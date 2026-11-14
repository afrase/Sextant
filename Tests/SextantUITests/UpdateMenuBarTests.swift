import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// The menu bar's update reminder (ADR 0070).
@MainActor
struct UpdateMenuBarTests {
    @Test func theMenuBarRemindsUntilTheUpdateIsSeen() {
        let updater = ReportingUpdater()
        let updates = SoftwareUpdates(updater: updater)
        updates.start()
        let fake = StandInKeyboard(serial: "KlgM7/40xJ7M")
        let live = LiveSession(watcher: fake, link: fake, secureInputProbe: { false })
        let store = MemoryLibrary()
        let library = Library(store: store)
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        func state() -> MenuBarPanelState {
            MenuBarPanelState(live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil, updates: updates)
        }
        #expect(state().update == nil, "nothing found yet")
        updater.report?(.found(AppVersion(major: 0, minor: 5, patch: 0)))
        #expect(state().update == AppVersion(major: 0, minor: 5, patch: 0))
        updater.report?(.seen)
        #expect(state().update == nil)
    }
}

@MainActor
private final class ReportingUpdater: SoftwareUpdater {
    let isSupported = true
    var checksAutomatically = true
    var installsAutomatically = false
    let lastChecked: Date? = nil
    let version: AppVersion? = AppVersion(major: 0, minor: 4, patch: 0)
    var report: (@MainActor (SoftwareUpdateEvent) -> Void)?

    func start(report: @escaping @MainActor (SoftwareUpdateEvent) -> Void) { self.report = report }
    func checkForUpdates() {}
}
