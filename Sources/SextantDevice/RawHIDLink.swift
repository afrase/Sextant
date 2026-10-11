import Foundation
import IOKit.hid
import SextantApplication
import SextantDomain
import os

/// The raw-HID interface of one keyboard: 32-byte reports, no report ID.
protocol HIDTransport: Sendable {
    /// Opens the interface without seizing it. `receive` then gets every input report, and `nil` once if the
    /// device goes away.
    func open(receive: @escaping @Sendable ([UInt8]?) -> Void) async throws(DeviceError)
    /// Writes one output report.
    func send(_ report: [UInt8]) async throws(DeviceError)
    func close() async
}

/// The live connection over Oryx's raw-HID protocol (research 03 §3, 00 §5). Writes to the keyboard (the version
/// and serial queries and pairing), so the composition root wires it only after the user approves (ADR 0012).
public struct RawHIDLink: KeyboardLink {
    private let clock: any Clock<Duration>
    private let makeTransport: @Sendable (KeyboardDevice, BoardDefinition) -> any HIDTransport

    public init() { self.init(clock: ContinuousClock()) { IOHIDTransport(device: $0, board: $1) } }

    init(clock: any Clock<Duration>, makeTransport: @escaping @Sendable (KeyboardDevice, BoardDefinition) -> any HIDTransport) {
        self.clock = clock
        self.makeTransport = makeTransport
    }

    public func session(with device: KeyboardDevice, board: BoardDefinition) -> AsyncStream<LiveEvent> {
        let session = OryxSession(transport: makeTransport(device, board), board: board, clock: clock)
        return AsyncStream { out in
            let task = Task { await session.run(out) }
            out.onTermination = { _ in task.cancel() }
        }
    }
}

/// Oryx raw-HID protocol reports (research 03 §3.3, §3.4).
enum OryxReport {
    static let size = 32
    static let getFirmwareVersion: UInt8 = 0x00
    static let pairingInit: UInt8 = 0x01
    static let getProtocolVersion: UInt8 = 0xFE
    private static let stop: UInt8 = 0xFE

    static func command(_ id: UInt8) -> [UInt8] { [id] + [UInt8](repeating: 0, count: size - 1) }

    /// The event in an input report, or nil when it carries none (pairing success, errors, RGB replies) or is
    /// malformed. Payloads end at the first 0xFE; the firmware leaves stack garbage after it. `08` and `0B` have no
    /// stop byte, but carry nothing Sextant shows.
    static func parse(_ report: [UInt8], board: BoardDefinition) -> LiveEvent? {
        guard let id = report.first, let end = report.dropFirst().firstIndex(of: stop) else { return nil }
        let p = Array(report[1..<end])
        switch (id, p.count) {
        case (0xFE, 1): return .protocolVersion(p[0])
        case (0x00, 1...) where p.allSatisfy({ (0x20..<0x7F).contains($0) }):
            return String(bytes: p, encoding: .ascii).map(LiveEvent.firmwareSerial)
        case (0x05, 1): return .layer(Int(p[0]))
        case (0x06, 2), (0x07, 2):
            let column = Int(p[0]), row = Int(p[1])
            guard row < board.matrixRows, column < board.matrixColumns else { return nil }
            return id == 0x06 ? .keyDown(row: row, column: column) : .keyUp(row: row, column: column)
        default: return nil
        }
    }
}

/// One session (00 §5): drain stale reports, query the protocol version (400 ms, retried once) and the firmware
/// serial, pair, wait up to 700 ms for the layer, then stream events until removal or cancellation.
private struct OryxSession: Sendable {
    let transport: any HIDTransport
    let board: BoardDefinition
    let clock: any Clock<Duration>

    private enum Input { case report([UInt8]), removed, deadline(Int) }
    private enum Phase { case draining, version(attempt: Int), pairing, live }

