import Foundation
import IOKit.hid
import SextantApplication
import SextantDomain

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
/// and serial queries, pairing, and commands once paired), so the composition root wires it only after the user
/// approves (ADR 0012, 0038).
public struct RawHIDLink: KeyboardLink {
    private let clock: any Clock<Duration>
    private let makeTransport: @Sendable (KeyboardDevice, BoardDefinition) -> any HIDTransport
    private let trace: (@Sendable (HIDTraceEntry) -> Void)?

    /// - Parameter trace: gets every report as it is written and as it arrives, trimmed (the Developer raw-HID log, ADR
    ///   0045). Called from the transport's callback queue.
    public init(trace: (@Sendable (HIDTraceEntry) -> Void)? = nil) {
        self.init(clock: ContinuousClock(), trace: trace) { IOHIDTransport(device: $0, board: $1) }
    }

    init(
        clock: any Clock<Duration>, trace: (@Sendable (HIDTraceEntry) -> Void)? = nil,
        makeTransport: @escaping @Sendable (KeyboardDevice, BoardDefinition) -> any HIDTransport
    ) {
        self.clock = clock
        self.trace = trace
        self.makeTransport = makeTransport
    }

    public func session(
        with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>
    ) -> AsyncStream<LiveEvent> {
        let session = OryxSession(transport: makeTransport(device, board), board: board, clock: clock, trace: trace)
        return AsyncStream { out in
            let task = Task { await session.run(out, commands: commands) }
            out.onTermination = { _ in task.cancel() }
        }
    }
}

/// Oryx raw-HID protocol reports (research 03 §3.3, §3.4), and Sextant's own layout read (ADR 0061).
enum OryxReport {
    static let size = 32
    static let getFirmwareVersion: UInt8 = 0x00
    static let pairingInit: UInt8 = 0x01
    static let getProtocolVersion: UInt8 = 0xFE
    private static let setLayer: UInt8 = 0x04
    private static let rgbControl: UInt8 = 0x05
    private static let setRGBLED: UInt8 = 0x06
    private static let setRGBLEDAll: UInt8 = 0x09
    /// A Sextant build's own requests and replies (ADR 0061): outside every Oryx command and event id.
    private static let sextant: UInt8 = 0x53
    /// `53 01`: a part of the stored layout record.
    private static let recordPartRequest: UInt8 = 0x01
    /// A layout record reply's header: `53 01 status size(2) offset(2) count`.
    private static let layoutRecordHeader = 8
    /// The most record bytes one reply carries.
    private static let layoutRecordPart = 24
    private static let stop: UInt8 = 0xFE

    static func command(_ id: UInt8) -> [UInt8] { padded([id]) }

    /// The report for a command, or nil when the firmware wouldn't bounds-check it (ADR 0038). Only `04 01`, `05`,
    /// `06`, `09` and Sextant's read `53 01` are ever built: `04 00` (layer off) and every other command id are out of
    /// reach.
    static func encode(_ command: KeyboardCommand, board: BoardDefinition) -> [UInt8]? {
        guard command.isAllowed(on: board) else { return nil }
        return switch command {
        case let .moveToLayer(layer): padded([setLayer, 0x01, UInt8(layer)])  // 01: layer_move
        case let .lighting(on): padded([rgbControl, on ? 0x01 : 0x00])
        case let .setLED(index, red, green, blue): padded([setRGBLED, UInt8(index), red, green, blue])
        case let .setAllLEDs(red, green, blue): padded([setRGBLEDAll, red, green, blue])
        case let .readLayoutRecord(offset):
            padded([sextant, recordPartRequest, UInt8(truncatingIfNeeded: offset >> 8), UInt8(truncatingIfNeeded: offset)])
        }
    }

