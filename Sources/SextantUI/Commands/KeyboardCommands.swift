import SextantApplication
import SwiftUI

struct KeyboardMenu: View {
    var window: LayoutWindowModel?
    var onKeyboard: OnKeyboard?
    var live: LiveSession?
    var layerShortcuts: LayerShortcuts?
    @AppStorage(SettingsKey.showsOverlay) private var showsOverlay = true

    var body: some View {
        Button("Build") { window?.build(.build) }.keyboardShortcut("b").disabled(window?.canBuild != true)
        Button("Build & Flash") { window?.build(.buildAndFlash) }.keyboardShortcut("r").disabled(window?.canBuild != true)
        Button("Stop") { window?.build(.stop) }.keyboardShortcut(".").disabled(window?.canStop != true)
        Button("Show Build Log") { window?.build(.showLog) }
            .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(window?.buildFlash == nil)
        Button("Flash This Revision…") { if let revision = window?.shownRevision { window?.flash(revision) } }
            .disabled(window?.shownRevision.map { window?.canFlash($0) != true } ?? true)
        Divider()
        Button("Next Issue") {}.keyboardShortcut("'").disabled(true)
        Button("Previous Issue") {}.keyboardShortcut("'", modifiers: [.command, .shift]).disabled(true)
        Divider()
        Toggle("Live View", isOn: Binding(get: { window?.isLive == true }, set: { window?.isLive = $0 }))
            .disabled(window?.isLive != true && window?.canGoLive != true)
        Toggle("Follow Keyboard", isOn: Binding(get: { window?.isFollowing == true }, set: { window?.isFollowing = $0 }))
            .keyboardShortcut("l").disabled(window?.canFollow != true)
        MoveKeyboardToLayerMenu(onKeyboard: onKeyboard, live: live, shortcuts: layerShortcuts)
        Toggle(
            "Preview Lighting on Keyboard",
            isOn: Binding(get: { window?.previewsLighting == true }, set: { window?.previewsLighting = $0 })
        )
        .disabled(window?.previewsLighting != true && (window?.lightingPreviewRefusal != nil || window?.session == nil))
        Toggle("Show Overlay While Holding a Layer", isOn: $showsOverlay)
        Divider()
        Button("Device Info…") { window?.device.popover = .capsule }.disabled(window?.live == nil)
        // shortcut: BuildFlashSession has no path to flash a stored Oryx image yet; enable when it gets one (spec §7.1).
        Button("Flash Oryx’s Build of This Revision…") {}.disabled(true)
    }
}