    /// fw21 and older paired with a key sequence; from protocol 2 (fw22) on, `01` pairs and the events are the same.
    static let minimumVersion: UInt8 = 0x02
    private static let drainTime = Duration.milliseconds(20)
    private static let versionTimeout = Duration.milliseconds(400)
    private static let pairingTimeout = Duration.milliseconds(700)
    /// The firmware queues only 4 output reports; voyager-disco paces at 5 ms on hardware.
    private static let writeSpacing = Duration.milliseconds(5)

    func run(_ out: AsyncStream<LiveEvent>.Continuation) async {
        let (inputs, feed) = AsyncStream.makeStream(of: Input.self)
        var reason: DeviceError?
        do {
            try await transport.open { feed.yield($0.map(Input.report) ?? .removed) }
            reason = try await converse(inputs, feed, out)
        } catch let error as DeviceError {
            reason = error
        } catch {
            reason = nil  // cancelled
        }
        await transport.close()
        out.yield(.ended(reason))
        out.finish()
    }

    /// Returns why the session gave up, or nil when the device went away or the consumer cancelled.
    private func converse(
        _ inputs: AsyncStream<Input>, _ feed: AsyncStream<Input>.Continuation, _ out: AsyncStream<LiveEvent>.Continuation
    ) async throws -> DeviceError? {
        var timer: Task<Void, Never>?
        var deadline = 0
        defer { timer?.cancel() }
        func arm(_ duration: Duration) {
            timer?.cancel()
            deadline += 1
            let id = deadline
            timer = Task { if (try? await clock.sleep(for: duration)) != nil { feed.yield(.deadline(id)) } }
        }

        var phase = Phase.draining
        arm(Self.drainTime)
        for await input in inputs {
            switch input {
            case .removed:
                return nil
            case let .deadline(id):
                guard id == deadline else { continue }
                switch phase {
                case .draining:
                    try await send(OryxReport.getProtocolVersion)
                    phase = .version(attempt: 1)
                    arm(Self.versionTimeout)
                case .version(attempt: 1):
                    try await send(OryxReport.getProtocolVersion)
                    phase = .version(attempt: 2)
                    arm(Self.versionTimeout)
                case .version:
                    return .io(String(localized: "The keyboard didn't answer. Its firmware may not have Oryx's live protocol."))
                case .pairing:
                    return .io(String(localized: "The keyboard didn't start sending live events."))
                case .live:
                    break
                }
            case let .report(bytes):
                if case .draining = phase { continue }
                guard let event = OryxReport.parse(bytes, board: board) else { continue }
                out.yield(event)
                switch (phase, event) {
                case let (.version, .protocolVersion(version)):
                    guard version >= Self.minimumVersion else {
                        return .io(String(localized: "This keyboard's firmware is too old for the live view (protocol \(version))."))
                    }
                    try await send(OryxReport.getFirmwareVersion)
                    try await send(OryxReport.pairingInit)
                    phase = .pairing
                    arm(Self.pairingTimeout)
                case (.pairing, .layer):
                    // shortcut: an app that seizes the interface after this goes unnoticed (reports just stop), since
                    // live mode never writes; watch kIOMessageServiceIsRequestingClose if LiveSession needs to say so.
                    phase = .live
                    timer?.cancel()
                default:
                    break
                }
            }
        }
        return nil
    }

    private func send(_ command: UInt8) async throws {
        try await transport.send(OryxReport.command(command))
        try await clock.sleep(for: Self.writeSpacing)
    }
}

extension DeviceError {
    /// Maps an IOKit result. `kIOReturnExclusiveAccess` (0xE00002C5) means another app (Keymapp) seized the interface.
    init(_ result: IOReturn) {
        switch result {
        case kIOReturnExclusiveAccess: self = .heldByAnotherApp
        case kIOReturnNoDevice, kIOReturnNotAttached: self = .notFound
        default: self = .io(String(format: "IOKit 0x%08X", UInt32(bitPattern: result)))
        }
    }
}

// MARK: - IOKit