    private static func padded(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: size - bytes.count) }

    /// What the raw-HID log keeps of a report: a sent one without its zero padding (by command, since a trailing 0 can
    /// be a value), a received one up to and including its stop byte. The firmware's stack garbage after it is never
    /// kept: `08`, `0B` and `FF` have no stop byte and keep exactly two bytes, and any other received report with no
    /// stop byte keeps only its id. A layout record's part keeps only its 8-byte header: the record holds macro text,
    /// which is never logged (ADR 0042, 0045, 0061).
    static func trimmed(_ report: [UInt8], sent: Bool) -> [UInt8] {
        guard let id = report.first else { return [] }
        let length =
            switch (sent, id) {
            case (true, _): commandLengths[id] ?? 1
            // `0B` answers `0A`, which Sextant never sends, but another host's reply reaches every open client.
            case (false, 0x08), (false, 0x0B), (false, 0xFF): 2
            case (false, 0x53): layoutRecordHeader
            case (false, _): (report.dropFirst().firstIndex(of: stop) ?? 0) + 1
            }
        return Array(report.prefix(length))
    }

    /// The bytes `encode` pads for each command; the handshake's queries are one byte.
    private static let commandLengths: [UInt8: Int] = [setLayer: 3, rgbControl: 2, setRGBLED: 5, setRGBLEDAll: 4, sextant: 4]

    /// A received report as the raw-HID log keeps it: trimmed, with its event, except a layout record's part, which
    /// keeps none, since its bytes are the layout's.
    static func traceEntry(received report: [UInt8], board: BoardDefinition) -> HIDTraceEntry {
        let event = parse(report, board: board)
        let kept: LiveEvent? = if case .layoutRecord = event { nil } else { event }
        return HIDTraceEntry(direction: .received, bytes: trimmed(report, sent: false), event: kept)
    }

    /// The event in an input report, or nil when it carries none (pairing success, unused replies) or is malformed.
    /// Payloads end at the first 0xFE; the firmware leaves stack garbage after it. `08` and `FF` have no stop byte:
    /// exactly byte 1 counts. `53` has none either: its header says how many bytes count.
    static func parse(_ report: [UInt8], board: BoardDefinition) -> LiveEvent? {
        switch (report.first, report.count) {
        case (0x08, 2...): return .lighting(report[1] != 0)
        case (0xFF, 2...): return .error(report[1])
        case (0x53, _): return layoutRecord(report)
        default: break
        }
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

    /// A Sextant build's reply to `53 01` (ADR 0061): `53 01 status size(2) offset(2) count`, big-endian, then `count`
    /// record bytes. Status 0 carries up to 24 of them, 1 none (the offset is at or past the end); 2 (an unknown
    /// request) and a reply whose count doesn't fit carry no event.
    private static func layoutRecord(_ report: [UInt8]) -> LiveEvent? {
        guard report.count >= layoutRecordHeader, report[1] == recordPartRequest else { return nil }
        let size = Int(report[3]) << 8 | Int(report[4])
        let offset = Int(report[5]) << 8 | Int(report[6])
        let count = Int(report[7])
        let bytes: [UInt8]
        switch report[2] {
        case 0 where count <= layoutRecordPart && layoutRecordHeader + count <= report.count:
            bytes = Array(report[layoutRecordHeader..<layoutRecordHeader + count])
        case 1: bytes = []
        default: return nil
        }
        return .layoutRecord(LayoutRecordChunk(offset: offset, size: size, bytes: bytes))
    }
}

/// One session (00 §5): drain stale reports, query the protocol version (400 ms, retried once) and the firmware
/// serial, pair, wait up to 700 ms for the layer, then stream events and write commands until removal, a failed
/// write or cancellation.
private struct OryxSession: Sendable {
    let transport: any HIDTransport
    let board: BoardDefinition
    let clock: any Clock<Duration>
    let trace: (@Sendable (HIDTraceEntry) -> Void)?

    private enum Input { case report([UInt8]), removed, deadline(Int), command(KeyboardCommand), writeFailed(DeviceError) }

    /// The one pending timeout: arming another cancels it, and only the newest id counts.
    private struct Deadline {
        private(set) var id = 0
        private var task: Task<Void, Never>?

        mutating func arm(_ duration: Duration, clock: any Clock<Duration>, feed: AsyncStream<Input>.Continuation) {
            task?.cancel()
            id += 1
            let id = id
            task = Task { if (try? await clock.sleep(for: duration)) != nil { feed.yield(.deadline(id)) } }
        }

        func cancel() { task?.cancel() }
    }
    private enum Phase { case draining, version(attempt: Int), pairing, live }

    /// fw21 and older paired with a key sequence; from protocol 2 (fw22) on, `01` pairs and the events are the same.
    static let minimumVersion: UInt8 = 0x02
    private static let openAttempts = 10
    private static let drainTime = Duration.milliseconds(20)
    private static let versionTimeout = Duration.milliseconds(400)
    private static let pairingTimeout = Duration.milliseconds(700)
    /// The firmware queues only 4 output reports; voyager-disco paces at 5 ms on hardware.
    private static let writeSpacing = Duration.milliseconds(5)

