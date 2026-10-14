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

extension MenuBarActions {
    /// The live panel's controls. Live View starts only on Turn On Live View, and a layer reaches the keyboard only
    /// through Move Keyboard to Layer (ADR 0048).
    @MainActor
    init(
        live: LiveSession, onKeyboard: OnKeyboard, windows: WindowRouter, openWindow: @escaping WindowRouter.OpenWindow,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.init(
            moveToLayer: { try? onKeyboard.moveKeyboard(toLayer: $0) },
            turnOnLiveView: { live.startLive() },
            buildAndFlash: { windows.buildAndFlash(openWindow) },
            openSextant: { windows.showMainWindow(openWindow) },
            openSettings: { windows.showSettings(openSettings) },
            quit: { NSApplication.shared.terminate(nil) })
    }
}

/// The menu bar extra's panel over the app's live session (spec §8.3).
struct MenuBarPanel: View {
    var live: LiveSession
    var onKeyboard: OnKeyboard
    var shortcuts: LayerShortcuts?
    var library: Library
    var windows: WindowRouter
    var heatmap: HeatmapRecorder?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let state = MenuBarPanelState(
            live: live, onKeyboard: onKeyboard, shortcuts: shortcuts, library: library, buildTarget: windows.target)
        // Words per minute fall as typing stops, with no press to redraw the panel.
        TimelineView(.periodic(from: .now, by: heatmap?.isOn == true ? 5 : 3600)) { context in
            MenuBarPanelContent(
                state: state,
                actions: MenuBarActions(
                    live: live, onKeyboard: onKeyboard, windows: windows, openWindow: { openWindow.layout($0) },
                    openSettings: { openSettings() }),
                typingStats: heatmap.flatMap { TypingStats($0, at: context.date) })
        }
    }
}

extension MenuBarPanel {
    init(services: SextantServices, windows: WindowRouter) {
        self.init(
            live: services.live, onKeyboard: services.onKeyboard, shortcuts: services.layerShortcuts, library: services.library,
            windows: windows, heatmap: services.heatmap)
    }
}

/// The panel itself, drawn from a ``MenuBarPanelState``: 360 pt wide and under 520 pt tall, with no text fields (spec
/// §13.3).
public struct MenuBarPanelContent: View {
    var state: MenuBarPanelState
    var actions = MenuBarActions()
    /// Shown only while heatmap recording is on (spec §8.3).
    var typingStats: TypingStats?
    @AppStorage(SettingsKey.showsOverlay) private var showsOverlay = true

    static let width: CGFloat = 360
    /// Rows shown before the list of layers scrolls, which keeps the panel under 520 pt with 32 layers.
    static let visibleRows = 5
    static let rowHeight: CGFloat = 22

    /// A panel whose controls do nothing, for snapshots.
    public init(state: MenuBarPanelState, typingStats: TypingStats? = nil) {
        self.state = state
        self.typingStats = typingStats
    }

    init(state: MenuBarPanelState, actions: MenuBarActions, typingStats: TypingStats? = nil) {
        self.state = state
        self.actions = actions
        self.typingStats = typingStats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            keyboard
            if let typingStats { TypingStatsLine(stats: typingStats) }
            // The switch at the trailing edge, as in a menu; a bare Toggle puts it right after its label.
            HStack {
                // The switch carries the same words for VoiceOver.
                Text("Show overlay while holding a layer").accessibilityHidden(true)
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
        case .none: note("cable.connector") { Text("Connect your keyboard with a USB cable.") }
        case .flashMode:
            if let flash = state.flash, let progress = flash.progress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Writing \(flash.title) to the keyboard").font(.callout)
                    ProgressView(value: progress).progressViewStyle(.linear)
                        .accessibilityLabel(Text("Writing firmware, \(Int((progress * 100).rounded())) percent"))
                }
            } else {
                note("bolt.fill") { Text("The keyboard is in flash mode, ready for Build & Flash.") }
            }
        case .heldByAnotherApp:
            note("exclamationmark.triangle.fill") { Text(verbatim: DeviceError.heldByAnotherApp.localizedDescription) }
        case .liveOff:
            // The button under the note's text, which it acts on.
            note("dot.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Live View is off. Turn it on to see the keyboard’s layer and the keys you press, and to switch layers here."
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    Button("Turn On Live View", action: actions.turnOnLiveView).controlSize(.small)
                }
            }
        case .connecting, .live: MenuBarLayers(state: state, moveToLayer: actions.moveToLayer)
        }
    }

    private var buildAndFlashRow: some View {
        let title =
            if let flash = state.flash {
                flash.progress.map { String(localized: "Flashing… \(Int(($0 * 100).rounded()))%") }
                    ?? String(localized: "Waiting to flash \(flash.title)…")
            } else if let target = state.buildTarget {
                String(localized: "Build & Flash “\(target)”…")
            } else {
                String(localized: "Build & Flash…")
            }
        return MenuBarRow(title: title, shortcut: state.flash == nil ? "⌘R" : nil, action: actions.buildAndFlash)
            .keyboardShortcut("r")
            .disabled(!state.canBuildAndFlash)
    }

    private func note(_ symbol: String, @ViewBuilder text: () -> some View) -> some View {
        Label {
            text().fixedSize(horizontal: false, vertical: true)
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
                // A long layout name keeps both ends: "Build & Flash “My Ma…out”…".
                title.lineLimit(1).truncationMode(.middle)
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
