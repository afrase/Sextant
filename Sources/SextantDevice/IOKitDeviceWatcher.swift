import Foundation
import IOKit
import SextantApplication
import SextantDomain
import os

/// One USB device as the IORegistry describes it.
struct USBDeviceRecord: Hashable, Sendable {
    /// IORegistry entry id.
    var id: UInt64
    var productID: UInt16
    var serial: String?
    var bcdDevice: UInt16
}

/// Raw presence notifications.
enum USBPresence: Hashable, Sendable {
    case matched(USBDeviceRecord)
    case terminated(id: UInt64)
}

/// Where presence notifications come from: IOKit in the app, a fake in tests.
protocol USBPresenceSource: Sendable {
    /// USB devices with `vendorID` and one of `productIDs`: those already present first, then changes.
    /// Ends, and releases its resources, when the consumer is cancelled.
    func presence(vendorID: UInt16, productIDs: Set<UInt16>) -> AsyncStream<USBPresence>
}

/// Read-only USB presence for a board's keyboard and bootloader product ids (IOKit matching notifications).
/// It never opens a device.
public struct IOKitDeviceWatcher: DeviceWatcher {
    private let source: any USBPresenceSource

    public init() { self.init(source: IOKitUSBPresence()) }

    init(source: any USBPresenceSource) { self.source = source }

    public func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        let raw = source.presence(vendorID: board.vendorID, productIDs: board.productIDs.union(board.bootloaderProductIDs.keys))
        return AsyncStream { continuation in
            let task = Task {
                var attached = Set<UInt64>()
                for await event in raw {
                    if let mapped = Self.map(event, board: board, attached: &attached) { continuation.yield(mapped) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Classifies a device by product id; removals are reported only for devices reported as attached.
    private static func map(_ event: USBPresence, board: BoardDefinition, attached: inout Set<UInt64>) -> DeviceEvent? {
        switch event {
        case let .matched(r):
            let device: ConnectedDevice
            if board.productIDs.contains(r.productID) {
                device = .keyboard(KeyboardDevice(id: r.id, productID: r.productID, serial: r.serial))
            } else if let kind = board.bootloaderProductIDs[r.productID] {
                device = .bootloader(BootloaderDevice(id: r.id, productID: r.productID, kind: kind, version: r.bcdDevice))
            } else {
                return nil
            }
            return attached.insert(r.id).inserted ? .attached(device) : nil
        case let .terminated(id):
            return attached.remove(id) == nil ? nil : .detached(id: id)
        }
    }
}

// MARK: - IOKit

/// `IOServiceAddMatchingNotification` on `IOUSBHostDevice`, delivered on a private serial queue.
struct IOKitUSBPresence: USBPresenceSource {
    func presence(vendorID: UInt16, productIDs: Set<UInt16>) -> AsyncStream<USBPresence> {
        AsyncStream { continuation in
            let watch = USBWatch(continuation: continuation)
            watch.queue.async { watch.start(vendorID: vendorID, productIDs: productIDs) }
            continuation.onTermination = { _ in watch.queue.async { watch.stop() } }
        }
    }
}

/// The notification port and its iterators. Touched only on `queue`; the stream's termination handler keeps
/// it alive until `stop()` has destroyed the port, after which no callback can reach it.
private final class USBWatch: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.sextant.device.watcher")
    private let continuation: AsyncStream<USBPresence>.Continuation
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private let log = Logger(subsystem: "com.sextant.app", category: "device")

    init(continuation: AsyncStream<USBPresence>.Continuation) { self.continuation = continuation }

    func start(vendorID: UInt16, productIDs: Set<UInt16>) {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            log.error("Couldn't create an IOKit notification port")
            return continuation.finish()
        }
        self.port = port
        IONotificationPortSetDispatchQueue(port, queue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let matched: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            Unmanaged<USBWatch>.fromOpaque(context).takeUnretainedValue().drain(iterator, matched: true)
        }
        let terminated: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            Unmanaged<USBWatch>.fromOpaque(context).takeUnretainedValue().drain(iterator, matched: false)
        }
        // Termination first, so a device unplugged between the two registrations is still reported as gone.
        for (type, callback) in [(kIOTerminatedNotification, terminated), (kIOFirstMatchNotification, matched)] {
            let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
            matching["idVendor"] = vendorID
            matching["idProductArray"] = productIDs.sorted()
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, matching, callback, context, &iterator)
            guard result == KERN_SUCCESS else {
                log.error("IOServiceAddMatchingNotification failed: \(result, privacy: .public)")
                stop()
                return continuation.finish()
            }
            iterators.append(iterator)
            // Draining reports the devices already present and arms the notification.
            drain(iterator, matched: type == kIOFirstMatchNotification)
        }
    }

    func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    fileprivate func drain(_ iterator: io_iterator_t, matched: Bool) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            guard matched else {
                continuation.yield(.terminated(id: id))
                continue
            }
            func property<T>(_ key: String) -> T? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T
            }
            guard let pid = (property("idProduct") as Int?).flatMap(UInt16.init(exactly:)) else { continue }
            let bcd = (property("bcdDevice") as Int?).flatMap(UInt16.init(exactly:))
            continuation.yield(
                .matched(
                    USBDeviceRecord(
                        id: id, productID: pid, serial: property("USB Serial Number"), bcdDevice: bcd ?? 0)))
        }
    }
}
