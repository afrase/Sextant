import Foundation
import IOKit.hid
import SextantApplication
import SextantDomain
import os

/// The Navigator trackpad's Precision Touchpad reports (research 06; zsa/qmk_modules `navigator_trackpad_ptp.c`).
enum TrackpadReport {
    /// Report 1: two fingers of six bytes each, scan time, then contact count and buttons.
    static let contactsID: UInt8 = 1
    static let contactsSize = 16
    /// Report 4, a feature: the input mode, 0 for mouse and 3 for Precision Touchpad.
    static let inputModeID: UInt8 = 4

    /// The fingers touching (tip and confidence both set) and the scan time; nil for any other report.
    static func parse(_ bytes: [UInt8]) -> (contacts: [TrackpadContact], scanTime: Int)? {
        guard bytes.count >= contactsSize, bytes[0] == contactsID else { return nil }
        var contacts: [TrackpadContact] = []
        for offset in [1, 7] where bytes[offset] & 0x03 == 0x03 {
            let x = Int(bytes[offset + 2]) | Int(bytes[offset + 3]) << 8
            let y = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8
            contacts.append(TrackpadContact(id: Int(bytes[offset + 1] & 0x07), x: Double(x), y: Double(y)))
        }
        return (contacts, Int(bytes[13]) | Int(bytes[14]) << 8)
    }

    static func inputMode(_ mode: TrackpadInputMode) -> [UInt8] { [inputModeID, mode == .touchpad ? 3 : 0] }
}

/// The Navigator trackpad's digitizer interface (usage page 0x0D, Touch Pad) through IOHIDManager, opened without
/// seizing (ADR 0068). Callbacks and writes run on the actor's own serial queue. Opening it needs Input Monitoring, so
/// nothing is opened until a session starts.
public actor IOHIDTrackpadLink: TrackpadLink {
    private let queue = DispatchSerialQueue(label: "com.sextant.device.trackpad")
    private let vendorID: Int
    private var current: TrackpadSession?
    private let logger = Logger(subsystem: "com.sextant.app", category: "device")

    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    public init(board: BoardDefinition) { vendorID = Int(board.vendorID) }

    public func hasInputAccess() -> Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    public func requestInputAccess() -> Bool {
        hasInputAccess() || IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    nonisolated public func session() -> AsyncStream<TrackpadEvent> {
        // Unbounded: an attach or detach must never be dropped; the runner reads as fast as reports come.
        let (stream, continuation) = AsyncStream.makeStream(of: TrackpadEvent.self)
        let id = UUID()
        let task = Task { await self.open(id, continuation) }
        continuation.onTermination = { _ in
            task.cancel()
            Task { await self.close(id) }
        }
        return stream
    }

    public func setInputMode(_ mode: TrackpadInputMode, on pad: TrackpadID) throws(TrackpadError) {
        guard let current, let device = current.devices[pad] else { throw .notAttached }
        let result = Self.write(mode, to: device)
        guard result == kIOReturnSuccess else {
            throw .io(String(format: "IOKit 0x%08X", UInt32(bitPattern: result)))
        }
        current.switched(pad, to: mode)
    }

    /// Feature report 4, with the report id as the first byte as IOKit expects.
    static func write(_ mode: TrackpadInputMode, to device: IOHIDDevice) -> IOReturn {
        let report = TrackpadReport.inputMode(mode)
        return report.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(TrackpadReport.inputModeID), $0, buffer.count)
            } ?? kIOReturnBadArgument
        }
    }

    private func open(_ id: UUID, _ continuation: AsyncStream<TrackpadEvent>.Continuation) {
        guard !Task.isCancelled else { return continuation.finish() }
        current?.close()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: vendorID, kIOHIDPrimaryUsagePageKey: kHIDPage_Digitizer, kIOHIDPrimaryUsageKey: kHIDUsage_Dig_TouchPad,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let session = TrackpadSession(id: id, manager: manager, continuation: continuation)
        // Retained until the manager's cancel handler: no callback can outlive its context.
        let context = Unmanaged.passRetained(session).toOpaque()
        let release = SessionRelease(manager: manager, context: context)
        IOHIDManagerSetCancelHandler(manager) { release.run() }
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<TrackpadSession>.fromOpaque(context).takeUnretainedValue().attached(device)
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<TrackpadSession>.fromOpaque(context).takeUnretainedValue().detached(device)
            }, context)
        IOHIDManagerRegisterInputReportCallback(
            manager,
            { context, _, sender, _, _, report, length in
                guard let context, let sender else { return }
                let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: max(0, length)))
                Unmanaged<TrackpadSession>.fromOpaque(context).takeUnretainedValue().received(bytes, from: device)
            }, context)
        IOHIDManagerSetDispatchQueue(manager, queue)
        // Never seize: ZSA's companion app and the system keep their view of the interface.
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerActivate(manager)
        current = session
        guard result == kIOReturnSuccess else {
            logger.error("Trackpad: IOHIDManagerOpen 0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)")
            session.fail(
                result == kIOReturnNotPermitted ? .inputMonitoringDenied : .io(String(format: "IOKit 0x%08X", UInt32(bitPattern: result))))
            return
        }
    }

    private func close(_ id: UUID) {
        guard let current, current.id == id else { return }
        current.close()
        self.current = nil
    }
}

