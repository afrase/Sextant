import SextantDomain
import SwiftUI

/// The panel's "Layer on the keyboard" (spec §8.3): a tile per layer up to four, otherwise rows with their global
/// shortcuts, then the mini map of the keyboard's layer with the keys held down. Choosing a layer moves the keyboard there
/// through Move Keyboard to Layer (ADR 0048); while it can't, the items are disabled under the reason.
struct MenuBarLayers: View {
    var state: MenuBarPanelState
    var moveToLayer: @MainActor (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Layer on the keyboard").font(.subheadline.weight(.semibold))
                Spacer()
                if let detail = state.layerDetail {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Group {
                if state.usesTiles {
                    HStack(spacing: 6) {
                        ForEach(state.layers) { tile($0) }
                        // Layer 0 alone (a layout Sextant doesn't have) takes half the width, not all of it.
                        if state.layers.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                    }
                } else {
                    // Opens on the keyboard's layer, which may be past the rows that fit: two rows above it at the top,
                    // so the cut falls through the half row at an edge, never through the row it's on.
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) { ForEach(state.layers) { row($0).id($0.index) } }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        // Overlay scrollers stay hidden until a scroll: show them once, beside the half row.
                        .scrollIndicatorsFlash(onAppear: true)
                        .onAppear { if let layer = state.layer { proxy.scrollTo(max(layer - 2, 0), anchor: .top) } }
                        .onChange(of: state.layer) { _, layer in if let layer { proxy.scrollTo(max(layer - 2, 0), anchor: .top) } }
                    }
                    .frame(height: listHeight)
                    .padding(.horizontal, -6)
                }
            }
            .disabled(!state.canMove)
            Text(verbatim: state.layerNote ?? String(localized: "Switching here moves the keyboard to that layer."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let layout = state.layout, let layer = state.layer {
                LayerMap(layout: layout, layer: layer, pressed: state.isSecureInputOn ? [] : state.pressed)
                    .frame(maxWidth: .infinity).frame(height: 100)
                if state.isSecureInputOn {
                    Label("Paused: secure input is on", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Every row up to ``MenuBarPanelContent/visibleRows``, one fewer under the App Layers row. A longer list is cut
    /// through a row, half a row short, so it reads as one that scrolls; half a row more would take the panel past 520 pt.
    private var listHeight: CGFloat {
        let count = state.layers.count, visible = MenuBarPanelContent.visibleRows - (state.appLayers == nil ? 0 : 1)
        return (count > visible ? CGFloat(visible) - 0.5 : CGFloat(count)) * MenuBarPanelContent.rowHeight
    }

    private func isActive(_ item: MenuBarPanelState.LayerItem) -> Bool { state.layer == item.index }

    private func tile(_ item: MenuBarPanelState.LayerItem) -> some View {
        let tone = item.color.map { LayerTones($0).display.color } ?? Color.accentColor
        let active = isActive(item)
        return Button {
            moveToLayer(item.index)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    LayerChip(color: item.color, size: 9)
                    Spacer(minLength: 0)
                    Text(verbatim: "L\(item.index)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(verbatim: item.title).font(.callout.weight(active ? .semibold : .regular)).lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? tone.opacity(0.22) : Color.primary.opacity(0.05))
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(active ? tone : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(item.title), layer \(item.index)"))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func row(_ item: MenuBarPanelState.LayerItem) -> some View {
        MenuBarRow(shortcut: item.shortcut, action: { moveToLayer(item.index) }) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.caption.weight(.semibold)).opacity(isActive(item) ? 1 : 0)
                LayerChip(color: item.color, size: 9)
                Text(verbatim: "L\(item.index)").font(.caption.monospacedDigit()).opacity(0.7).frame(width: 22, alignment: .leading)
                Text(verbatim: item.title).lineLimit(1)
            }
        }
        .accessibilityLabel(Text("\(item.title), layer \(item.index)"))
        .accessibilityAddTraits(isActive(item) ? .isSelected : [])
    }
}
