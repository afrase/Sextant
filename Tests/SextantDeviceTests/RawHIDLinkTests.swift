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
    /// Opens that fail with `.notFound` first, as when the interface isn't published yet.
    let notFoundFirst: Int
    let opens = Locked(0)
    let sent = Locked<[[UInt8]]>([])
    let closed = Locked(false)
    private let receive = Locked<(@Sendable ([UInt8]?) -> Void)?>(nil)

    init(
        onOpen: [[UInt8]?] = [], script: [[[UInt8]?]] = [], openError: DeviceError? = nil, sendError: DeviceError? = nil,
        notFoundFirst: Int = 0
    ) {
        self.notFoundFirst = notFoundFirst
        self.onOpen = onOpen
        self.script = script
        self.openError = openError
        self.sendError = sendError
    }

    func open(receive: @escaping @Sendable ([UInt8]?) -> Void) throws(DeviceError) {
        opens.value += 1
        if opens.value <= notFoundFirst { throw .notFound }
        if let openError { throw openError }
        self.receive.value = receive
        onOpen.forEach(receive)
    }

    func send(_ report: [UInt8]) throws(DeviceError) {
        if let sendError { throw sendError }
        let n = sent.value.count
        sent.value.append(report)
        if n < script.count, let receive = receive.value { script[n].forEach(receive) }
    }

    func close() { closed.value = true }
}

/// An input report: the bytes, then garbage, as the firmware leaves its buffer.
func report(_ bytes: UInt8...) -> [UInt8] { bytes + [UInt8](repeating: 0xAB, count: 32 - bytes.count) }

struct RawHIDLinkTests {
    let keyboard = KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")
    static let serialReply = report(0x00, 0x4B, 0x6C, 0x67, 0x4D, 0x37, 0x2F, 0x34, 0x30, 0x78, 0x4A, 0x37, 0x4D, 0xFE)

    func events(_ hid: FakeHID) async -> [LiveEvent] {
        var events: [LiveEvent] = []
        for await event in RawHIDLink(clock: ImmediateClock(), makeTransport: { _, _ in hid }).session(with: keyboard, board: .voyager) {
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
                .protocolVersion(5), .firmwareSerial("KlgM7/40xJ7M"), .layer(0), .keyDown(row: 0, column: 1), .keyUp(row: 0, column: 1),
                .ended(nil),
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
            for await event in link.session(with: keyboard, board: .voyager) where event == .layer(0) { layers.value += 1 }
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
        let malformed: [[UInt8]] = [
            [], [0x05], [0x05, 0x01], [0x06, 0x01, 0xFE], [0x05, 0x01, 0x02, 0xFE],
            report(0x06, 0x07, 0x00, 0xFE), report(0x06, 0x00, 0x0C, 0xFE),  // outside the 12 × 7 matrix
            report(0x00, 0xFE), report(0x00, 0x4B, 0x80, 0xFE),  // empty or non-ASCII serial
            report(0x08, 0x01), report(0x04, 0xFE), report(0xFF, 0xFF, 0xFE),  // RGB reply, paired, error
        ]
        for bytes in malformed { #expect(OryxReport.parse(bytes, board: board) == nil, "\(bytes.prefix(4))") }
    }
}
