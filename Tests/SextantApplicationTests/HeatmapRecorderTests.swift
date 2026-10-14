import Clocks
import Foundation
import SextantDomain
import Synchronization
import Testing

@testable import SextantApplication

/// Heatmap recording (ADR 0053) on FakeKeyboardLink, FakeDeviceWatcher and an in-memory store, with a test clock: nothing
/// here reads a real keyboard or sleeps for real.
@MainActor
struct HeatmapRecorderTests {
    let store = InMemoryLibrary()
    let heat = FakeHeatmapStore()
    let watcher = FakeDeviceWatcher()
    let link = FakeKeyboardLink()
    let clock = TestClock()
    let now = TestNow(Date(timeIntervalSinceReferenceDate: 813_758_400))  // 2026-10-15 12:00 UTC
    let secureInput = SecureInputFlag()
    let live: LiveSession
    let library: Library
    let onKeyboard: OnKeyboard
    let layout: KeyboardLayout
    var calendar = Calendar(identifier: .gregorian)

    init() throws {
        let secureInput = secureInput
        live = LiveSession(watcher: watcher, link: link, clock: clock) { secureInput.isOn }
        library = Library(store: store)
        onKeyboard = OnKeyboard(library: library, store: store, live: live)
        layout = try KeyboardLayout(oryxJSON: Fixtures.userLayoutData)
        calendar.timeZone = .gmt
    }

    func recorder(on: Bool, retentionDays: Int = 30, saved: @escaping @MainActor (Bool, Int) -> Void = { _, _ in }) -> HeatmapRecorder {
        let now = now
        let recorder = HeatmapRecorder(
            live: live, onKeyboard: onKeyboard, library: library, store: heat, clock: clock, now: { now() },
            calendar: calendar, isOn: on, retentionDays: retentionDays, persist: saved)
        recorder.start()
        return recorder
    }

    /// The user's layout (Main, Sym+Num, Brd+Sys) in the library, on a plugged-in keyboard that runs it; returns its id.
    func knownKeyboard(serial: String = "KlgM7/40xJ7M") async throws -> UUID {
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        live.start()
        onKeyboard.start()
        watcher.attach(.keyboard(.voyager(serial: serial)))
        #expect(await eventually { live.firmwareSerial == serial })
        return entry.id
    }

    /// Turns Live View on and pairs its session on layer 0.
    func goLive() async -> Bool {
        live.startLive()
        guard await eventually({ link.sessionCount == 1 }) else { return false }
        link.send(.layer(0))
        return await eventually {
            await clock.advance(by: .milliseconds(17))
            return live.canSend
        }
    }

    /// Presses and releases each key (by index) on the board.
    func type(_ indices: Int...) {
        for index in indices {
            let key = BoardDefinition.voyager.keys[index]
            link.send(.keyDown(row: key.matrixRow, column: key.matrixColumn), .keyUp(row: key.matrixRow, column: key.matrixColumn))
        }
    }

    /// Lets the minute's write happen.
    func nextMinute() async { await clock.advance(by: .seconds(60)) }

    // MARK: Opt-in

