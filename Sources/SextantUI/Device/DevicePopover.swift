import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

extension View {
    /// Hangs the window's Device popover off this view while `model.devicePopover` names `anchor`.
    func devicePopover(_ model: LayoutWindowModel, from anchor: DevicePopoverAnchor, arrowEdge: Edge = .bottom) -> some View {
        popover(
            isPresented: Binding(get: { model.devicePopover == anchor }, set: { if !$0 { model.devicePopover = nil } }),
            arrowEdge: arrowEdge
        ) { DevicePopover(model: model) }
    }
}

/// The Device popover (spec §8.2): identity, the live layer and keys, Follow, the raw-HID log when it is on, and how
/// live data stays private.
public struct DevicePopover: View {
    var model: LayoutWindowModel
    /// First connect shows a note about live data once (spec §12.3).
    @AppStorage(SettingsKey.seenLiveDataNote) private var seenLiveDataNote = false
    @AppStorage(SettingsKey.showsKeyPresses) private var showsPresses = true
    @AppStorage(SettingsKey.showsOverlay) private var showsOverlay = true
    @State private var showsTrace = true
    @Environment(RawHIDTrace.self) private var trace: RawHIDTrace?
    @Environment(WindowRouter.self) private var windows: WindowRouter?
    @Environment(\.openWindow) private var openWindow

    public init(model: LayoutWindowModel) { self.model = model }

