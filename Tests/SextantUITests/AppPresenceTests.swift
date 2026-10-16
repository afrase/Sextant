import AppKit
import SextantApplication
import Testing

@testable import SextantUI

/// When Sextant leaves the Dock and comes back (spec §2.1, ADR 0049). The policy goes to a recorder, never to the app.
@MainActor
struct AppPresenceTests {
    private let defaults: UserDefaults
    private let suite = "sextant-app-presence-\(UUID().uuidString)"
    /// Each test's own, so one test's window closing never reaches another's presence.
    private let windowNotifications = NotificationCenter()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    private func makePresence(
        windows: @escaping @MainActor () -> Int = { 0 }, apply: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void
    ) -> AppPresence {
        AppPresence(defaults: defaults, windowNotifications: windowNotifications, openWindows: windows, apply: apply)
    }

    private func set(shows: Bool, keeps: Bool) {
        defaults.set(shows, forKey: SettingsKey.showsInMenuBar)
        defaults.set(keeps, forKey: SettingsKey.keepsInMenuBar)
    }

    @Test func theLastWindowClosingLeavesTheDockOnlyWithBothSettingsOn() {
        var applied: [NSApplication.ActivationPolicy] = []
        let presence = makePresence { applied.append($0) }
        // The defaults: shown in the menu bar and kept there (the user's request, 2026-10-16).
        presence.windowOpened()
        presence.windowClosed()
        #expect(applied == [.accessory])
        presence.windowOpened()
        #expect(applied == [.accessory, .regular])
        applied = []

        set(shows: true, keeps: false)
        presence.windowClosed()
        #expect(applied.isEmpty && presence.policy == .regular, "not kept in the menu bar")

        set(shows: true, keeps: true)
        presence.windowOpened()
        presence.windowOpened()
        presence.windowClosed()
        #expect(applied.isEmpty, "a window is still open")
        presence.windowClosed()
        #expect(applied == [.accessory])

        // A window that opens on its own (restoration, File ▸ New Window) brings the Dock icon back.
        presence.windowOpened()
        #expect(applied == [.accessory, .regular])
        presence.windowClosed()

        set(shows: false, keeps: true)
        presence.windowOpened()
        presence.windowClosed()
        #expect(presence.policy == .regular, "without the menu bar extra, Sextant would have no way back")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func turningEitherSettingOffBringsTheDockIconBack() async {
        for setting in [SettingsKey.showsInMenuBar, SettingsKey.keepsInMenuBar] {
            var applied: [NSApplication.ActivationPolicy] = []
            set(shows: true, keeps: true)
            let presence = makePresence { applied.append($0) }
            presence.windowOpened()
            presence.windowClosed()
            #expect(applied == [.accessory])
            defaults.set(false, forKey: setting)
            #expect(await eventually { applied == [.accessory, .regular] }, "\(setting)")
        }
        // Turning them on waits for the last window to close: the Dock icon doesn't vanish under Settings.
        var applied: [NSApplication.ActivationPolicy] = []
        set(shows: false, keeps: false)
        let presence = makePresence { applied.append($0) }
        set(shows: true, keeps: true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(applied.isEmpty && presence.policy == .regular)
        defaults.removePersistentDomain(forName: suite)
    }

    /// From the menu bar, the Dock icon comes back before the window opens, and Sextant activates after it.
    @Test func theDockIconReturnsBeforeAnyWindowOpens() async throws {
        set(shows: true, keeps: true)
        var calls: [String] = []
        let presence = makePresence {
            calls.append("policy \($0 == .accessory ? "accessory" : "regular")")
        }
        let library = Library(store: MemoryLibrary())
        _ = try await library.importOryxJSON(#require(userLayoutData))
        let router = WindowRouter(
            library: library, onKeyboard: nil, live: nil, presence: presence, activate: { calls.append("activate") })
        presence.windowOpened()
        presence.windowClosed()
        router.showMainWindow { _ in calls.append("open") }
        #expect(calls == ["policy accessory", "policy regular", "open", "activate"])

        calls = []
        presence.windowOpened()
        presence.windowClosed()
        router.buildAndFlash { _ in calls.append("open") }
        #expect(calls == ["policy accessory", "policy regular", "open", "activate"])

        calls = []
        presence.windowOpened()
        presence.windowClosed()
        router.showSettings { calls.append("settings") }
        #expect(calls == ["policy accessory", "policy regular", "settings", "activate"])
        defaults.removePersistentDomain(forName: suite)
    }

    /// Settings opened from the menu bar brings the Dock icon back; closing it, the last window, takes it away again.
    @Test func theLastOtherWindowClosingLeavesTheDockToo() async {
        set(shows: true, keeps: true)
        var applied: [NSApplication.ActivationPolicy] = []
        let windows = OpenWindows()
        let presence = makePresence(windows: { windows.count }) { applied.append($0) }
        presence.windowOpened()
        presence.windowClosed()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(applied.isEmpty, "Settings is still open")

        windows.count = 0
        windowNotifications.post(name: NSWindow.willCloseNotification, object: nil)
        #expect(await eventually { applied == [.accessory] })

        // A closing window can still count while it goes: Sextant looks once more after it has gone.
        presence.prepareToOpen()
        windows.count = 1
        windowNotifications.post(name: NSWindow.willCloseNotification, object: nil)
        windows.count = 0
        #expect(await eventually { applied == [.accessory, .regular, .accessory] })
        defaults.removePersistentDomain(forName: suite)
    }
}

/// How many windows a test says are open; a sendable closure can't read a local `var` that changes later.
@MainActor
private final class OpenWindows {
    var count = 1
}

/// Polls `condition`, letting other tasks run, for up to about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
