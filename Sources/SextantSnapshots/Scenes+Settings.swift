import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

// Settings › Keyboard and Advanced (spec §8.9), and the Device popover with the raw-HID log on (ADR 0045). The log's
// entries are what RawHIDLink traces for this session; nothing here touches hardware.

extension Scenes {
    static func settings(_ f: Fixtures) async -> [SnapshotScene] {
        var scenes: [SnapshotScene] = []
        scenes += SnapshotScene.pair("settings-keyboard", size: CGSize(width: 520, height: 520), chrome: .window(title: "Keyboard")) {
            KeyboardSettings()
        }
        let trace = RawHIDTrace { false }
        trace.isOn = true
        scenes += SnapshotScene.pair("settings-advanced", size: CGSize(width: 520, height: 250), chrome: .window(title: "Advanced")) {
            AdvancedSettings(trace: trace)
        }

        // Following the keyboard on Brd+Sys with keys 51 and 13 down, the log open in the Device popover.
        let board = BoardDefinition.voyager
        let (k51, k13) = (board.keys[51], board.keys[13])
        let log = RawHIDTrace { false }
        log.isOn = true
        let keyboard = OneKeyboard(script: [
            .protocolVersion(5), .layer(2), .keyDown(row: k51.matrixRow, column: k51.matrixColumn),
            .keyDown(row: k13.matrixRow, column: k13.matrixColumn),
        ])
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        live.start()
        live.startLive()
        guard let model = await model(f, live: live) else { return scenes }
        Task { await model.followKeyboard() }
        let entries = session(keys: [k51, k13])
        entries.forEach(log.record)
        for _ in 0..<250 where log.entries.count < entries.count || model.session?.selection.layer != 2 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        scenes += SnapshotScene.pair(
            "device-popover-trace", size: full,
            overlays: [
                .popover(size: CGSize(width: 360, height: 0), anchor: CGRect(x: 560, y: 14, width: 150, height: 26)) {
                    DevicePopover(model: model).environment(log)
                }
            ]
        ) { LayoutWindow(model: model, layoutID: .constant(f.entry.id)) }
        return scenes
    }

    /// The fixtures' layout in a window over `live`, with Build & Flash on fakes so it draws enabled.
    private static func model(_ f: Fixtures, live: LiveSession) async -> LayoutWindowModel? {
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent() else { return nil }
        let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)), live: live)
        await model.open(f.entry.id)
        model.buildFlash = await idleBuildFlash(model)
        return model
    }

    /// The reports of a handshake with KlgM7/40xJ7M on layer 2, then `keys` going down, as RawHIDLink traces them.
    private static func session(keys: [BoardDefinition.KeyInfo]) -> [HIDTraceEntry] {
        let serial = Array("KlgM7/40xJ7M".utf8)
        var reports: [(HIDTraceEntry.Direction, [UInt8], LiveEvent?)] = [
            (.sent, [0xFE], nil), (.received, [0xFE, 0x05, 0xFE], .protocolVersion(5)), (.sent, [0x00], nil),
            (.received, [0x00] + serial + [0xFE], .firmwareSerial("KlgM7/40xJ7M")), (.sent, [0x01], nil),
            (.received, [0x05, 0x02, 0xFE], .layer(2)),
        ]
        for key in keys {
            reports.append(
                (
                    .received, [0x06, UInt8(key.matrixColumn), UInt8(key.matrixRow), 0xFE],
                    .keyDown(row: key.matrixRow, column: key.matrixColumn)
                ))
        }
        let start = DateComponents(calendar: .current, year: 2026, month: 10, day: 12, hour: 9, minute: 41, second: 7).date ?? .now
        return reports.enumerated().map { n, report in
            // The handshake takes milliseconds; the keys go down a few seconds later.
            let offset = n < 6 ? Double(n) * 0.006 : 3.2 + Double(n - 6) * 0.41
            return HIDTraceEntry(date: start + offset, direction: report.0, bytes: report.1, event: report.2)
        }
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
