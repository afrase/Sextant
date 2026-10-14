import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

extension Scenes {
    /// Layers and the Lighting lens (spec §3.6, §3.8, §6.1, §6.2).
    static func layers(_ f: Fixtures) async -> [SnapshotScene] {
        // Loaded before the edits below, like every model here.
        let previews = await lightingPreview(f)
        let rename = await model(f, layer: 1)
        let menu = await model(f, layer: 1)
        let summary = await model(f, layer: 1)
        let lighting = await model(f, layer: 2)
        let lightingMin = await model(f, layer: 2)
        // Edits come after every model has loaded, so their autosaves can't leak into another scene.
        rename.startRenaming(layer: 1)
        let brush = KeyboardLayout.defaultSwatch.first ?? HexColor(red: 1, green: 0, blue: 0)
        for m in [lighting, lightingMin] {
            m.lens = .lighting
            m.session?.paint(brush, keys: [14, 15, 16, 20], layer: 2)
        }
        // Live presses light in every lens (spec §2.2).
        lightingMin.pressedKeys.update([15, 31])

        func window(_ name: String, _ model: LayoutWindowModel, size: CGSize = full, overlays: [SnapshotOverlay] = []) -> [SnapshotScene] {
            SnapshotScene.pair(name, size: size, overlays: overlays) { LayoutWindow(model: model, layoutID: .constant(f.entry.id)) }
        }
        // The context menu on Sym+Num with Colour ▸ open. Real menus can't render offscreen, so this draws their items.
        let menus = [
            SnapshotOverlay.menu(size: CGSize(width: 200, height: 0), at: CGPoint(x: 150, y: 190)) { layerMenu(open: "Color") },
            SnapshotOverlay.menu(size: CGSize(width: 150, height: 0), at: CGPoint(x: 346, y: 222)) { colourMenu },
        ]
        return window("layers-rename", rename) + window("layers-color-menu", menu, overlays: menus)
            + window("layers-summary", summary) + window("lighting", lighting)
            + [
                SnapshotScene("lighting-min-light", size: CGSize(width: 1120, height: 640)) {
                    LayoutWindow(model: lightingMin, layoutID: .constant(f.entry.id))
                }
            ] + previews
    }

    /// The Lighting inspector's "On the keyboard" (ADR 0051): previewing Brd+Sys at 60%, another layout's window
    /// previewing, and Live View off. (`lighting` above has no keyboard.) The keyboard is a stand-in, and no window feeds
    /// the preview, so nothing is sent anywhere.
    static func lightingPreview(_ f: Fixtures) async -> [SnapshotScene] {
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent() else { return [] }
        func window(_ live: LiveSession, _ preview: LightingPreview) async -> LayoutWindowModel {
            let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)), live: live, lightingPreview: preview)
            await model.open(f.entry.id)
            model.buildFlash = await idleBuildFlash(model)
            model.session?.select(layer: 2)
            model.lens = .lighting
            Task { await model.followKeyboard() }
            return model
        }
        let paired = LightingKeyboard()
        let live = LiveSession(watcher: paired, link: paired, secureInputProbe: { false })
        live.start()
        live.startLive()
        let preview = LightingPreview(live: live)
        preview.start()
        let on = await window(live, preview)
        // A preview of its own, held by another layout's window (one window per layout: `on` stands in for it).
        let elsewherePreview = LightingPreview(live: live)
        let elsewhere = await window(live, elsewherePreview)
        for _ in 0..<250 where !live.canSend { try? await Task.sleep(for: .milliseconds(20)) }
        try? preview.claim(for: on, title: on.session?.layout.title ?? "")
        preview.setBrightness(0.6)
        try? elsewherePreview.claim(for: on, title: "Travel")

        let plugged = LightingKeyboard()
        let liveOff = LiveSession(watcher: plugged, link: plugged, secureInputProbe: { false })
        liveOff.start()
        let off = await window(liveOff, LightingPreview(live: liveOff))
        for _ in 0..<50 where liveOff.connection == .noKeyboard { try? await Task.sleep(for: .milliseconds(10)) }

        func scenes(_ name: String, _ model: LayoutWindowModel) -> [SnapshotScene] {
            SnapshotScene.pair(name, size: full) { LayoutWindow(model: model, layoutID: .constant(f.entry.id)) }
        }
        return scenes("lighting-preview-on", on) + scenes("lighting-preview-live-off", off)
            + [
                SnapshotScene("lighting-preview-elsewhere-light", size: full) {
                    LayoutWindow(model: elsewhere, layoutID: .constant(f.entry.id))
                }
            ]
    }

    /// A layer's context menu with the submenu `open` highlighted.
    static func layerMenu(open: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let items = [
                "Rename…", "Color", "-", "Duplicate", "Move Up", "Move Down", "-", "Copy Layer To", "Clear Layer…", "Delete Layer…",
            ]
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if item == "-" {
                    Divider().padding(.vertical, 4)
                } else {
                    HStack {
                        Text(item)
                        Spacer()
                        if ["Color", "Copy Layer To"].contains(item) { Image(systemName: "chevron.right").font(.caption) }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(item == open ? Color.accentColor.opacity(0.85) : .clear, in: .rect(cornerRadius: 5))
                }
            }
        }
        .padding(5)
    }

    private static var colourMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(KeyboardLayout.defaultSwatch, id: \.self) { color in
                // Sym+Num's #00F0FF isn't a swatch, so nothing is ticked.
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(color.color).frame(width: 12, height: 12)
                    Text(verbatim: color.hex).monospacedDigit()
                }
                .padding(.leading, 26)
                .frame(height: 22)
            }
            Divider().padding(.vertical, 4)
            Text("Custom…").padding(.horizontal, 26).frame(height: 22)
            Text("No Color").padding(.horizontal, 26).frame(height: 22)
        }
        .padding(5)
    }
}

/// The user's keyboard, present from the start; once Live View starts, its session reports Brd+Sys and stays open. It never
/// reads the commands it is given.
private struct LightingKeyboard: DeviceWatcher, KeyboardLink {
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        AsyncStream { $0.yield(.layer(2)) }
    }
}
