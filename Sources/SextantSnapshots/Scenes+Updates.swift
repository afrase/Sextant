import AppKit
import Foundation
import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

// The update checker (ADR 0063): the Software Update window in each state, Settings › General's Updates section and the
// menu bar's notice. A scripted feed answers; nothing reaches the network.

extension Scenes {
    static func updates(_ f: Fixtures) async -> [SnapshotScene] {
        let page = URL(string: "https://github.com/afrase/Sextant/releases/tag/v0.3.0") ?? URL(fileURLWithPath: "/")
        let newer = AppRelease(version: AppVersion(major: 0, minor: 3, patch: 0), page: page, download: page)
        let checked = Date(timeIntervalSinceNow: -3 * 3600)
        func checker(_ answer: Result<AppRelease, UpdateCheckError>?) async -> UpdateChecker {
            let updates = UpdateChecker(
                current: AppVersion(major: 0, minor: 2, patch: 0), feed: ScriptedFeed(answer: answer ?? .success(newer)),
                saved: .init(lastChecked: answer == nil ? nil : checked), now: { checked })
            if answer != nil { await updates.check() }
            return updates
        }
        let available = await checker(.success(newer))
        let states: [(String, UpdateChecker, Bool)] = [
            ("available", available, false), ("available-homebrew", available, true),
            (
                "up-to-date",
                await checker(.success(AppRelease(version: AppVersion(major: 0, minor: 2, patch: 0), page: page, download: page))), false
            ),
            ("failed", await checker(.failure(.offline)), false), ("idle", await checker(nil), false),
        ]
        var scenes: [SnapshotScene] = []
        for (name, updates, homebrew) in states {
            let size = NSHostingView(rootView: SoftwareUpdateWindow(updates: updates, installedWithHomebrew: homebrew)).fittingSize
            scenes += SnapshotScene.pair("software-update-\(name)", size: size, chrome: .window(title: "Software Update")) {
                SoftwareUpdateWindow(updates: updates, installedWithHomebrew: homebrew)
            }
        }
        scenes += SnapshotScene.pair("settings-general-updates", size: CGSize(width: 520, height: 560), chrome: .window(title: "General")) {
            GeneralSettings(updates: available)
        }
        let target = await f.windowModel().session?.layout.title ?? ""
        scenes += SnapshotScene.pair("menubar-panel-update", size: CGSize(width: 360, height: 300), chrome: .content) {
            MenuBarPanelContent(state: MenuBarPanelState(keyboard: .none, buildTarget: target, update: newer.version))
        }
        return scenes
    }
}

/// Answers every check the same way.
private struct ScriptedFeed: ReleaseFeed {
    var answer: Result<AppRelease, UpdateCheckError>
    func latest() async throws(UpdateCheckError) -> AppRelease { try answer.get() }
}
