import Clocks
import Foundation
import SextantApplication
import SextantDomain
import Testing

/// Reading the layout a Sextant build stores (ADR 0061) over the paired Live View session, on FakeDeviceWatcher and
/// FakeKeyboardLink: nothing here writes to a keyboard.
@MainActor
struct LiveSessionLayoutReadTests {
    let watcher = FakeDeviceWatcher()
    let link = FakeKeyboardLink()
    /// The session's debounce and write estimate (12 ms a write), and the reads' half-second deadlines.
    let clock = TestClock()
    let live: LiveSession

    /// 100 bytes: four full parts, then one of 4.
    static let record: [UInt8] = (0..<100).map { UInt8($0) }

    init() {
        live = LiveSession(watcher: watcher, link: link, clock: clock) { false }
        live.start()
    }

    /// A keyboard plugged in, with Live View on and its session paired.
    func paired() async -> Bool {
        live.startLive()
        watcher.attach(.keyboard(.voyager(serial: "sx-01234567-89ABCDEF")))
        guard await eventually({ link.sessionCount == 1 }) else { return false }
        link.send(.layer(0))
        return await eventually {
            await clock.advance(by: .milliseconds(17))
            return live.canSend
        }
    }

    /// The offsets the first session was asked for, in order.
    var asked: [Int] {
        (link.commands.first ?? []).compactMap { if case let .readLayoutRecord(offset) = $0 { offset } else { nil } }
    }

    /// A read running in the background; `done` turns on once it has returned or thrown.
    func reading(fractions: Recorded<Double> = Recorded(), done: Flag = Flag()) -> Task<[UInt8], any Error> {
        Task {
            defer { done.isOn = true }
            return try await live.readLayoutRecord { fractions.append($0) }
        }
    }

    /// Advances the clock 50 ms at a time until `condition` holds.
    func advance(until condition: () -> Bool) async -> Bool {
        await eventually {
            await clock.advance(by: .milliseconds(50))
            return condition()
        }
    }

    @Test func readsTheWholeRecordOnePartAtATime() async throws {
        let seen = Recorded<LiveActivity>()
        let stream = live.activity()
        let watching = Task { for await activity in stream { seen.append(activity) } }
        defer { watching.cancel() }
        try #require(await paired())
        link.storeLayoutRecord(Self.record)
        let fractions = Recorded<Double>()
        let bytes = try await live.readLayoutRecord { fractions.append($0) }
        #expect(bytes == Self.record)
        #expect(asked == [0, 24, 48, 72, 96])
        #expect(fractions.values == [0.24, 0.48, 0.72, 0.96, 1])
        #expect(await eventually { seen.values == [.layer(0)] })
        try await Task.sleep(for: .milliseconds(20))
        #expect(seen.values == [.layer(0)], "the record's parts are never activity")
        #expect(live.activeLayer == 0 && live.pressedKeys.isEmpty)
    }

    @Test func needsAPairedLiveViewSession() async throws {
        await #expect(throws: LayoutReadError.notLive, "no keyboard") { try await live.readLayoutRecord() }
        watcher.attach(.keyboard(.voyager(serial: "sx-01234567-89ABCDEF")))
        #expect(await eventually { live.connection != .noKeyboard })
        await #expect(throws: LayoutReadError.notLive, "Live View off") { try await live.readLayoutRecord() }
        live.startLive()
        #expect(await eventually { link.sessionCount == 1 })
        await #expect(throws: LayoutReadError.notLive, "still pairing") { try await live.readLayoutRecord() }
        #expect(link.commands == [[]], "nothing was written")
    }

