import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

// The Heatmap lens (spec §8.5, ADR 0053) on the user's layout, with a week of typing made up in code: English letter
// frequencies on Main, brackets and digits on Sym+Num, arrows on Brd+Sys (seeded from PrototypeKit's sample). No real
// typing and no other person's layout reaches a scene.

extension Scenes {
    static func heatmap(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        func window(_ name: String, _ model: LayoutWindowModel, size: CGSize = full, light: Bool = false) {
            let make = { LayoutWindow(model: model, layoutID: .constant(f.entry.id)) }
            scenes += light ? [SnapshotScene("\(name)-light", size: size) { make() }] : SnapshotScene.pair(name, size: size) { make() }
        }
        func lens(layer: Int = 0, key: Int? = nil, hours: Bool = true, status: HeatmapRecorder.Status? = nil) async -> LayoutWindowModel {
            let model = await model(f, layer: layer, key: key)
            model.lens = .heatmap
            let typing = hours ? model.session.map { weekOfTyping($0.layout) } ?? [] : []
            model.heatmap.show(typing, of: f.entry.id, range: .week, status: status ?? .recording(f.entry.id))
            return model
        }

        // Main, recording; Sym+Num with ⏎ selected, whose strip gives its presses on each layer.
        window("heatmap", await lens())
        window("heatmap-symnum-key", await lens(layer: 1, key: 24), light: true)
        // Recording off with nothing recorded (the empty state); on, paused by Live View, with nothing in the range.
        window("heatmap-off", await lens(hours: false, status: .off))
        window("heatmap-no-data", await lens(hours: false, status: .waiting(.liveViewOff)), light: true)
        // Counts kept from before recording was turned off.
        window("heatmap-off-with-data", await lens(layer: 2, status: .off), light: true)
        window("heatmap-min", await lens(), size: CGSize(width: 1120, height: 640))
        // Recording's usual company: the live capsule while following, at the smallest window, recording and paused.
        for (name, status) in [
            ("heatmap-min-following", HeatmapRecorder.Status.recording(f.entry.id)), ("heatmap-min-following-off", .off),
        ] {
            let following = await lens(layer: 2, status: status)
            following.activity = ActivityState(
                device: connected, status: .onKeyboard(revisionDate: Date(timeIntervalSince1970: 1_789_000_000)))
            following.isFollowing = true
            window(name, following, size: CGSize(width: 1120, height: 640), light: true)
        }
        // Paused for a reason other than Live View, with counts and without.
        window("heatmap-paused", await lens(status: .waiting(.otherLayout)), light: true)
        window("heatmap-paused-no-data", await lens(hours: false, status: .waiting(.otherLayout)), light: true)

        // A store that can't be read or written: the inspector and Settings › Privacy say so.
        let failing = idleHeatmapRecorder(store: FailingHeatmapStore())
        _ = await failing.snapshot(of: f.entry.id, from: nil)
        if let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent() {
            let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)), heatmap: failing)
            await model.open(f.entry.id)
            model.buildFlash = await idleBuildFlash(model)
            model.lens = .heatmap
            window("heatmap-error", model, light: true)
        }
        scenes.append(
            SnapshotScene("settings-privacy-error-light", size: CGSize(width: 520, height: 440), chrome: .window(title: "Privacy")) {
                PrivacySettings(heatmap: failing)
            })

        // The menu bar panel's typing line, while recording and while paused.
        guard let layout = await model(f).session?.layout else { return scenes }
        let state = MenuBarPanelState(
            keyboard: .live, running: "\(layout.title), revision 1", layout: layout, layer: 0, buildTarget: layout.title)
        for (name, stats) in [
            ("typing", TypingStats(today: 12_408, wordsPerMinute: 64)),
            ("typing-paused", TypingStats(today: 12_408, wordsPerMinute: 0, pause: "Paused while you type in a password field")),
            (
                "typing-paused-long",
                TypingStats(today: 12_408, wordsPerMinute: 0, pause: "Paused: the keyboard runs a layout that isn’t in your library")
            ),
        ] {
            let size = NSHostingView(rootView: MenuBarPanelContent(state: state, typingStats: stats)).fittingSize
            scenes += SnapshotScene.pair("menubar-panel-\(name)", size: size, chrome: .content) {
                MenuBarPanelContent(state: state, typingStats: stats)
            }
        }
        return scenes
    }

    /// A recorder that is off, over no keyboard and an empty folder (or `store`), for Settings › Privacy. Nothing starts
    /// it.
    static func idleHeatmapRecorder(store heatmapStore: (any HeatmapStore)? = nil) -> HeatmapRecorder {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)")
        let store = PackageLibrary(root: folder.appending(path: "Library"))
        let library = Library(store: store)
        let keyboard = PluggedInKeyboard(serial: "KlgM7/40xJ7M")
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        return HeatmapRecorder(
            live: live, onKeyboard: OnKeyboard(library: library, store: store, live: live), library: library,
            store: heatmapStore ?? HeatmapFiles(root: folder.appending(path: "Heatmap")), isOn: false, retentionDays: 30)
    }

    /// A heatmap store on a disk that fails every read and write.
    private struct FailingHeatmapStore: HeatmapStore {
        func hours(of layoutID: UUID, from start: Date?) throws(HeatmapStoreError) -> [HeatmapHour] { throw .io("unreadable") }
        func add(_ hour: HeatmapHour, to layoutID: UUID) throws(HeatmapStoreError) { throw .io("disk full") }
        func prune(before date: Date) throws(HeatmapStoreError) { throw .io("disk full") }
        func clear(_ layoutID: UUID?) throws(HeatmapStoreError) { throw .io("disk full") }
    }

    /// About 140,000 presses over the last seven days, one hour a day.
    static func weekOfTyping(_ layout: KeyboardLayout, keystrokes: Double = 140_000) -> [HeatmapHour] {
        // Per-mille shares of every press.
        let letters: [String: Double] = [
            "E": 89, "T": 64, "A": 58, "O": 53, "I": 50, "N": 48, "S": 45, "H": 43, "R": 43, "D": 30, "L": 29, "C": 20, "U": 20,
            "M": 17, "W": 17, "F": 16, "G": 14, "Y": 14, "P": 14, "B": 11, "V": 7, "K": 6, "J": 1.1, "X": 1.1, "Q": 0.7, "Z": 0.5,
        ]
        var main = Dictionary(uniqueKeysWithValues: letters.map { ("KC_\($0.key)", $0.value) })
        let other: [String: Double] = [
            "KC_SPACE": 150, "KC_BSPC": 52, "KC_ENTER": 16, "KC_LEFT_SHIFT": 17, "KC_QUOTE": 12, "KC_COMMA": 11, "KC_DOT": 10,
            "KC_TAB": 7, "KC_EQUAL": 5, "KC_SCLN": 3, "KC_MINUS": 3, "KC_SLASH": 4, "KC_BSLS": 0.4, "KC_LEFT_CTRL": 5,
            "KC_LEFT_GUI": 30, "KC_RIGHT_CTRL": 0.8, "KC_1": 2.2, "KC_2": 2.0, "KC_3": 1.6, "KC_4": 1.3, "KC_5": 1.2, "KC_6": 1.0,
            "KC_7": 0.9, "KC_8": 0.9, "KC_9": 1.0, "KC_0": 1.8,
        ]
        main.merge(other) { $1 }
        let perMille = keystrokes / 1000
        var counts: [Int: [Int: Double]] = [:]
        for (index, key) in (layout.layers.first?.keys ?? []).enumerated() {
            counts[0, default: [:]][index] = key.actions.reduce(0) { $0 + (main[$1.action.code] ?? 0) } * perMille
        }
        // Sym+Num: brackets, digits and operators. Brd+Sys: arrows, then history and media.
        let symbols: [Int: Double] = [
            16: 9, 17: 9, 20: 4, 21: 4, 22: 6, 23: 6, 13: 1.5, 14: 2, 15: 2.5, 7: 2, 8: 1.5, 9: 1.2, 10: 1.6, 6: 2.4, 32: 2.5,
            33: 2.2, 34: 2.1, 38: 2.4, 39: 2.3, 40: 2.2, 44: 3.4, 45: 3.0, 46: 2.6, 51: 3.6, 47: 1.8, 48: 3.0, 41: 1.6, 42: 1.2,
        ]
        let navigation: [Int: Double] = [
            38: 11, 39: 9, 40: 9, 41: 11, 32: 2.2, 35: 2.4, 33: 1.4, 34: 1.4, 44: 3.2, 46: 2.8, 8: 0.9, 9: 1.1,
        ]
        counts[1] = symbols.mapValues { $0 * perMille }
        counts[2] = navigation.mapValues { $0 * perMille }
        // Each layer's thumb key is pressed once a time the layer is reached.
        let reached = [1: 2_140.0, 2: 1_630.0]
        counts[0, default: [:]][24, default: 0] += reached[1] ?? 0
        counts[0, default: [:]][51, default: 0] += reached[2] ?? 0
        // Busier on weekdays.
        let days: [Double] = [0.18, 0.17, 0.16, 0.17, 0.16, 0.08, 0.08]
        let now = HeatmapHour.start(of: Date())
        return days.enumerated().map { day, share in
            var hour = HeatmapHour(start: now.addingTimeInterval(-Double(day) * 24 * HeatmapHour.duration))
            for (layer, keys) in counts {
                guard let id = layout.layers[safe: layer]?.id else { continue }
                hour.presses[id] = keys.compactMapValues { count in
                    let n = Int((count * share).rounded())
                    return n > 0 ? n : nil
                }
            }
            for (layer, times) in reached {
                if let id = layout.layers[safe: layer]?.id { hour.layerEntries[id] = Int((times * share).rounded()) }
            }
            return hour
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
