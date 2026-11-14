import Foundation
import SextantApplication
import SextantDomain
import Testing

/// The in-app updater's use case (ADR 0070): it mirrors the updater for the menus, Settings and the menu bar.
@MainActor
struct SoftwareUpdatesTests {
    @Test func itMirrorsTheUpdaterAndForwardsChoices() {
        let updater = FakeUpdater()
        updater.lastChecked = Date(timeIntervalSince1970: 1_800_000_000)
        let updates = SoftwareUpdates(updater: updater)
        #expect(updates.isSupported && updates.checksAutomatically && !updates.installsAutomatically)
        #expect(updates.current == AppVersion(major: 0, minor: 4, patch: 0))
        #expect(updates.lastChecked == updater.lastChecked)
        updates.checksAutomatically = false
        updates.installsAutomatically = true
        #expect(!updater.checksAutomatically && updater.installsAutomatically)
    }

    @Test func checkingWaitsForTheUpdaterToAllowIt() {
        let updater = FakeUpdater()
        let updates = SoftwareUpdates(updater: updater)
        updates.check()
        #expect(updater.checks == 0, "not started")
        updates.start()
        updates.start()
        #expect(updater.starts == 1)
        updater.report?(.canCheck(true))
        updates.check()
        #expect(updater.checks == 1)
        updater.report?(.canCheck(false))
        updates.check()
        #expect(updater.checks == 1, "a check or an install is under way")
    }

    @Test func aBackgroundUpdateIsNoticedUntilSeenOrFinished() {
        let updater = FakeUpdater()
        let updates = SoftwareUpdates(updater: updater)
        updates.start()
        let version = AppVersion(major: 0, minor: 5, patch: 0)
        updater.report?(.found(version))
        #expect(updates.notice == version)
        updater.report?(.seen)
        #expect(updates.notice == nil)
        updater.report?(.found(version))
        updater.report?(.finished)
        #expect(updates.notice == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_100)
        updater.report?(.checked(date))
        #expect(updates.lastChecked == date)
    }

    @Test func choicesMadeInTheUpdatersWindowShowInSettingsWithoutBeingWrittenBack() {
        let updater = FakeUpdater()
        let updates = SoftwareUpdates(updater: updater)
        updates.start()
        updater.installsAutomatically = true
        updater.report?(.installsAutomatically(true))
        #expect(updates.installsAutomatically)
        #expect(updater.writes == 0, "only copied in")
        updater.report?(.checksAutomatically(false))
        #expect(!updates.checksAutomatically && updater.writes == 0)
    }

    @Test func turningChecksOffShowsAutomaticInstallsOffToo() {
        let updater = FakeUpdater()
        updater.installsAutomatically = true
        let updates = SoftwareUpdates(updater: updater)
        updater.installsGoOffWithChecks = true
        updates.checksAutomatically = false
        #expect(!updates.installsAutomatically, "as the updater reads it")
    }

    @Test func aBuildThatCantUpdateNeverStarts() {
        let updater = FakeUpdater()
        updater.isSupported = false
        let updates = SoftwareUpdates(updater: updater)
        updates.start()
        updates.check()
        #expect(updater.starts == 0 && updater.checks == 0 && !updates.canCheck)
    }
}

@MainActor
private final class FakeUpdater: SoftwareUpdater {
    var isSupported = true
    var checksAutomatically = true {
        didSet {
            writes += 1
            if installsGoOffWithChecks, !checksAutomatically { installsAutomatically = false }
        }
    }
    var installsAutomatically = false
    /// Sparkle's getter: no automatic installs without automatic checks.
    var installsGoOffWithChecks = false
    var writes = 0
    var lastChecked: Date?
    let version: AppVersion? = AppVersion(major: 0, minor: 4, patch: 0)
    var report: (@MainActor (SoftwareUpdateEvent) -> Void)?
    var starts = 0
    var checks = 0

    func start(report: @escaping @MainActor (SoftwareUpdateEvent) -> Void) {
        starts += 1
        self.report = report
    }

    func checkForUpdates() { checks += 1 }
}
