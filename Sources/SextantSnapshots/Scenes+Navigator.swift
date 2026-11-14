import AppKit
import SextantApplication
import SextantDomain
import SextantUI
import SwiftUI

// Settings › Navigator and the board's Navigator popover (ADRs 0068 and 0069), over a driver whose ports are stand-ins:
// nothing here opens a device, posts an event or asks for a permission.
extension Scenes {
    static func navigator(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        let running = await driver(input: true, post: true, pad: true)
        let waiting = await driver(input: true, post: false, pad: false)
        var off = TrackpadSettings()
        off.isEnabled = false
        let idle = await driver(input: true, post: true, pad: false, settings: off)
        scenes += SnapshotScene.pair("settings-navigator", size: CGSize(width: 520, height: 1500), chrome: .window(title: "Navigator")) {
            NavigatorSettings(driver: running)
        }
        scenes.append(
            SnapshotScene(
                "settings-navigator-permissions-light", size: CGSize(width: 520, height: 620), chrome: .window(title: "Navigator")
            ) {
                NavigatorSettings(driver: waiting)
            })
        let trackpad = NavigatorConfig(kind: .trackpad, side: .right)
        for (name, driver, config) in [
            ("running", running, trackpad), ("permissions", waiting, trackpad), ("off", idle, trackpad),
            ("trackball", idle, NavigatorConfig(kind: .trackball, side: .left)),
        ] {
            let make = { NavigatorPopover(navigator: config, driver: driver, showMacSettings: {}, showFirmwareSettings: {}) }
            let size = NSHostingView(rootView: make()).fittingSize
            scenes += SnapshotScene.pair("navigator-popover-\(name)", size: size, chrome: .content) { make() }
        }
        return scenes
    }

    /// A driver that is on, with the given permissions and (optionally) one trackpad attached.
    private static func driver(input: Bool, post: Bool, pad: Bool, settings: TrackpadSettings? = nil) async -> TrackpadDriver {
        var on = TrackpadSettings()
        on.isEnabled = true
        let driver = TrackpadDriver(
            link: StandInLink(access: input, hasPad: pad), output: StandInOutput(access: post), system: StandInSystem(),
            clock: ContinuousClock(), now: { 0 }, settings: settings ?? on, save: { _ in })
        await driver.start()
        for _ in 0..<50 where pad && driver.status != .running { try? await Task.sleep(for: .milliseconds(10)) }
        return driver
    }

    private struct StandInLink: TrackpadLink {
        var access: Bool
        var hasPad: Bool
        func hasInputAccess() async -> Bool { access }
        func requestInputAccess() async -> Bool { access }
        func session() -> AsyncStream<TrackpadEvent> {
            AsyncStream { continuation in if hasPad { continuation.yield(.attached(TrackpadID(1))) } }
        }
        func setInputMode(_ mode: TrackpadInputMode, on pad: TrackpadID) async throws(TrackpadError) {}
    }

    private struct StandInOutput: PointerOutput {
        var access: Bool
        func hasAccess() async -> Bool { access }
        func requestAccess() async -> Bool { access }
        func post(_ intents: [PointerIntent]) async {}
    }

    private struct StandInSystem: SystemPointerSettings {
        func current() async -> SystemPointerPreferences { .standard }
    }
}