    @Test func offByDefaultCountsNothing() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: false)
        #expect(await goLive())
        type(13, 14)
        #expect(await eventually { live.pressedKeys.isEmpty })
        await nextMinute()
        await recorder.flush()
        #expect(recorder.status == .off && recorder.counted == 0)
        #expect(await heat.stored(id).isEmpty && heat.addCount == 0)
    }

    @Test func turningItOnIsSavedAndCountsFromThen() async throws {
        let id = try await knownKeyboard()
        var saved: [String] = []
        let recorder = recorder(on: false) { saved.append("\($0) \($1)") }
        #expect(await goLive())
        let feed = live.activity()
        type(13)
        for await event in feed where event == .keyUp(index: 13) { break }
        // The recorder's own feed hands it the press too, while it is still off.
        for _ in 0..<50 { await Task.yield() }
        recorder.isOn = true
        recorder.retentionDays = 90
        #expect(saved == ["true 30", "true 90"])
        #expect(recorder.status == .recording(id))
        type(14, 14)
        #expect(await eventually { recorder.counted == 2 })
        await recorder.flush()
        #expect(await heat.stored(id)[layout.layers[0].id] == [14: 2], "only presses made while on")
    }

    // MARK: Counting

    @Test func countsKeyDownsByLayerIDAndLayerEntries() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13, 13, 24)
        link.send(.layer(1))
        type(16)
        link.send(.layer(0), .layer(2))
        type(38)
        #expect(await eventually { recorder.counted == 5 })
        await recorder.flush()
        let stored = await heat.stored(id)
        #expect(stored[layout.layers[0].id] == [13: 2, 24: 1])
        #expect(stored[layout.layers[1].id] == [16: 1])
        #expect(stored[layout.layers[2].id] == [38: 1])
        let entries = await heat.entries(id)
        #expect(entries == [layout.layers[1].id: 1, layout.layers[0].id: 1, layout.layers[2].id: 1], "pairing's report isn't a move")
        #expect(await heat.hourStarts(id) == [now()], "one hour, starting on the hour")
    }

    @Test func nothingDuringSecureInput() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        secureInput.isOn = true
        type(13, 14, 15)
        link.send(.layer(1))
        await clock.advance(by: .seconds(2))
        #expect(recorder.status == .waiting(.secureInput))
        secureInput.isOn = false
        await clock.advance(by: .seconds(2))
        type(16)
        #expect(await eventually { recorder.counted == 1 })
        await recorder.flush()
        // On Sym+Num, which the keyboard moved to while secure input hid it: that move isn't counted either.
        #expect(await heat.stored(id) == [layout.layers[1].id: [16: 1]])
        #expect(await heat.entries(id).isEmpty)
    }

    @Test func nothingForFirmwareOfAnotherLayout() async throws {
        let id = try await knownKeyboard(serial: "Q9x2/aa11")
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13, 14)
        #expect(await eventually { live.pressedKeys.isEmpty })
        await recorder.flush()
        #expect(recorder.status == .waiting(.otherLayout) && recorder.counted == 0)
        #expect(await heat.stored(id).isEmpty && heat.addCount == 0)
    }

    @Test func waitsForLiveViewAndSaysWhy() async throws {
        let recorder = recorder(on: true)
        #expect(recorder.status == .waiting(.noKeyboard))
        _ = try await knownKeyboard()
        #expect(recorder.status == .waiting(.liveViewOff))
    }

    // MARK: Writing

    @Test func writesEveryMinuteAndAtQuit() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13)
        #expect(await eventually { recorder.counted == 1 })
        await clock.advance(by: .seconds(59))
        #expect(heat.addCount == 0)
        #expect(
            await eventually {
                await clock.advance(by: .seconds(1))
                return heat.addCount == 1
            })
        #expect(await heat.stored(id) == [layout.layers[0].id: [13: 1]])
        type(14)
        #expect(await eventually { recorder.counted == 2 })
        await recorder.flush()  // quitting
        #expect(await heat.stored(id) == [layout.layers[0].id: [13: 1, 14: 1]])
        await recorder.flush()
        #expect(heat.addCount == 2, "nothing left to write")
    }

    @Test func aFailedWriteIsRetried() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13)
        #expect(await eventually { recorder.counted == 1 })
        await heat.failWrites(true)
        await recorder.flush()
        #expect(recorder.lastError != nil)
        type(13)
        #expect(await eventually { recorder.counted == 2 })
        await heat.failWrites(false)
        await recorder.flush()
        #expect(recorder.lastError == nil)
        #expect(await heat.stored(id) == [layout.layers[0].id: [13: 2]])
    }

    @Test func prunesByRetentionAtStartEachDayAndOnChange() async throws {
        let recorder = recorder(on: true, retentionDays: 30)
        #expect(await eventually { await heat.prunes.count == 1 })
        #expect(await heat.prunes.last == now().addingTimeInterval(-30 * 86_400))
        recorder.retentionDays = 365
        #expect(await eventually { await heat.prunes.count == 2 })
        #expect(await heat.prunes.last == now().addingTimeInterval(-365 * 86_400))
        await recorder.flush()
        #expect(await heat.prunes.count == 2, "once a day")
        now.advance(by: 86_400)
        await recorder.flush()
        #expect(await heat.prunes.count == 3)
    }

    // MARK: Reading

    /// A window's read plus what was counted since never counts a press twice, across a write.
    @Test func snapshotsAddUnwrittenCountsOnce() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13, 13)
        #expect(await eventually { recorder.counted == 2 })
        let before = await recorder.snapshot(of: id, from: nil)
        func total(_ snapshot: HeatmapRecorder.Snapshot) -> Int {
            KeyHeatmap(snapshot.hours + recorder.unwritten(of: id, from: nil, after: snapshot.version)).total()
        }
        #expect(total(before) == 2 && before.hours.isEmpty)
        await recorder.flush()
        #expect(total(before) == 2, "the write is added until the window reads again")
        let after = await recorder.snapshot(of: id, from: nil)
        #expect(total(after) == 2 && after.version > before.version)
        type(14)
        #expect(await eventually { total(after) == 3 })
        #expect(recorder.unwritten(of: id, from: now().addingTimeInterval(3600), after: after.version).isEmpty)
    }

    @Test func todayAndWordsPerMinute() async throws {
        let id = try await knownKeyboard()
        await heat.seed(id, HeatmapHour(start: now().addingTimeInterval(-3600), presses: ["x": [1: 40]]))
        await heat.seed(id, HeatmapHour(start: now().addingTimeInterval(-13 * 3600), presses: ["x": [1: 7]]))  // yesterday
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13, 14, 15, 16, 17, 18, 19, 20, 21, 22)
        #expect(await eventually { recorder.counted == 10 && recorder.pressesToday(at: now()) == 50 })
        #expect(recorder.wordsPerMinute(at: now()) == 2)
        #expect(recorder.wordsPerMinute(at: now().addingTimeInterval(61)) == 0, "only the last minute, kept in memory")
    }

    // MARK: Clearing

    @Test func clearDropsStoredAndUnwrittenCounts() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13)
        #expect(await eventually { recorder.counted == 1 })
        await recorder.flush()
        type(14)
        #expect(await eventually { recorder.counted == 2 && recorder.pressesToday(at: now()) == 2 })
        let version = recorder.version
        await recorder.clear(id)
        #expect(await heat.cleared == [id])
        #expect(
            recorder.unwritten(of: id, from: nil, after: 0).isEmpty && recorder.pressesToday(at: now()) == 0 && recorder.version > version)
        await recorder.flush()
        #expect(await heat.stored(id).isEmpty)
        await recorder.clear(nil)
        #expect(await heat.cleared == [id, nil])
    }

    @Test func trashingALayoutDeletesItsCounts() async throws {
        let id = try await knownKeyboard()
        let other = try await library.importOryxJSON(Fixtures.userLayoutData)
        let recorder = recorder(on: true)
        #expect(await eventually { library.entries.count == 2 })
        await library.trash(other.id)
        #expect(await eventually { await heat.cleared == [other.id] })
        _ = recorder
        #expect(!(await heat.cleared).contains(id))
    }
}

