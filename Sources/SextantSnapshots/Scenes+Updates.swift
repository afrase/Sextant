import Foundation
import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

// In-app updates (ADR 0070): Settings › General's Updates section, on a release build and on one that can't update
// itself, and the menu bar's reminder. Sparkle's own windows aren't Sextant's to draw. A stand-in updater answers;
// nothing reaches the network.

extension Scenes {
    static func updates(_ f: Fixtures) async -> [SnapshotScene] {
        let release = SoftwareUpdates(updater: StandInUpdater(isSupported: true, lastChecked: Date(timeIntervalSinceNow: -3 * 3600)))
        release.start()
        let local = SoftwareUpdates(updater: StandInUpdater(isSupported: false, lastChecked: nil))
        var scenes: [SnapshotScene] = []
        for (name, updates) in [("", release), ("-unsupported", local)] {
            scenes += SnapshotScene.pair(
                "settings-general-updates\(name)", size: CGSize(width: 520, height: 620), chrome: .window(title: "General")
            ) { GeneralSettings(updates: updates) }
        }
        let target = await f.windowModel().session?.layout.title ?? ""
        scenes += SnapshotScene.pair("menubar-panel-update", size: CGSize(width: 360, height: 300), chrome: .content) {
            MenuBarPanelContent(
                state: MenuBarPanelState(keyboard: .none, buildTarget: target, update: AppVersion(major: 0, minor: 5, patch: 0)))
        }
        return scenes
    }
}

/// An updater that is idle and ready, checking automatically, as a release build is between checks.
@MainActor
private final class StandInUpdater: SoftwareUpdater {
    let isSupported: Bool
    var checksAutomatically = true
    var installsAutomatically = false
    let lastChecked: Date?
    let version: AppVersion? = AppVersion(major: 0, minor: 4, patch: 0)

    init(isSupported: Bool, lastChecked: Date?) {
        self.isSupported = isSupported
        self.lastChecked = lastChecked
    }

    func start(report: @escaping @MainActor (SoftwareUpdateEvent) -> Void) { report(.canCheck(true)) }
    func checkForUpdates() {}
}
