import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// Settings › Keyboard and Advanced (spec §8.9), on a defaults suite of their own.
@MainActor
struct SettingsTests {
    let suiteName = "SettingsTests-\(UUID().uuidString)"

    @Test func pressesLeaveTheBoardWhileTheSettingIsOff() async throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: SettingsKey.showsKeyPresses)
        let key13 = BoardDefinition.voyager.keys[13]
        let keyboard = OneKeyboard(script: [.protocolVersion(5), .layer(0), .keyDown(row: key13.matrixRow, column: key13.matrixColumn)])
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        live.start()
        live.startLive()
        defer { live.stop() }
        let window = LayoutWindowModel(library: Library(store: MemoryLibrary()), live: live)
        let following = Task { await window.followKeyboard(settings: defaults) }
        defer { following.cancel() }

        #expect(await eventually { live.pressedKeys == [13] })
        try await Task.sleep(for: .milliseconds(50))
        #expect(!window.pressedKeys.state(13).isDown, "the keyboard reports the press; the board doesn't show it")

        defaults.set(true, forKey: SettingsKey.showsKeyPresses)
        #expect(await eventually { window.pressedKeys.state(13).isDown }, "turning it on shows held keys at once")
        defaults.set(false, forKey: SettingsKey.showsKeyPresses)
        #expect(await eventually { !window.pressedKeys.state(13).isDown }, "and off hides them at once")
    }

    @Test func resetAllWarningsShowsTheLiveDataNoteAgain() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(!SettingsKey.hasDismissedNotes(in: defaults), "nothing to reset: the button is off")
        defaults.set(true, forKey: SettingsKey.seenLiveDataNote)
        #expect(SettingsKey.hasDismissedNotes(in: defaults))
        SettingsKey.resetOneTimeNotes(in: defaults)
        #expect(defaults.object(forKey: SettingsKey.seenLiveDataNote) == nil && !SettingsKey.hasDismissedNotes(in: defaults))
    }

    /// The Device popover's log line: a 24-hour time, then positions only, "down k40 · R8 C2".
    @Test func aTracedKeyReportReadsAsItsPosition() throws {
        let board = BoardDefinition.voyager
        let key = board.keys[40]
        let (row, column) = (UInt8(key.matrixRow), UInt8(key.matrixColumn))
        let evening = try #require(
            DateComponents(calendar: .current, year: 2026, month: 10, day: 12, hour: 21, minute: 41, second: 7, nanosecond: 24_000_000).date
        )
        let pressed = HIDTraceEntry(
            date: evening, direction: .received, bytes: [0x06, column, row, 0xFE],
            event: .keyDown(row: key.matrixRow, column: key.matrixColumn))
        let line = pressed.line(board: board)
        #expect(line.head == "21:41:07.024  ←  ")
        #expect(line.report == String(format: "06 %02X %02X FE  down k40 · R%d C%d", column, row, row, column))
        #expect(HIDTraceEntry(direction: .sent, bytes: [0x01]).line(board: board).head.hasSuffix("  →  "))
    }
}

/// One keyboard, present from the start, whose link session plays `script` and stays open.
private struct OneKeyboard: DeviceWatcher, KeyboardLink {
    var script: [LiveEvent]

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in script.forEach { continuation.yield($0) } }
    }
}

/// Polls `condition`, letting other tasks run, for up to about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
