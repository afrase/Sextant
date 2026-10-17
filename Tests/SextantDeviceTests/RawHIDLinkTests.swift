import Clocks
import IOKit
import SextantApplication
import SextantDomain
import Testing

@testable import SextantDevice

/// A keyboard's raw-HID interface played from a script: the n-th report sent gets `script[n]` back (nil = unplugged).
final class FakeHID: HIDTransport {
    let onOpen: [[UInt8]?]
    let script: [[[UInt8]?]]
    let openError: DeviceError?
    let sendError: DeviceError?
    /// Sends that succeed before `sendError` applies.
    let sendErrorAfter: Int
    /// Opens that fail with `.notFound` first, as when the interface isn't published yet.
    let notFoundFirst: Int
    /// Stamps each send with this clock's time.
    let clock: TestClock<Duration>?
    let opens = Locked(0)
    let sent = Locked<[[UInt8]]>([])
    let sentAt = Locked<[TestClock<Duration>.Instant]>([])
    let closed = Locked(false)
    private let receive = Locked<(@Sendable ([UInt8]?) -> Void)?>(nil)

    init(
        onOpen: [[UInt8]?] = [], script: [[[UInt8]?]] = [], openError: DeviceError? = nil, sendError: DeviceError? = nil,
        sendErrorAfter: Int = 0, notFoundFirst: Int = 0, clock: TestClock<Duration>? = nil
    ) {
        self.notFoundFirst = notFoundFirst
        self.onOpen = onOpen
        self.script = script
        self.openError = openError
        self.sendError = sendError
        self.sendErrorAfter = sendErrorAfter
        self.clock = clock
    }

    func open(receive: @escaping @Sendable ([UInt8]?) -> Void) throws(DeviceError) {
        opens.value += 1
        if opens.value <= notFoundFirst { throw .notFound }
        if let openError { throw openError }
        self.receive.value = receive
        onOpen.forEach(receive)
    }

    func send(_ report: [UInt8]) throws(DeviceError) {
        let n = sent.value.count
        if let sendError, n >= sendErrorAfter { throw sendError }
        sent.value.append(report)
        if let clock { sentAt.value.append(clock.now) }
        if n < script.count, let receive = receive.value { script[n].forEach(receive) }
    }

    func close() { closed.value = true }
}

/// An input report: the bytes, then garbage, as the firmware leaves its buffer.
func report(_ bytes: UInt8...) -> [UInt8] { bytes + [UInt8](repeating: 0xAB, count: 32 - bytes.count) }

struct RawHIDLinkTests {
    let keyboard = KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")
    static let serialReply = report(0x00, 0x4B, 0x6C, 0x67, 0x4D, 0x37, 0x2F, 0x34, 0x30, 0x78, 0x4A, 0x37, 0x4D, 0xFE)

    /// Every event of one session; `onLayer` runs at each layer event, once the session is paired.
    func events(
        _ hid: FakeHID, commands: AsyncStream<KeyboardCommand> = AsyncStream { _ in }, onLayer: () -> Void = {}
    ) async -> [LiveEvent] {
        var events: [LiveEvent] = []
        let link = RawHIDLink(clock: ImmediateClock(), makeTransport: { _, _ in hid })
        for await event in link.session(with: keyboard, board: .voyager, commands: commands) {
            if case .layer = event { onLayer() }
            events.append(event)
        }
        return events
    }

