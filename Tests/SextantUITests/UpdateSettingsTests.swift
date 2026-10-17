import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// Settings › General's update choices and the menu bar's notice (ADR 0063).
@MainActor
struct UpdateSettingsTests {
    let suite = "UpdateSettingsTests-\(UUID().uuidString)"

    @Test func checkingIsOnByDefaultAndTheChoicesRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(UpdateSettings.saved(in: defaults) == UpdateChecker.Saved(checksAutomatically: true))
        let saved = UpdateChecker.Saved(
            checksAutomatically: false, lastChecked: Date(timeIntervalSince1970: 1_800_000_000), dismissed: AppVersion("0.3.0"))
        UpdateSettings.save(saved, in: defaults)
        #expect(UpdateSettings.saved(in: defaults) == saved)
        UpdateSettings.save(.init(), in: defaults)
        #expect(UpdateSettings.saved(in: defaults) == .init(), "no date or dismissed version left behind")
    }

    @Test func homebrewIsTheCaskroomOnEitherPrefix() {
        #expect(UpdateSettings.installedWithHomebrew { $0 == "/opt/homebrew/Caskroom/sextant" })
        #expect(UpdateSettings.installedWithHomebrew { $0 == "/usr/local/Caskroom/sextant" })
        #expect(!UpdateSettings.installedWithHomebrew { _ in false })
    }

    @Test func theMenuBarShowsANoticeUntilItIsSkipped() async throws {
        let page = try #require(URL(string: "https://github.com/afrase/Sextant/releases/tag/v0.3.0"))
        let newer = AppRelease(version: AppVersion(major: 0, minor: 3, patch: 0), page: page, download: page)
        let updates = UpdateChecker(current: AppVersion("0.2.0"), feed: OneRelease(release: newer), saved: .init())
        let fake = StandInKeyboard(serial: "KlgM7/40xJ7M")
        let live = LiveSession(watcher: fake, link: fake, secureInputProbe: { false })
        let store = MemoryLibrary()
        let library = Library(store: store)
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        func state() -> MenuBarPanelState {
            MenuBarPanelState(live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil, updates: updates)
        }
        #expect(state().update == nil, "nothing checked yet")
        await updates.check()
        #expect(state().update == newer.version)
        updates.dismiss()
        #expect(state().update == nil)
    }
}

private struct OneRelease: ReleaseFeed {
    var release: AppRelease
    func latest() async throws(UpdateCheckError) -> AppRelease { release }
}
