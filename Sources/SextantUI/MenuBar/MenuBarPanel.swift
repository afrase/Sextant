import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// What the panel's controls do. The live panel routes them to the app's use cases; snapshots pass none.
struct MenuBarActions {
    var moveToLayer: @MainActor (Int) -> Void = { _ in }
    /// The same path as the toolbar's live button (ADR 0057): only ever on the user's click.
    var turnOnLiveView: @MainActor () -> Void = {}
    var buildAndFlash: @MainActor () -> Void = {}
    var openSextant: @MainActor () -> Void = {}
    var openSettings: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

/// The menu bar extra's panel over the app's live session (spec §8.3).
struct MenuBarPanel: View {
    var services: SextantServices
    var windows: WindowRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let state = MenuBarPanelState(
            live: services.live, onKeyboard: services.onKeyboard, shortcuts: services.layerShortcuts, library: services.library)
        let open: WindowRouter.OpenWindow = { openWindow.layout($0) }
        MenuBarPanelContent(
            state: state,
            actions: MenuBarActions(
                moveToLayer: { try? services.onKeyboard.moveKeyboard(toLayer: $0) },
                turnOnLiveView: { services.live.startLive() },
                buildAndFlash: { windows.buildAndFlash(open) },
                openSextant: { windows.showMainWindow(open) },
                openSettings: { windows.showSettings { openSettings() } },
                quit: { NSApplication.shared.terminate(nil) }))
    }
}

/// The panel itself, drawn from a ``MenuBarPanelState``: 360 pt wide and under 520 pt tall, with no text fields (spec
/// §13.3).
public struct MenuBarPanelContent: View {
    var state: MenuBarPanelState
    var actions = MenuBarActions()
    @AppStorage(SettingsKey.showsOverlay) private var showsOverlay = true

    static let width: CGFloat = 360
    /// Rows shown before the list of layers scrolls, which keeps the panel under 520 pt with 32 layers.
    static let visibleRows = 5
    static let rowHeight: CGFloat = 22

    /// A panel whose controls do nothing, for snapshots.
    public init(state: MenuBarPanelState) { self.state = state }

    init(state: MenuBarPanelState, actions: MenuBarActions) {
        self.state = state
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            keyboard
            // The switch at the trailing edge, as in a menu; a bare Toggle puts it right after its label.
            HStack {
                Text("Show overlay while holding a layer")
                Spacer()
                Toggle("Show overlay while holding a layer", isOn: $showsOverlay).toggleStyle(.switch).controlSize(.small)
                    .labelsHidden()
            }
            Divider()
            VStack(spacing: 0) {
                buildAndFlashRow
                MenuBarRow(title: String(localized: "Open Sextant"), shortcut: "⌘0", action: actions.openSextant)
                    .keyboardShortcut("0")
                MenuBarRow(title: String(localized: "Settings…"), shortcut: "⌘,", action: actions.openSettings).keyboardShortcut(",")
                MenuBarRow(title: String(localized: "Quit Sextant"), shortcut: "⌘Q", action: actions.quit).keyboardShortcut("q")
            }
            .padding(.horizontal, -6)
        }
        .padding(14)
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            SextantGlyph(progress: state.flash?.progress).fill(.secondary).frame(width: 26, height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: state.boardName).font(.headline)
                Text(state.status).font(.caption).foregroundStyle(.secondary)
                if let running = state.running {
                    Text(verbatim: running).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if state.keyboard == .live, let layer = state.layer { LayerPips(layer: layer) }
            Button(action: actions.openSettings) {
                Image(systemName: "gearshape").font(.body)
            }
            .buttonStyle(.borderless)
            .help(Text("Settings"))
            .accessibilityLabel(Text("Settings"))
        }
    }

    @ViewBuilder private var keyboard: some View {
        switch state.keyboard {
        case .none: note(Text("Connect your keyboard with a USB cable."), symbol: "cable.connector")
        case .flashMode:
            if let flash = state.flash, let progress = flash.progress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Writing \(flash.title) to the keyboard").font(.callout)
                    ProgressView(value: progress).progressViewStyle(.linear)
                        .accessibilityLabel(Text("Writing firmware, \(Int((progress * 100).rounded())) percent"))
                }
            } else {
                note(Text("The keyboard is in flash mode, ready for Build & Flash."), symbol: "bolt.fill")
            }
        case .heldByAnotherApp:
            note(Text(verbatim: DeviceError.heldByAnotherApp.localizedDescription), symbol: "exclamationmark.triangle.fill")
        case .liveOff:
            VStack(alignment: .leading, spacing: 8) {
                note(
                    Text(
                        "Live View is off. Turn it on to see the keyboard’s layer and the keys you press, and to switch layers here."
                    ), symbol: "dot.radiowaves.left.and.right")
                Button("Turn On Live View", action: actions.turnOnLiveView).controlSize(.small)
            }
        case .connecting, .live: MenuBarLayers(state: state, moveToLayer: actions.moveToLayer)
        }
    }

    private var buildAndFlashRow: some View {
        let title =
            if let flash = state.flash {
                flash.progress.map { String(localized: "Flashing… \(Int(($0 * 100).rounded()))%") }
                    ?? String(localized: "Waiting to flash \(flash.title)…")
            } else {
                String(localized: "Build & Flash…")
            }
        return MenuBarRow(title: title, shortcut: state.flash == nil ? "⌘R" : nil, action: actions.buildAndFlash)
            .keyboardShortcut("r")
            .disabled(!state.canBuildAndFlash)
    }

    private func note(_ text: Text, symbol: String) -> some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

/// A menu-style row (spec §8.3's native rows): highlighted under the pointer, its shortcut on the right.
struct MenuBarRow<Title: View>: View {
    var shortcut: String?
    var action: @MainActor () -> Void
    @ViewBuilder var title: Title
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let lit = isHovered && isEnabled
        Button(action: action) {
            HStack {
                title
                Spacer()
                if let shortcut { Text(verbatim: shortcut).opacity(lit ? 1 : 0.55).accessibilityHidden(true) }
            }
            .padding(.horizontal, 6)
            .frame(height: MenuBarPanelContent.rowHeight)
            .contentShape(Rectangle())
            .foregroundStyle(lit ? Color.white : .primary)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(lit ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension MenuBarRow where Title == Text {
    init(title: String, shortcut: String?, action: @escaping @MainActor () -> Void) {
        self.init(shortcut: shortcut, action: action) { Text(verbatim: title) }
    }
}