    @Test func handshakeThenEventsUntilUnplugged() async {
        let hid = FakeHID(
            onOpen: [report(0x05, 0x03, 0xFE)],  // stale: drained
            script: [
                [report(0xFE, 0x05, 0xFE)],
                [Self.serialReply],
                [
                    report(0x04, 0xFE), report(0x05, 0x00, 0xFE), report(0x06, 0x01, 0x00, 0xFE), report(0xFF, 0xFF),
                    report(0x07, 0x01, 0x00, 0xFE), nil,
                ],
            ])
        #expect(
            await events(hid) == [
                .protocolVersion(5), .firmwareSerial("KlgM7/40xJ7M"), .layer(0), .keyDown(row: 0, column: 1), .error(0xFF),
                .keyUp(row: 0, column: 1), .ended(nil),
            ])
        #expect(hid.sent.value == [OryxReport.command(0xFE), OryxReport.command(0x00), OryxReport.command(0x01)])
        #expect(hid.sent.value.allSatisfy { $0.count == 32 })
        #expect(hid.closed.value)
    }

    @Test func retriesTheVersionQueryOnce() async {
        let hid = FakeHID(script: [[], [report(0xFE, 0x05, 0xFE)], [], [report(0x05, 0x02, 0xFE), nil]])
        #expect(await events(hid) == [.protocolVersion(5), .layer(2), .ended(nil)])
        #expect(hid.sent.value.map { $0[0] } == [0xFE, 0xFE, 0x00, 0x01])
    }

    /// A board another host paired already reports layers and presses during the handshake: none comes out before this
    /// session's own pairing, since each tells LiveSession commands will be written.
    @Test func reportsNoLayerOrPressBeforePairing() async {
        let hid = FakeHID(script: [
            [report(0x05, 0x02, 0xFE)], [report(0xFE, 0x05, 0xFE)], [report(0x06, 0x01, 0x00, 0xFE)],
            [report(0x07, 0x01, 0x00, 0xFE), report(0x04, 0xFE), report(0x05, 0x02, 0xFE), nil],
        ])
        #expect(await events(hid) == [.protocolVersion(5), .layer(2), .ended(nil)])
        #expect(hid.sent.value.map { $0[0] } == [0xFE, 0xFE, 0x00, 0x01])
    }

    @Test func givesUpWithoutAVersionAndNeverPairs() async {
        let hid = FakeHID()
        let events = await events(hid)
        #expect(events.count == 1)
        guard case .ended(.io) = events.last else { Issue.record("\(events)"); return }
        #expect(hid.sent.value.map { $0[0] } == [0xFE, 0xFE])
        #expect(hid.closed.value)
    }

    @Test(arguments: [0x00, 0x01] as [UInt8])
    func refusesProtocolsBeforePairingByCommand(_ version: UInt8) async {
        let hid = FakeHID(script: [[report(0xFE, version, 0xFE)]])
        let events = await events(hid)
        #expect(events.first == .protocolVersion(version))
        guard case .ended(.io) = events.last else { Issue.record("\(events)"); return }
        #expect(hid.sent.value.map { $0[0] } == [0xFE])
    }

    /// fw22 (2), fw23–24 (4), fw25 (5) and a newer firmware: never an equality check.
    @Test(arguments: [0x02, 0x04, 0x05, 0x06] as [UInt8])
    func acceptsProtocolsFromVersion2(_ version: UInt8) async {
        let hid = FakeHID(script: [[report(0xFE, version, 0xFE)], [], [report(0x05, 0x01, 0xFE), nil]])
        #expect(await events(hid) == [.protocolVersion(version), .layer(1), .ended(nil)])
    }

    @Test func givesUpWhenPairingSendsNoLayer() async {
        let hid = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x04, 0xFE)]])
        let events = await events(hid)
        guard case .ended(.io) = events.last else { Issue.record("\(events)"); return }
        #expect(hid.sent.value.map { $0[0] } == [0xFE, 0x00, 0x01])
    }

    /// The HID interface appears a little after the USB device: retried for a second, then given up.
    @Test func waitsForTheInterfaceAfterAttach() async {
        let late = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x05, 0x00, 0xFE), nil]], notFoundFirst: 3)
        #expect(await events(late) == [.protocolVersion(5), .layer(0), .ended(nil)])
        let missing = FakeHID(notFoundFirst: 10)
        #expect(await events(missing) == [.ended(.notFound)])
        #expect(missing.opens.value == 10)
    }

    @Test func reportsAnInterfaceSeizedByAnotherApp() async {
        let seized = FakeHID(openError: .heldByAnotherApp)
        #expect(await events(seized) == [.ended(.heldByAnotherApp)])
        #expect(seized.opens.value == 1)
        let seizedLater = FakeHID(sendError: .heldByAnotherApp)
        #expect(await events(seizedLater) == [.ended(.heldByAnotherApp)])
        #expect(seizedLater.closed.value)
        #expect(DeviceError(IOReturn(bitPattern: 0xE000_02C5)) == .heldByAnotherApp)
        #expect(DeviceError(kIOReturnNotAttached) == .notFound)
    }

    @Test func cancellingTheConsumerClosesTheInterface() async throws {
        let hid = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x05, 0x00, 0xFE)]])
        let link = RawHIDLink(clock: ImmediateClock(), makeTransport: { _, _ in hid })
        let layers = Locked(0)
        let consumer = Task {
            for await event in link.session(with: keyboard, board: .voyager, commands: AsyncStream { _ in })
            where event == .layer(0) { layers.value += 1 }
        }
        try await waitUntil { layers.value == 1 }
        consumer.cancel()
        try await waitUntil { hid.closed.value }
    }

    @Test func parsesToTheStopByteAndRejectsMalformedReports() {
        let board = BoardDefinition.voyager
        #expect(OryxReport.parse(report(0x06, 0x01, 0x00, 0xFE), board: board) == .keyDown(row: 0, column: 1))
        #expect(OryxReport.parse([0x07, 0x06, 0x0B, 0xFE], board: board) == .keyUp(row: 11, column: 6))
        #expect(OryxReport.parse(report(0x00, 0x4B, 0x6C, 0xFE), board: board) == .firmwareSerial("Kl"))
        // No stop byte: exactly byte 1, whatever follows.
        #expect(OryxReport.parse(report(0x08, 0x01), board: board) == .lighting(true))
        #expect(OryxReport.parse([0x08, 0x00, 0xFE], board: board) == .lighting(false))
        #expect(OryxReport.parse(report(0xFF, 0x04), board: board) == .error(0x04))
        let malformed: [[UInt8]] = [
            [], [0x05], [0x05, 0x01], [0x06, 0x01, 0xFE], [0x05, 0x01, 0x02, 0xFE],
            report(0x06, 0x07, 0x00, 0xFE), report(0x06, 0x00, 0x0C, 0xFE),  // outside the 12 × 7 matrix
            report(0x00, 0xFE), report(0x00, 0x4B, 0x80, 0xFE),  // empty or non-ASCII serial
            [0x08], [0xFF], report(0x04, 0xFE), report(0x0B, 0x01),  // truncated replies, paired, status-LED reply
        ]
        for bytes in malformed { #expect(OryxReport.parse(bytes, board: board) == nil, "\(bytes.prefix(4))") }
    }

    @Test func encodesTheFourCommandsAs32ByteReports() {
        let board = BoardDefinition.voyager
        let expected: [(KeyboardCommand, [UInt8])] = [
            (.moveToLayer(0), [0x04, 0x01, 0x00]), (.moveToLayer(31), [0x04, 0x01, 0x1F]),
            (.lighting(true), [0x05, 0x01]), (.lighting(false), [0x05, 0x00]),
            (.setLED(index: 51, red: 0xFF, green: 0x80, blue: 0x01), [0x06, 0x33, 0xFF, 0x80, 0x01]),
            (.setAllLEDs(red: 0x00, green: 0x00, blue: 0x40), [0x09, 0x00, 0x00, 0x40]),
        ]
        for (command, bytes) in expected {
            #expect(OryxReport.encode(command, board: board) == bytes + [UInt8](repeating: 0, count: 32 - bytes.count))
        }
    }

    /// Shifting by layer 32 is undefined in the firmware; LED 52 would write past its LED array; a layout read's offset
    /// is two bytes.
    @Test(arguments: [
        KeyboardCommand.moveToLayer(32), .moveToLayer(255), .moveToLayer(256), .moveToLayer(-1),
        .setLED(index: 52, red: 1, green: 1, blue: 1), .setLED(index: 255, red: 1, green: 1, blue: 1),
        .setLED(index: -1, red: 1, green: 1, blue: 1), .readLayoutRecord(offset: 65_536), .readLayoutRecord(offset: -1),
    ])
    func refusesValuesTheFirmwareDoesntBoundsCheck(_ command: KeyboardCommand) {
        #expect(OryxReport.encode(command, board: .voyager) == nil)
    }

    // MARK: Layout record (ADR 0061)

    /// A layout record reply: the 8-byte header, the part, then the firmware's zero padding.
    static func recordReply(status: UInt8, size: Int, offset: Int, part: [UInt8]) -> [UInt8] {
        let header: [UInt8] = [
            0x53, 0x01, status, UInt8(size >> 8), UInt8(size & 0xFF), UInt8(offset >> 8), UInt8(offset & 0xFF), UInt8(part.count),
        ]
        return header + part + [UInt8](repeating: 0, count: 32 - header.count - part.count)
    }

    @Test func encodesTheLayoutReadWithItsTwoByteOffset() {
        let expected: [(Int, [UInt8])] = [
            (0, [0x53, 0x01, 0x00, 0x00]), (0x1234, [0x53, 0x01, 0x12, 0x34]), (65_535, [0x53, 0x01, 0xFF, 0xFF]),
        ]
        for (offset, bytes) in expected {
            let report = OryxReport.encode(.readLayoutRecord(offset: offset), board: .voyager)
            #expect(report == bytes + [UInt8](repeating: 0, count: 28))
            #expect(report.map { OryxReport.trimmed($0, sent: true) } == bytes, "the log keeps the request without its padding")
        }
    }

    @Test func parsesALayoutRecordPartByItsHeader() {
        let board = BoardDefinition.voyager
        let part = [UInt8](0x41..<0x59)  // 24 bytes
        let full = Self.recordReply(status: 0, size: 300, offset: 24, part: part)
        #expect(OryxReport.parse(full, board: board) == .layoutRecord(LayoutRecordChunk(offset: 24, size: 300, bytes: part)))
        // The last part is short; what follows its count is padding, never record bytes.
        let last = Self.recordReply(status: 0, size: 300, offset: 288, part: Array(part.prefix(12)))
        let lastChunk = LayoutRecordChunk(offset: 288, size: 300, bytes: Array(part.prefix(12)))
        #expect(OryxReport.parse(last, board: board) == .layoutRecord(lastChunk))
        let end = Self.recordReply(status: 1, size: 300, offset: 300, part: [])
        let endChunk = LayoutRecordChunk(offset: 300, size: 300, bytes: [])
        #expect(OryxReport.parse(end, board: board) == .layoutRecord(endChunk), "status 1: at or past the end")
        var tooLong = Self.recordReply(status: 0, size: 300, offset: 0, part: part)
        tooLong[7] = 25
        var cutShort = Self.recordReply(status: 0, size: 300, offset: 0, part: part)
        cutShort.removeLast(4)
        var otherRequest = Self.recordReply(status: 0, size: 300, offset: 0, part: part)
        otherRequest[1] = 0x02
        let malformed: [[UInt8]] = [
            Self.recordReply(status: 2, size: 0, offset: 0, part: []),  // the build doesn't know the request
            Self.recordReply(status: 3, size: 300, offset: 0, part: part), tooLong, cutShort, otherRequest,
            [0x53, 0x01, 0x00, 0x01, 0x2C, 0x00, 0x00], [0x53],  // shorter than a header
        ]
        for bytes in malformed { #expect(OryxReport.parse(bytes, board: board) == nil, "\(bytes.prefix(8))") }
    }

    /// The record holds macro text, which is never logged (ADR 0042, 0045): the log keeps only the header.
    @Test func theTraceKeepsOnlyALayoutRecordPartsHeader() {
        let reply = Self.recordReply(status: 0, size: 30, offset: 0, part: [UInt8](repeating: 0x41, count: 24))
        #expect(OryxReport.trimmed(reply, sent: false) == [0x53, 0x01, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x18])
        let entry = OryxReport.traceEntry(received: reply, board: .voyager)
        #expect(entry.bytes == [0x53, 0x01, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x18] && entry.event == nil && entry.direction == .received)
        #expect(OryxReport.traceEntry(received: report(0x05, 0x02, 0xFE), board: .voyager).event == .layer(2), "other events stay")
    }

    /// The read is written once paired, like Oryx's commands, and its reply comes out as an event; the log sees the request
    /// and the reply's header only.
    @Test func readsALayoutRecordPartOverThePairedSession() async {
        let part = [UInt8](repeating: 0x41, count: 24)
        let reply = Self.recordReply(status: 0, size: 30, offset: 0, part: part)
        let hid = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x05, 0x00, 0xFE)], [reply, nil]])
        let traced = Locked<[HIDTraceEntry]>([])
        let link = RawHIDLink(clock: ImmediateClock(), trace: { entry in traced.withLock { $0.append(entry) } }) { _, _ in hid }
        let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
        var events: [LiveEvent] = []
        for await event in link.session(with: keyboard, board: .voyager, commands: commands) {
            if case .layer = event { feed.yield(.readLayoutRecord(offset: 0)) }
            events.append(event)
        }
        let chunk = LayoutRecordChunk(offset: 0, size: 30, bytes: part)
        #expect(events == [.protocolVersion(5), .layer(0), .layoutRecord(chunk), .ended(nil)])
        #expect(hid.sent.value.last == [0x53, 0x01, 0x00, 0x00] + [UInt8](repeating: 0, count: 28))
        #expect(traced.value.suffix(2).map(\.bytes) == [[0x53, 0x01, 0x00, 0x00], Array(reply.prefix(8))])
        #expect(traced.value.last?.event == nil)
    }

    /// The pre-buffered command arrives while the session drains, so it is dropped; the out-of-range one is refused.
    @Test func writesCommandsOnlyOncePaired() async {
        let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
        feed.yield(.lighting(true))
        // The keyboard is unplugged right after the first command's write.
        let hid = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x04, 0xFE), report(0x05, 0x00, 0xFE)], [nil]])
        let events = await events(hid, commands: commands) {
            feed.yield(.moveToLayer(32))
            feed.yield(.setAllLEDs(red: 1, green: 2, blue: 3))
        }
        #expect(events == [.protocolVersion(5), .layer(0), .ended(nil)])
        #expect(hid.sent.value.map { Array($0.prefix(4)) } == [[0xFE, 0, 0, 0], [0x00, 0, 0, 0], [0x01, 0, 0, 0], [0x09, 1, 2, 3]])
    }

    /// `01` is out but the layer hasn't come back: the board may not be paired yet, so nothing more is written.
    @Test func dropsCommandsWhilePairing() async throws {
        let clock = TestClock()
        let hid = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x04, 0xFE)]])
        let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
        let link = RawHIDLink(clock: clock, makeTransport: { _, _ in hid })
        let ended = Locked(false)
        let consumer = Task {
            for await event in link.session(with: keyboard, board: .voyager, commands: commands) {
                if case .ended = event { ended.value = true }
            }
        }
        defer { consumer.cancel() }
        try await waitUntil {
            await clock.advance(by: .milliseconds(1))
            return hid.sent.value.count == 3
        }
        // Queued behind the pause after `01`, so the loop meets it in the pairing phase, before the 700 ms deadline.
        feed.yield(.moveToLayer(1))
        try await Task.sleep(for: .milliseconds(20))
        try await waitUntil {
            await clock.advance(by: .milliseconds(10))
            return ended.value
        }
        #expect(hid.sent.value.map { $0[0] } == [0xFE, 0x00, 0x01])
    }

    /// Commands share the handshake's write path: never closer than 5 ms, as the firmware's 4-report queue needs.
    @Test func pacesEveryWriteAtLeastFiveMillisecondsApart() async throws {
        let clock = TestClock()
        let hid = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x05, 0x00, 0xFE)]], clock: clock)
        let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
        let link = RawHIDLink(clock: clock, makeTransport: { _, _ in hid })
        let paired = Locked(false)
        let consumer = Task {
            for await event in link.session(with: keyboard, board: .voyager, commands: commands) where event == .layer(0) {
                paired.value = true
            }
        }
        defer { consumer.cancel() }
        try await waitUntil {
            await clock.advance(by: .milliseconds(1))
            return paired.value
        }
        let sequence: [KeyboardCommand] = [.moveToLayer(1), .lighting(true), .setAllLEDs(red: 1, green: 2, blue: 3), .lighting(false)]
        sequence.forEach { feed.yield($0) }
        try await waitUntil {
            await clock.advance(by: .milliseconds(1))
            return hid.sent.value.count == 8
        }
        let times = hid.sentAt.value
        #expect(zip(times, times.dropFirst()).allSatisfy { $0.duration(to: $1) >= .milliseconds(5) }, "\(times)")
        // The firmware may drop the move's own layer event (research 03 O2); pairing again reports the layer.
        #expect(
            hid.sent.value.dropFirst(3).map { Array($0.prefix(2)) } == [[0x04, 0x01], [0x01, 0], [0x05, 0x01], [0x09, 1], [0x05, 0]])
    }

    /// The pause after each paired write holds back only the next write, never the keyboard's reports.
    @Test func reportsDontWaitBehindQueuedWrites() async throws {
        let clock = TestClock()
        // A key goes down while the first of three LED writes goes out.
        let hid = FakeHID(
            script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x05, 0x00, 0xFE)], [report(0x06, 0x01, 0x00, 0xFE)]], clock: clock)
        let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
        let link = RawHIDLink(clock: clock, makeTransport: { _, _ in hid })
        let seen = Locked<[LiveEvent]>([])
        let consumer = Task {
            for await event in link.session(with: keyboard, board: .voyager, commands: commands) { seen.value.append(event) }
        }
        defer { consumer.cancel() }
        try await waitUntil {
            await clock.advance(by: .milliseconds(1))
            return seen.value.contains(.layer(0))
        }
        for index in 0..<3 { feed.yield(.setLED(index: index, red: 1, green: 2, blue: 3)) }
        try await waitUntil { seen.value.contains(.keyDown(row: 0, column: 1)) }
        #expect(hid.sent.value.count == 4, "the clock hasn't moved, so only the first LED write is out")
    }

    /// Keymapp seizing the interface after pairing shows up at the next command's write.
    @Test func aFailedCommandWriteEndsTheSession() async {
        let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
        let hid = FakeHID(
            script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x05, 0x00, 0xFE)]], sendError: .heldByAnotherApp, sendErrorAfter: 3)
        let events = await events(hid, commands: commands) { feed.yield(.moveToLayer(1)) }
        #expect(events == [.protocolVersion(5), .layer(0), .ended(.heldByAnotherApp)])
        #expect(hid.sent.value.count == 3 && hid.closed.value)
    }

    /// The raw-HID log (ADR 0045) sees every report the session reads, drained ones too, and every one it writes, in the
    /// wire's order: the fake answers inside each write, before the session writes again. The zero padding and the
    /// firmware's garbage after the stop byte are never kept.
    @Test func theTraceSeesEveryReportTrimmedAtTheStopByte() async {
        let hid = FakeHID(
            onOpen: [report(0x05, 0x03, 0xFE)],
            script: [
                [report(0xFE, 0x05, 0xFE)], [Self.serialReply],
                [report(0x05, 0x00, 0xFE), report(0x06, 0x01, 0x00, 0xFE), report(0xFF, 0xFF), nil],
            ])
        let traced = Locked<[HIDTraceEntry]>([])
        let link = RawHIDLink(clock: ImmediateClock(), trace: { entry in traced.withLock { $0.append(entry) } }) { _, _ in hid }
        for await _ in link.session(with: keyboard, board: .voyager, commands: AsyncStream { _ in }) {}
        let expected: [(HIDTraceEntry.Direction, [UInt8])] = [
            (.received, [0x05, 0x03, 0xFE]), (.sent, [0xFE]), (.received, [0xFE, 0x05, 0xFE]), (.sent, [0x00]),
            (.received, Array(Self.serialReply.prefix(14))), (.sent, [0x01]), (.received, [0x05, 0x00, 0xFE]),
            (.received, [0x06, 0x01, 0x00, 0xFE]), (.received, [0xFF, 0xFF]),
        ]
        #expect(traced.value.map(\.direction) == expected.map(\.0))
        #expect(traced.value.map(\.bytes) == expected.map(\.1))
        #expect(
            traced.value.map(\.event) == [
                .layer(3), nil, .protocolVersion(5), nil, .firmwareSerial("KlgM7/40xJ7M"), nil, .layer(0), .keyDown(row: 0, column: 1),
                .error(0xFF),
            ])
    }

    /// A trailing 0 can be a value (layer 0, lights off), so a sent report is cut by its command, not at its last nonzero.
    @Test func theTraceKeepsEachCommandWithoutItsPadding() {
        let expected: [(KeyboardCommand, [UInt8])] = [
            (.moveToLayer(0), [0x04, 0x01, 0x00]), (.lighting(false), [0x05, 0x00]),
            (.setLED(index: 0, red: 0, green: 0, blue: 0), [0x06, 0x00, 0x00, 0x00, 0x00]),
            (.setAllLEDs(red: 0, green: 0, blue: 0), [0x09, 0x00, 0x00, 0x00]),
        ]
        for (command, bytes) in expected {
            #expect(OryxReport.encode(command, board: .voyager).map { OryxReport.trimmed($0, sent: true) } == bytes)
        }
        #expect(OryxReport.trimmed(OryxReport.command(0x01), sent: true) == [0x01])
        #expect(OryxReport.trimmed(report(0x0B, 0x01, 0x12, 0xFE), sent: false) == [0x0B, 0x01], "no stop byte: the state only")
        #expect(OryxReport.trimmed(report(0x0C, 0x01), sent: false) == [0x0C], "a stop byte that never comes: only the id")
        #expect(OryxReport.trimmed([], sent: false).isEmpty)
    }
}