/// One session's manager, its devices and its stream. Every callback and every access runs on the link's queue, so the
/// mutable state needs no lock; it outlives the manager's callbacks because the link holds it until `close`.
private final class TrackpadSession: @unchecked Sendable {
    let id: UUID
    private let manager: IOHIDManager
    private let continuation: AsyncStream<TrackpadEvent>.Continuation
    private(set) var devices: [TrackpadID: IOHIDDevice] = [:]
    /// Each device's id, looked up once rather than at every report.
    private var ids: [IOHIDDevice: TrackpadID] = [:]
    /// Pads this session put in touchpad mode, which closing puts back.
    private var inTouchpadMode: Set<TrackpadID> = []
    private var isClosed = false

    init(id: UUID, manager: IOHIDManager, continuation: AsyncStream<TrackpadEvent>.Continuation) {
        self.id = id
        self.manager = manager
        self.continuation = continuation
    }

    func attached(_ device: IOHIDDevice) {
        guard !isClosed else { return }
        let pad = Self.id(of: device)
        devices[pad] = device
        ids[device] = pad
        continuation.yield(.attached(pad))
    }

    func detached(_ device: IOHIDDevice) {
        guard let pad = ids.removeValue(forKey: device) ?? Optional(Self.id(of: device)),
            devices.removeValue(forKey: pad) != nil
        else { return }
        inTouchpadMode.remove(pad)
        continuation.yield(.detached(pad))
    }

    func received(_ bytes: [UInt8], from device: IOHIDDevice) {
        guard !isClosed, let pad = ids[device], let report = TrackpadReport.parse(bytes) else { return }
        let frame = TrackpadFrame(contacts: report.contacts, scanTime: report.scanTime, timestamp: 0)
        continuation.yield(.frame(frame, from: pad))
    }

    func switched(_ pad: TrackpadID, to mode: TrackpadInputMode) {
        if mode == .touchpad { inTouchpadMode.insert(pad) } else { inTouchpadMode.remove(pad) }
    }

    func fail(_ error: TrackpadError) {
        continuation.yield(.failed(error))
        close()
    }

    /// Puts every pad this session switched back in mouse mode while the devices are still open, then stops the
    /// callbacks; the cancel handler closes the manager and frees the context.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        for pad in inTouchpadMode {
            if let device = devices[pad] { _ = IOHIDTrackpadLink.write(.mouse, to: device) }
        }
        inTouchpadMode = []
        devices = [:]
        ids = [:]
        continuation.finish()
        IOHIDManagerCancel(manager)
    }

    private static func id(of device: IOHIDDevice) -> TrackpadID {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return TrackpadID(id)
    }
}

/// Closes the manager and frees its session context; runs once, from IOHID's cancel handler on the link's queue.
private struct SessionRelease: @unchecked Sendable {
    let manager: IOHIDManager
    let context: UnsafeMutableRawPointer

    func run() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        Unmanaged<TrackpadSession>.fromOpaque(context).release()
    }
}
