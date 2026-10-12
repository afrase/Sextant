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

    /// Layer 32 would shift past the firmware's 32-bit layer state; LED 52 would write past its LED array.
    @Test(arguments: [
        KeyboardCommand.moveToLayer(32), .moveToLayer(255), .moveToLayer(256), .moveToLayer(-1),
        .setLED(index: 52, red: 1, green: 1, blue: 1), .setLED(index: 255, red: 1, green: 1, blue: 1),
        .setLED(index: -1, red: 1, green: 1, blue: 1),
    ])
    func refusesValuesTheFirmwareDoesntBoundsCheck(_ command: KeyboardCommand) {
        #expect(OryxReport.encode(command, board: .voyager) == nil)
    }

    /// The pre-buffered command arrives while the session drains, so it is dropped; the out-of-range one is refused.
    @Test func writesCommandsOnlyOncePaired() async {
        let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
        feed.yield(.lighting(true))
        // The keyboard is unplugged right after the first command's write.
        let hid = FakeHID(script: [[report(0xFE, 0x05, 0xFE)], [], [report(0x04, 0xFE), report(0x05, 0x00, 0xFE)], [nil]])
        let events = await events(hid, commands: commands) {
            feed.yield(.moveToLayer(32))
            feed.yield(.moveToLayer(2))
        }
        #expect(events == [.protocolVersion(5), .layer(0), .ended(nil)])
        #expect(hid.sent.value.map { Array($0.prefix(3)) } == [[0xFE, 0, 0], [0x00, 0, 0], [0x01, 0, 0], [0x04, 0x01, 0x02]])
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
        for command in [KeyboardCommand.lighting(true), .setAllLEDs(red: 1, green: 2, blue: 3), .lighting(false)] { feed.yield(command) }
        try await waitUntil {
            await clock.advance(by: .milliseconds(1))
            return hid.sent.value.count == 6
        }
        let times = hid.sentAt.value
        #expect(zip(times, times.dropFirst()).allSatisfy { $0.duration(to: $1) >= .milliseconds(5) }, "\(times)")
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
}
