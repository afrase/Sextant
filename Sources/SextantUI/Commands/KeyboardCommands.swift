import SwiftUI

struct KeyboardMenu: View {
    var window: LayoutWindowModel?

    var body: some View {
        Button("Build") { window?.build(.build) }.keyboardShortcut("b").disabled(window?.canBuild != true)
        Button("Build & Flash") { window?.build(.buildAndFlash) }.keyboardShortcut("r").disabled(window?.canBuild != true)
        Button("Stop") { window?.build(.stop) }.keyboardShortcut(".").disabled(window?.canStop != true)
        Button("Show Build Log") { window?.build(.showLog) }
            .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(window?.onBuild == nil || window?.session == nil)
        Divider()
        Button("Next Issue") {}.keyboardShortcut("'").disabled(true)
        Button("Previous Issue") {}.keyboardShortcut("'", modifiers: [.command, .shift]).disabled(true)
        Divider()
        Toggle("Follow Keyboard", isOn: Binding(get: { window?.isFollowing == true }, set: { window?.isFollowing = $0 }))
            .keyboardShortcut("l").disabled(window?.canFollow != true)
        Menu("Move Keyboard to Layer") {}.disabled(true)
        Button("Preview Lighting on Keyboard") {}.disabled(true)
        Button("Show Overlay While Holding a Layer") {}.disabled(true)
        Divider()
        Button("Device Info…") {}.disabled(true)
        Button("Flash Oryx’s Build of This Revision…") {}.disabled(true)
    }
}