    public var body: some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 14) {
                header(live)
                if let serial = live.firmwareSerial {
                    Divider()
                    identity(live, serial: serial)
                }
                if model.canGoLive || model.isLive {
                    Divider()
                    // Pairing writes to the keyboard, so it starts only from here, the toolbar, the Keyboard menu or the menu
                    // bar (ADR 0057).
                    Toggle(isOn: Binding(get: { model.isLive }, set: { model.isLive = $0 })) {
                        Text("Live View: the keyboard’s layer and the keys you press").fixedSize(horizontal: false, vertical: true)
                    }
                    if let onKeyboard = model.onKeyboard {
                        MoveKeyboardToLayerMenu(onKeyboard: onKeyboard, live: model.live).fixedSize()
                    }
                }
                if case .connected = live.connection {
                    liveSection(live)
                    Toggle(isOn: Binding(get: { model.isFollowing }, set: { model.isFollowing = $0 })) {
                        HStack {
                            Text("Follow the keyboard’s layer")
                            Spacer()
                            Text(verbatim: "⌘L").foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                    }
                    .disabled(!model.canFollow)
                    showToggles
                }
                if let trace, trace.isOn {
                    Divider()
                    traceLog(trace)
                }
                Divider()
                privacy(live)
            }
            .padding(16)
            .frame(width: 360)
        }
    }

    /// The keyboard's layout and firmware, and what Sextant offers when it doesn't have that layout (ADR 0061).
    private func identity(_ live: LiveSession, serial: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Identity") {
                row("Layout") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: serial).font(.callout.monospaced()).textSelection(.enabled)
                        if let match = model.firmwareMatch { MatchLabel(match: match, long: true) }
                    }
                }
                row("Firmware") { Text(firmware(live)).font(.callout.monospacedDigit()) }
            }
            if let prompt = model.keyboardLayoutPrompt { keyboardLayout(prompt) }
        }
    }

    /// What Sextant offers for a layout it doesn't have. The popover closes for the window or the sheet a button opens.
    private func keyboardLayout(_ prompt: KeyboardLayoutPrompt) -> some View {
        KeyboardLayoutPromptView(
            prompt: prompt, isLive: model.isLive, font: .callout, getLayout: { model.getKeyboardLayout() },
            addToLibrary: { addToLibrary() }, importFromOryx: importFromOryx)
    }

    private func addToLibrary() {
        model.devicePopover = nil
        openWindow.keyboardLayout(windows)
    }

    /// The Oryx [Import], for an Oryx serial: Oryx's own build stores no layout to read.
    private var importFromOryx: (@MainActor () -> Void)? {
        guard let serial = model.connectedOryxSerial else { return nil }
        return {
            model.devicePopover = nil
            model.openImport(serial)
        }
    }

    /// Where live presses show: the same settings as Settings › Keyboard's.
    @ViewBuilder private var showToggles: some View {
        Toggle("Show key presses on the board", isOn: $showsPresses)
        Toggle("Show overlay while a layer is held", isOn: $showsOverlay)
    }

    @ViewBuilder private func privacy(_ live: LiveSession) -> some View {
        // The heatmap, once the user turns it on, saves hourly counts (ADR 0053).
        let recordsHeatmap = model.heatmap.isOn
        let kept = PrivacySettings.title(model.heatmap.recorder?.retentionDays ?? PrivacySettings.heatmapRetentionDays())
        if !seenLiveDataNote, case .connected = live.connection {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    recordsHeatmap
                        ? """
                        Sextant shows the keyboard’s layer and the keys you hold as they happen. The heatmap saves \
                        counts of presses per key and of layer changes, by the hour, and keeps them for \(kept).
                        """
                        : "Sextant shows the keyboard’s layer and the keys you hold as they happen. Nothing is recorded."
                )
                .fixedSize(horizontal: false, vertical: true)
                Button("OK") { seenLiveDataNote = true }.controlSize(.small)
            }
            .font(.callout)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.1)))
        }
        Text(
            recordsHeatmap
                ? """
                Key events stay in memory on this Mac. Heatmap counts are kept for \(kept) (Settings › Privacy). \
                Live display and the heatmap pause while you type in a password field.
                """
                : """
                Key events stay in memory on this Mac and are never written to disk. \
                Live display pauses while you type in a password field.
                """
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The Developer raw-HID log (Settings › Advanced), newest last. It also serves as the spec's event monitor.
    private func traceLog(_ trace: RawHIDTrace) -> some View {
        DisclosureGroup(isExpanded: $showsTrace) {
            if trace.entries.isEmpty {
                Text("No reports yet.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let lines = trace.entries.map { $0.line(board: model.board) }
                // A report too long for one line wraps under its own bytes, so the time column stays clear.
                let rows = VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { n in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(verbatim: lines[n].head).fixedSize()
                            Text(verbatim: lines[n].report)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    // A short log takes its own height; a long one scrolls, opening on the newest report.
                    ViewThatFits(in: .vertical) {
                        rows
                        ScrollView { rows }.defaultScrollAnchor(.bottom)
                    }
                    .frame(maxHeight: 150)
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lines.map { $0.head + $0.report }.joined(separator: "\n"), forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        } label: {
            Text("Raw-HID log").font(.headline)
        }
    }

    private func header(_ live: LiveSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "keyboard").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.boardName).font(.headline)
                Text(state(live)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func state(_ live: LiveSession) -> String {
        switch live.connection {
        case .noKeyboard: String(localized: "Not connected. Connect your keyboard with a USB cable.")
        case .connected: String(localized: "Connected over USB")
        case .bootloader: String(localized: "In flash mode, ready for Build & Flash. Unplug it and plug it back in to leave flash mode.")
        case .heldByAnotherApp: DeviceError.heldByAnotherApp.localizedDescription
        case .liveOff:
            String(localized: "Connected over USB. Turn on Live View to see its layer and the keys you press.")
        }
    }

    private func firmware(_ live: LiveSession) -> String {
        let usb = model.connectedKeyboard.map { "USB " + String(format: "%04X:%04X", model.board.vendorID, $0.productID) }
        let proto = live.protocolVersion.map { String(localized: "protocol \($0)") }
        return [proto, usb].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func liveSection(_ live: LiveSession) -> some View {
        section("Live") {
            if let layer = live.activeLayer {
                row("Layer") {
                    HStack(spacing: 6) {
                        if model.runsThisLayout { LayerChip(color: model.session?.layout.layers[safe: layer]?.color, size: 10) }
                        Text(model.liveLayerText(layer)).font(.callout)
                    }
                }
                row("Lights") {
                    HStack(spacing: 8) {
                        LayerPips(layer: layer)
                        Text("= \(layer) in binary").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            row("Keys down") {
                if live.isSecureInputOn {
                    Label("Paused: secure input is on", systemImage: "eye.slash").font(.callout).foregroundStyle(.secondary)
                } else if live.pressedKeys.isEmpty {
                    Text("None").font(.callout).foregroundStyle(.secondary)
                } else {
                    // Positions only, never letters (spec §8.2).
                    Text(verbatim: live.pressedKeys.sorted().map { "k\($0)" }.joined(separator: "  ")).font(.callout.monospaced())
                }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) { rows() }
        }
    }

    private func row(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(label).font(.callout).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value()
        }
    }
}

/// ✓ matches, ↑ earlier version or ⚠ different layout (spec §3.6).
struct MatchLabel: View {
    var match: FirmwareMatch
    /// The popover's wording ("matches this layout") rather than the card's.
    var long = false

    var body: some View {
        let (symbol, text, tone): (String, String, Color) =
            switch match {
            case .current:
                (
                    "checkmark.circle.fill", long ? String(localized: "matches this layout") : String(localized: "matches"),
                    Tokens.success.color
                )
            case .thisLayout: ("arrow.up.circle", String(localized: "earlier version of this layout"), Tokens.warning.color)
            case .otherLayout: ("exclamationmark.triangle.fill", String(localized: "different layout"), Tokens.warning.color)
            }
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tone)
            Text(text).foregroundStyle(.secondary)
        }
        .font(long ? .callout : .caption)
        .accessibilityElement(children: .combine)
    }
}

/// The keyboard's four status lights, which show the active layer in binary, light 1 first.
struct LayerPips: View {
    var layer: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { bit in
                Circle()
                    .fill((layer >> bit) & 1 == 1 ? Tokens.success.color : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Status lights show layer \(layer)"))
    }
}

extension HIDTraceEntry {
    /// One log line in two columns, "21:04:31.207  ←  " and "06 02 08 FE  down k40 · R8 C2": positions only, as the
    /// protocol carries nothing else. The clock is 24-hour, so a log that runs past noon still reads in order.
    func line(board: BoardDefinition) -> (head: String, report: String) {
        let time = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).time(includingFractionalSeconds: true))
        var report = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let key: (word: String, row: Int, column: Int)? =
            switch event {
            case let .keyDown(row, column): (String(localized: "down"), row, column)
            case let .keyUp(row, column): (String(localized: "up"), row, column)
            default: nil
            }
        if let key {
            let index = board.keyIndex(matrixRow: key.row, column: key.column).map { "k\($0) · " } ?? ""
            report += "  \(key.word) \(index)R\(key.row) C\(key.column)"
        }
        return ("\(time)  \(direction == .sent ? "→" : "←")  ", report)
    }
}

extension LayoutWindowModel {
    var board: BoardDefinition { session?.layout.board ?? .voyager }
    var boardName: String { board.displayName }

    /// The keyboard's layer by this layout's name when the keyboard runs this layout; by number otherwise, since
    /// another layout's layers have other names.
    func liveLayerTitle(_ layer: Int) -> String {
        (runsThisLayout ? session?.layout.layers[safe: layer]?.title : nil) ?? layer.formatted()
    }

    /// The popover's longer form: "Brd+Sys · layer 2 · held by Space (key 51)".
    func liveLayerText(_ layer: Int) -> String {
        guard let layout = session?.layout, runsThisLayout, let title = layout.layers[safe: layer]?.title else { return layer.formatted() }
        let held = layer == 0 ? nil : KeyText.activator(layout: layout, layer: layer)?.text
        return ([title, String(localized: "layer \(layer)")] + [held].compactMap { $0 }).joined(separator: " · ")
    }

    /// The keyboard runs a build of the open layout, so its layer numbers mean this layout's layers.
    var runsThisLayout: Bool {
        switch firmwareMatch {
        case .current, .thisLayout: true
        default: false
        }
    }
}