    func run(_ out: AsyncStream<LiveEvent>.Continuation, commands: AsyncStream<KeyboardCommand>) async {
        let (inputs, feed) = AsyncStream.makeStream(of: Input.self)
        // Commands join the same loop as reports, so each one meets the session's phase in order.
        let forward = Task { for await command in commands { feed.yield(.command(command)) } }
        defer { forward.cancel() }
        var reason: DeviceError?
        do {
            try await open { bytes in
                // Logged as it arrives, not when the loop gets to it, so the log keeps the wire's order and times.
                if let trace, let bytes { trace(OryxReport.traceEntry(received: bytes, board: board)) }
                feed.yield(bytes.map(Input.report) ?? .removed)
            }
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

    /// Opens the interface, waiting up to a second for it: the HID interface is published tens of milliseconds
    /// after the USB device the watcher reports.
    private func open(_ receive: @escaping @Sendable ([UInt8]?) -> Void) async throws {
        for attempt in 1...Self.openAttempts {
            // Not `catch .notFound where …`: that pattern crashes Swift 6.3's compiler here.
            do {
                return try await transport.open(receive: receive)
            } catch {
                guard case .notFound = error, attempt < Self.openAttempts else { throw error }
            }
            try await clock.sleep(for: .milliseconds(100))
        }
    }

    /// Returns why the session gave up, or nil when the device went away or the consumer cancelled.
    private func converse(
        _ inputs: AsyncStream<Input>, _ feed: AsyncStream<Input>.Continuation, _ out: AsyncStream<LiveEvent>.Continuation
    ) async throws -> DeviceError? {
        var deadline = Deadline()
        // Paired writes go out from their own task, so their 5 ms pacing never holds back the reports behind them.
        // The handshake's writes are all done before the first one.
        let (writes, writer) = AsyncStream.makeStream(of: [UInt8].self)
        let writing = Task {
            do {
                for await report in writes where !Task.isCancelled { try await send(report) }
            } catch let error as DeviceError {
                feed.yield(.writeFailed(error))
            } catch {}  // cancelled
        }
        defer {
            deadline.cancel()
            writing.cancel()
        }

        var phase = Phase.draining
        deadline.arm(Self.drainTime, clock: clock, feed: feed)
        for await input in inputs {
            switch input {
            case .removed:
                return nil
            case let .writeFailed(error):
                return error
            case let .command(command):
                // Only a paired session writes; a command before then is dropped, never queued.
                guard case .live = phase, let report = OryxReport.encode(command, board: board) else { continue }
                writer.yield(report)
                // The firmware drops a layer event that matches a value pairing never updates (research 03 O2), so a
                // move can go unreported; pairing again always reports the layer.
                if case .moveToLayer = command { writer.yield(OryxReport.command(OryxReport.pairingInit)) }
            case let .deadline(id):
                guard id == deadline.id else { continue }
                switch phase {
                case .draining:
                    try await send(OryxReport.getProtocolVersion)
                    phase = .version(attempt: 1)
                    deadline.arm(Self.versionTimeout, clock: clock, feed: feed)
                case .version(attempt: 1):
                    try await send(OryxReport.getProtocolVersion)
                    phase = .version(attempt: 2)
                    deadline.arm(Self.versionTimeout, clock: clock, feed: feed)
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
                switch (phase, event) {
                case (.pairing, .layer):
                    // shortcut: an app that seizes the interface after this goes unnoticed (reports just stop) until a
                    // command's write fails; watch kIOMessageServiceIsRequestingClose if LiveSession must say so sooner.
                    phase = .live
                    deadline.cancel()
                case (.live, _), (_, .protocolVersion), (_, .firmwareSerial), (_, .lighting), (_, .error), (_, .layoutRecord), (_, .ended):
                    break
                case (_, .layer), (_, .keyDown), (_, .keyUp):
                    // A board another host paired already reports these during the handshake. Each tells LiveSession the
                    // session is paired and takes commands, so they wait for this session's own pairing (ADR 0051).
                    continue
                }
                out.yield(event)
                guard case .version = phase, case let .protocolVersion(version) = event else { continue }
                guard version >= Self.minimumVersion else {
                    return .io(String(localized: "This keyboard's firmware is too old for the live view (protocol \(version))."))
                }
                try await send(OryxReport.getFirmwareVersion)
                try await send(OryxReport.pairingInit)
                phase = .pairing
                deadline.arm(Self.pairingTimeout, clock: clock, feed: feed)
            }
        }
        return nil
    }

    private func send(_ command: UInt8) async throws { try await send(OryxReport.command(command)) }

    private func send(_ report: [UInt8]) async throws {
        // Logged before the write: the reply can arrive before the write returns. A write that fails ends the session.
        trace?(HIDTraceEntry(direction: .sent, bytes: OryxReport.trimmed(report, sent: true)))
        try await transport.send(report)
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
    private static func rawInterface(of device: KeyboardDevice, board: BoardDefinition, manager: IOHIDManager) -> IOHIDDevice? {
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