    /// Stock Oryx firmware, and a Sextant build without a record, answer `FF FF`: an unknown command.
    @Test func firmwareThatStoresNoRecordAnswersUnknownCommand() async throws {
        try #require(await paired())
        await #expect(throws: LayoutReadError.noRecord) { try await live.readLayoutRecord() }
        #expect(asked == [0])
        await #expect(throws: LayoutReadError.noRecord, "a failed read lets the next one run") {
            try await live.readLayoutRecord()
        }
    }

    /// A part that doesn't come is asked for once more, half a second after its request was likely written.
    @Test func asksForALostPartOnceMore() async throws {
        try #require(await paired())
        link.storeLayoutRecord(Self.record)
        link.dropLayoutReads(1)
        let read = reading()
        #expect(await eventually { asked == [0] })
        await clock.advance(by: .milliseconds(400))
        #expect(asked == [0], "not before half a second")
        #expect(await advance { asked.count > 1 })
        let bytes = try await read.value
        #expect(bytes == Self.record)
        #expect(asked == [0, 0, 24, 48, 72, 96])
    }

    @Test func givesUpWhenAPartIsLostTwice() async throws {
        try #require(await paired())
        link.storeLayoutRecord(Self.record)
        link.dropLayoutReads(2)
        let done = Flag()
        let read = reading(done: done)
        #expect(await eventually { asked == [0] })
        #expect(await advance { asked == [0, 0] })
        #expect(await advance { done.isOn })
        await #expect(throws: LayoutReadError.timedOut) { try await read.value }
        #expect(asked == [0, 0], "never a third time")
    }

    @Test(arguments: ["the session ends", "Live View turns off", "the keyboard is unplugged"])
    func endsWhenThePairedSessionDoes(_ how: String) async throws {
        try #require(await paired())
        link.dropLayoutReads(1)
        let read = reading()
        #expect(await eventually { asked == [0] })
        switch how {
        case "the session ends": link.send(.ended(nil))
        case "Live View turns off": live.stopLive()
        default: watcher.detach(1)
        }
        await #expect(throws: LayoutReadError.disconnected) { try await read.value }
    }

    @Test func refusesASecondReadWhileOneRuns() async throws {
        try #require(await paired())
        link.storeLayoutRecord(Self.record)
        link.dropLayoutReads(1)
        let first = reading()
        #expect(await eventually { asked == [0] })
        await #expect(throws: LayoutReadError.busy) { try await live.readLayoutRecord() }
        #expect(await advance { asked.count > 1 })
        let bytes = try await first.value
        #expect(bytes == Self.record)
        let again = try await live.readLayoutRecord()
        #expect(again == Self.record, "free again once it's done")
    }

    /// The record can't change mid-read: a reflash ends the session first.
    @Test func aSizeThatChangesIsMalformed() async throws {
        try #require(await paired())
        link.dropLayoutReads(.max)
        let read = reading()
        #expect(await eventually { asked == [0] })
        link.send(.layoutRecord(LayoutRecordChunk(offset: 0, size: 48, bytes: Array(repeating: 1, count: 24))))
        #expect(await eventually { asked == [0, 24] })
        link.send(.layoutRecord(LayoutRecordChunk(offset: 24, size: 50, bytes: Array(repeating: 2, count: 24))))
        await #expect(throws: LayoutReadError.malformed) { try await read.value }
    }

    /// An empty record, a part that runs past the record's size, and a part with no bytes before the end.
    @Test(arguments: [
        LayoutRecordChunk(offset: 0, size: 0, bytes: []), LayoutRecordChunk(offset: 0, size: 10, bytes: Array(repeating: 1, count: 24)),
        LayoutRecordChunk(offset: 0, size: 30, bytes: []),
    ])
    func partsThatDontAddUpAreMalformed(_ first: LayoutRecordChunk) async throws {
        try #require(await paired())
        link.dropLayoutReads(.max)
        let read = reading()
        #expect(await eventually { asked == [0] })
        link.send(.layoutRecord(first))
        await #expect(throws: LayoutReadError.malformed) { try await read.value }
    }

    /// A stale reply, or another host's, answers another offset; another command's refusal answers another command.
    @Test func ignoresRepliesToOtherRequests() async throws {
        try #require(await paired())
        link.dropLayoutReads(.max)
        let fractions = Recorded<Double>()
        let read = reading(fractions: fractions)
        #expect(await eventually { asked == [0] })
        let record = (0..<30).map { UInt8($0) }
        let head = LayoutRecordChunk(offset: 0, size: 30, bytes: Array(record.prefix(24)))
        let tail = LayoutRecordChunk(offset: 24, size: 30, bytes: Array(record.dropFirst(24)))
        link.send(.layoutRecord(tail), .error(0x04), .layoutRecord(head))
        #expect(await eventually { asked == [0, 24] })
        link.send(.layoutRecord(head), .layoutRecord(tail))
        let bytes = try await read.value
        #expect(bytes == record)
        #expect(fractions.values == [0.8, 1])
    }
}