/// The board's raw-HID interface through IOHIDManager, opened without seizing. Its callbacks and writes run on the
/// actor's own serial queue.
actor IOHIDTransport: HIDTransport {
    private let device: KeyboardDevice
    private let board: BoardDefinition
    private let queue = DispatchSerialQueue(label: "com.sextant.device.rawhid")
    private var manager: IOHIDManager?
    private var hid: IOHIDDevice?

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(device: KeyboardDevice, board: BoardDefinition) {
        self.device = device
        self.board = board
    }

    func open(receive: @escaping @Sendable ([UInt8]?) -> Void) throws(DeviceError) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        guard let hid = Self.rawInterface(of: device, board: board, manager: manager) else { throw .notFound }
        // Never seize: Keymapp and Oryx in Chrome must keep working (research 03 §5.4).
        let result = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw DeviceError(result) }

        let sink = ReportSink(receive)
        let context = Unmanaged.passRetained(sink).toOpaque()
        IOHIDDeviceSetDispatchQueue(hid, queue)
        IOHIDDeviceRegisterInputReportCallback(
            hid, sink.buffer, OryxReport.size,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                let count = max(0, min(length, OryxReport.size))
                Unmanaged<ReportSink>.fromOpaque(context).takeUnretainedValue().receive(
                    Array(UnsafeBufferPointer(start: report, count: count)))
            }, context)
        IOHIDDeviceRegisterRemovalCallback(
            hid,
            { context, _, _ in
                guard let context else { return }
                Unmanaged<ReportSink>.fromOpaque(context).takeUnretainedValue().receive(nil)
            }, context)
        let release = SendableRelease(device: hid, context: context)
        IOHIDDeviceSetCancelHandler(hid) { release.run() }
        IOHIDDeviceActivate(hid)
        self.hid = hid
    }

    func send(_ report: [UInt8]) throws(DeviceError) {
        guard let hid else { throw .notFound }
        let result = report.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map { IOHIDDeviceSetReport(hid, kIOHIDReportTypeOutput, 0, $0, buffer.count) } ?? kIOReturnBadArgument
        }
        guard result == kIOReturnSuccess else { throw DeviceError(result) }
    }

    func close() {
        if let hid { IOHIDDeviceCancel(hid) }  // the cancel handler closes the device and frees the sink
        hid = nil
        manager = nil
    }

    /// The keyboard's raw-HID interface, found without opening anything. Matching is on the vendor usage page only:
    /// opening the keyboard or trackpad interfaces needs Input Monitoring.
    static func rawInterface(of device: KeyboardDevice, board: BoardDefinition, manager: IOHIDManager) -> IOHIDDevice? {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: board.vendorID, kIOHIDProductIDKey: device.productID,
            kIOHIDPrimaryUsagePageKey: board.rawHIDUsagePage, kIOHIDPrimaryUsageKey: board.rawHIDUsage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let candidates = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        return candidates.first { service(IOHIDDeviceGetService($0), isUnder: device.id) }
    }

    /// Whether `service` (the HID interface) belongs to the USB device with registry id `id`.
    private static func service(_ service: io_service_t, isUnder id: UInt64) -> Bool {
        var entry = service
        IOObjectRetain(entry)
        defer { IOObjectRelease(entry) }
        for _ in 0..<4 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
            IOObjectRelease(entry)
            entry = parent
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS, entryID == id { return true }
        }
        return false
    }
}

/// The input-report buffer and the session's callback, owned by IOHID until the device's cancel handler runs.
private final class ReportSink {
    let receive: @Sendable ([UInt8]?) -> Void
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: OryxReport.size)

    init(_ receive: @escaping @Sendable ([UInt8]?) -> Void) { self.receive = receive }

    deinit { buffer.deallocate() }
}

/// Closes the device and frees its sink; runs once, from IOHID's cancel handler on the transport's queue.
private struct SendableRelease: @unchecked Sendable {
    let device: IOHIDDevice
    let context: UnsafeMutableRawPointer

    func run() {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        Unmanaged<ReportSink>.fromOpaque(context).release()
    }
}