/// Secure input, as the probe reports it.
final class SecureInputFlag: Sendable {
    private let value = Mutex(false)

    var isOn: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

/// A clock for dates the test moves by hand.
final class TestNow: Sendable {
    private let date: Mutex<Date>

    init(_ date: Date) { self.date = Mutex(date) }

    func callAsFunction() -> Date { date.withLock { $0 } }

    func advance(by seconds: TimeInterval) { date.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// The Heatmap store in memory: hours by layout, and every prune and clear.
actor FakeHeatmapStore: HeatmapStore {
    private var hours: [UUID: [Date: HeatmapHour]] = [:]
    private(set) var prunes: [Date] = []
    private(set) var cleared: [UUID?] = []
    private var failing = false
    /// Hours whose add fails, while others succeed.
    private var failingHours: Set<Date> = []
    private let adds = Mutex(0)
    /// An add waits here, once set, until ``release()``.
    private var gate: CheckedContinuation<Void, Never>?
    private var gated = false
    private(set) var waiting = false

    nonisolated var addCount: Int { adds.withLock { $0 } }

    func failWrites(_ fail: Bool) { failing = fail }

    func failWrites(of hour: Date?) { failingHours = hour.map { [$0] } ?? [] }

    func holdWrites() { gated = true }

    func release() {
        gated = false
        gate?.resume()
        gate = nil
    }

    func seed(_ id: UUID, _ hour: HeatmapHour) { hours[id, default: [:]][hour.start] = hour }

    /// Every stored press of a layout, by layer id and key.
    func stored(_ id: UUID) -> [String: [Int: Int]] { KeyHeatmap((hours[id] ?? [:]).values).presses }

    func entries(_ id: UUID) -> [String: Int] { KeyHeatmap((hours[id] ?? [:]).values).layerEntries }

    func hourStarts(_ id: UUID) -> [Date] { (hours[id] ?? [:]).keys.sorted() }

    func hours(of layoutID: UUID, from start: Date?) throws(HeatmapStoreError) -> [HeatmapHour] {
        (hours[layoutID] ?? [:]).values.filter { hour in start.map { hour.start >= $0 } ?? true }.sorted { $0.start < $1.start }
    }

    func add(_ hour: HeatmapHour, to layoutID: UUID) async throws(HeatmapStoreError) {
        if gated {
            waiting = true
            await withCheckedContinuation { gate = $0 }
            waiting = false
        }
        guard !failing, !failingHours.contains(hour.start) else { throw .io("disk full") }
        adds.withLock { $0 += 1 }
        hours[layoutID, default: [:]][hour.start, default: HeatmapHour(start: hour.start)].add(hour)
    }

    func prune(before date: Date) throws(HeatmapStoreError) {
        prunes.append(date)
        for id in hours.keys { hours[id] = hours[id]?.filter { $0.key >= date } }
    }

    func clear(_ layoutID: UUID?) throws(HeatmapStoreError) {
        cleared.append(layoutID)
        if let layoutID { hours[layoutID] = nil } else { hours = [:] }
    }
}
