import SextantApplication
import SextantDomain
import SwiftUI

/// The sidebar's pinned device card (spec §3.6): the keyboard at a glance. A click opens the Device popover; a layout
/// that isn't in the library gets [Get Layout], which reads it from the keyboard (ADR 0061), and [Import] for an Oryx one.
public struct DeviceCard: View {
    var model: LayoutWindowModel
    @Environment(\.openWindow) private var openWindow
    @Environment(WindowRouter.self) private var windows: WindowRouter?

    public init(model: LayoutWindowModel) { self.model = model }

    public var body: some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    model.device.popover = .card
                } label: {
                    summary(live).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows the Device popover"))
                .devicePopover(model, from: .card, arrowEdge: .trailing)
                if let prompt = model.keyboardLayoutPrompt {
                    KeyboardLayoutPromptView(
                        prompt: prompt, isLive: model.isLive, getLayout: { model.getKeyboardLayout() },
                        addToLibrary: { openWindow.keyboardLayout(windows) }, importFromOryx: importFromOryx)
                } else if let serial = model.unknownOryxSerial {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Runs \(serial) · not in your library").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Import") { model.openImport(serial) }.controlSize(.small)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .padding(10)
        }
    }

    /// The Oryx [Import] beside the prompt, for an Oryx serial: Oryx's own build stores no layout to read.
    private var importFromOryx: (@MainActor () -> Void)? {
        guard let serial = model.connectedOryxSerial else { return nil }
        return { model.openImport(serial) }
    }

    private func summary(_ live: LiveSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(dot(live.connection)).frame(width: 7, height: 7)
                Text(verbatim: model.boardName).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let layer = live.activeLayer { LayerPips(layer: layer) }
            }
            Text(state(live.connection)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
                if let layer = live.activeLayer {
                    GridRow {
                        label("Layer")
                        HStack(spacing: 5) {
                            if model.runsThisLayout { LayerChip(color: model.session?.layout.layers[safe: layer]?.color, size: 8) }
                            Text(model.liveLayerTitle(layer)).lineLimit(1)
                        }
                    }
                }
                if let serial = live.firmwareSerial {
                    GridRow {
                        label("Layout")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: serial).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                            if let match = model.firmwareMatch { MatchLabel(match: match) }
                        }
                    }
                }
                if let version = live.protocolVersion {
                    GridRow {
                        label("Firmware")
                        Text("protocol \(version)").monospacedDigit()
                    }
                }
            }
            .font(.caption)
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private func dot(_ connection: LiveSession.Connection) -> Color {
        switch connection {
        case .noKeyboard: .secondary
        case .bootloader: Tokens.warning.color
        case .connected, .heldByAnotherApp, .liveOff: Tokens.success.color
        }
    }

    private func state(_ connection: LiveSession.Connection) -> String {
        switch connection {
        case .noKeyboard: String(localized: "No keyboard · Connect it with a USB cable")
        case .connected: String(localized: "Connected · USB")
        case .bootloader: String(localized: "Flash mode (bootloader)")
        case .heldByAnotherApp: String(localized: "In use by Keymapp")
        case .liveOff: String(localized: "Connected")
        }
    }
}
