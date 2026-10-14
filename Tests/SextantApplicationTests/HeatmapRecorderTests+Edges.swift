import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

/// Heatmap recording at its edges: what windows see while a write lands, a write that fails for one hour, the day and
/// hour moving on with nobody typing, pauses, and a package that only fails to read.
extension HeatmapRecorderTests {
    /// Every press of a layout as a window sees it: the snapshot it read plus what the recorder hasn't stored for it.
    func windowTotal(_ recorder: HeatmapRecorder, _ snapshot: HeatmapRecorder.Snapshot, of id: UUID) -> Int {
        KeyHeatmap(snapshot.hours + recorder.unwritten(of: id, from: nil, after: snapshot.version)).total()
    }

    @Test func countsStayInWindowsWhileAWriteLands() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13, 13)
        #expect(await eventually { recorder.counted == 2 })
        let snapshot = await recorder.snapshot(of: id, from: nil)
        await heat.holdWrites()
        let flush = Task { await recorder.flush() }
        #expect(await eventually { await heat.waiting })
        #expect(windowTotal(recorder, snapshot, of: id) == 2, "the batch being written still counts")
        type(14)
        #expect(await eventually { recorder.counted == 3 })
        #expect(windowTotal(recorder, snapshot, of: id) == 3)
        await heat.release()
        await flush.value
        #expect(windowTotal(recorder, snapshot, of: id) == 3, "and once, after it lands")
    }

    /// Each hour is written whole or not at all, so retrying a write that failed for one hour never adds another twice.
    @Test func aWriteThatFailsForOneHourKeepsOnlyThatHour() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13)
        #expect(await eventually { recorder.counted == 1 })
        now.advance(by: 3600)
        type(14)
        #expect(await eventually { recorder.counted == 2 })
        await heat.failWrites(of: HeatmapHour.start(of: now()))
        await recorder.flush()
        #expect(await heat.stored(id) == [layout.layers[0].id: [13: 1]] && recorder.lastError != nil)
        await heat.failWrites(of: nil)
        await recorder.flush()
        #expect(await heat.stored(id) == [layout.layers[0].id: [13: 1, 14: 1]])
        #expect(recorder.lastError == nil)
    }

    /// A failed write stays reported until a write succeeds, whatever reads and prunes do meanwhile.
    @Test func aFailedWriteStaysReportedUntilAWriteSucceeds() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13)
        #expect(await eventually { recorder.counted == 1 })
        await heat.failWrites(true)
        await recorder.flush()
        _ = await recorder.snapshot(of: id, from: nil)
        now.advance(by: 86_400)
        await recorder.flush()
        #expect(await heat.prunes.count == 2)
        #expect(recorder.lastError != nil, "a read and a prune succeeded, the write didn't")
        await heat.failWrites(false)
        await recorder.flush()
        #expect(recorder.lastError == nil)
    }

    @Test func aLayerMoveReachesWindowsBeforeTheWrite() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13)
        #expect(await eventually { recorder.counted == 1 })
        let changes = recorder.changes
        link.send(.layer(1))
        #expect(await eventually { recorder.changes > changes })
        #expect(KeyHeatmap(recorder.unwritten(of: id, from: nil, after: 0)).layerEntries == [layout.layers[1].id: 1])
    }

    @Test func todayIsReadWhenRecordingStartsAndIsZeroAfterMidnight() async throws {
        let id = try await knownKeyboard()
        await heat.seed(id, HeatmapHour(start: now().addingTimeInterval(-3600), presses: ["x": [1: 40]]))
        let recorder = recorder(on: true)
        #expect(recorder.pressesToday(at: now()) == nil)
        #expect(await goLive())
        #expect(await eventually { recorder.pressesToday(at: now()) == 40 }, "before any press")
        type(13)
        #expect(await eventually { recorder.pressesToday(at: now()) == 41 })
        now.advance(by: 13 * 3600)  // 01:00 the next day
        #expect(recorder.pressesToday(at: now()) == 0)
        type(14)
        #expect(await eventually { recorder.pressesToday(at: now()) == 1 })
    }

    @Test func theHourMovesOnWithNobodyTyping() async throws {
        let recorder = recorder(on: true)
        let hour = recorder.hour
        #expect(hour == HeatmapHour.start(of: now()))
        now.advance(by: 3600)
        await nextMinute()
        #expect(await eventually { recorder.hour == hour.addingTimeInterval(3600) })
    }

    /// A move made while secure input hid the keyboard isn't counted when Live View pairs again on that layer.
    @Test func aLayerReachedDuringSecureInputIsNotAMove() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        #expect(await goLive())
        type(13)
        #expect(await eventually { recorder.counted == 1 })
        secureInput.isOn = true
        link.send(.layer(1))
        await clock.advance(by: .seconds(2))
        #expect(await eventually { recorder.status == .waiting(.secureInput) })
        secureInput.isOn = false
        await clock.advance(by: .seconds(2))
        #expect(await eventually { recorder.status == .recording(id) })
        live.stopLive()
        #expect(await eventually { !live.canSend })
        live.startLive()
        #expect(await eventually { link.sessionCount == 2 })
        link.send(.layer(1))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.canSend
            })
        type(16)
        #expect(await eventually { recorder.counted == 2 })
        await recorder.flush()
        #expect(await heat.entries(id).isEmpty)
        #expect(await heat.stored(id)[layout.layers[1].id] == [16: 1])
    }

    /// Only Sextant's Move to Trash drops counts: a package that fails to read for now leaves the library but keeps them.
    @Test func aLayoutThatOnlyFailsToReadKeepsItsCounts() async throws {
        let id = try await knownKeyboard()
        let recorder = recorder(on: true)
        await heat.seed(id, HeatmapHour(start: now(), presses: ["x": [1: 5]]))
        await store.hide(id)
        await library.refresh()
        #expect(!library.entries.contains { $0.id == id })
        for _ in 0..<50 { await Task.yield() }
        await recorder.flush()
        #expect(await heat.cleared.isEmpty && heat.addCount == 0)
        #expect(await heat.stored(id) == ["x": [1: 5]])
    }
}
