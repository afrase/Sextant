import SextantApplication
import SextantDomain
import SwiftUI

/// Several selected keys (spec §5.4, ADR 0047): "3 keys", the slot editor and the common actions. Each change goes to
/// every selected key as one undo step ("Make 3 Keys Transparent"), through EditSession's selection-wide edits.
struct MultiKeyInspector: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let layer = session.selection.layer
        let indices = session.selection.keyIndices
        let keys = indices.compactMap { session.layout.key(layer: layer, index: $0) }
        let slot = session.selection.slot
        let actions = Set(keys.map { $0[slot].filledAction })
        VStack(alignment: .leading, spacing: 12) {
            header(indices, layer: layer)
            MultiSlotStrip(session: session, keys: keys)
            if actions.count == 1, let action = actions.first {
                SlotEditor(model: model, session: session, slot: slot, action: action, layer: layer)
            } else {
                mixed(slot, count: actions.count)
            }
            Divider()
            Text("Keys").font(.headline)
            colorRow(keys)
            Divider()
            HStack {
                Button {
                    session.makeTransparent()
                } label: {
                    Text("Make Transparent").frame(maxWidth: .infinity)
                }
                .disabled(keys.allSatisfy(\.isTransparent))
                .help(Text("Make Transparent (⌘⌫)"))
                Button {
                    session.disable()
                } label: {
                    Text("Disable").frame(maxWidth: .infinity)
                }
                .disabled(keys.allSatisfy { $0.kind == .disabled })
                .help(Text("Disable Key (⇧⌘⌫)"))
            }
            HStack {
                Menu("Copy To Layer") { CopyKeysMenu(session: session) }
                    .disabled(session.layout.layers.count < 2)
                    .help(Text("Puts these keys in the same places on another layer."))
                Button("Clear Label") { session.setLabel(nil) }
                    .disabled(keys.allSatisfy { $0.customLabel == nil })
            }
        }
        .labeledContentStyle(InspectorRowStyle())
    }

    /// The selected caps, how many, and the layer (spec §5.4: "3 keys").
    private func header(_ indices: [Int], layer: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                // Up to three caps, fanned: enough to read as several without crowding the title.
                ForEach(Array(indices.prefix(3).enumerated().reversed()), id: \.element) { n, index in
                    KeyCap(model: KeyCapModel(layout: session.layout, layer: layer, index: index), u: 40)
                        .frame(width: 40, height: 40)
                        .offset(x: CGFloat(n) * 6, y: CGFloat(n) * 6)
                }
            }
            .frame(width: 52, height: 52, alignment: .topLeading)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(indices.count) keys").font(.title3.weight(.semibold))
                HStack(spacing: 4) {
                    LayerChip(color: session.currentLayer?.color, size: 8)
                    Text(verbatim: session.currentLayer?.title ?? "")
                }
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
                Text(verbatim: KeyText.keyList(indices))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The slot holds different things on different keys: a new keycode or Clear sets them all alike.
    private func mixed(_ slot: KeySlot, count: Int) -> some View {
        LabeledContent("Keycode") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mixed: \(count) different").foregroundStyle(.secondary)
                HStack {
                    Button("Change…") { model.openKeycodePicker() }
                    Button("Clear") { session.setAction(nil, slot: slot) }
                }
            }
        }
    }

    /// The keys' own LED color: one swatch when they share it.
    private func colorRow(_ keys: [Key]) -> some View {
        let colors = Set(keys.map(\.glowColor))
        let shared = colors.count == 1 ? colors.first.flatMap(\.self) : nil
        return LabeledContent("LED color") {
            Menu {
                KeyColourMenu(window: model)
            } label: {
                if let shared {
                    Label {
                        Text(verbatim: shared.hex)
                    } icon: {
                        shared.swatchImage
                    }
                } else {
                    Text(colors.count == 1 ? String(localized: "None") : String(localized: "Mixed"))
                }
            }
            .fixedSize()
        }
    }
}

/// The four slot tabs for several keys: each shows what the keys hold there when they agree, else "Mixed".
private struct MultiSlotStrip: View {
    var session: EditSession
    var keys: [Key]

    /// What VoiceOver hears for a slot the keys don't share.
    static func unshared(mixed: Bool) -> String { mixed ? String(localized: "mixed") : String(localized: "empty") }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(KeySlot.allCases) { slot in
                let actions = Set(keys.map { $0[slot].filledAction })
                let shared = actions.count == 1 ? actions.first.flatMap(\.self) : nil
                let legend = shared.map { Legends.legend(for: $0, layerNames: session.layout.layerNames) }
                let selected = session.selection.slot == slot
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                Button {
                    session.select(key: session.selection.keyIndex, slot: slot)
                } label: {
                    VStack(spacing: 4) {
                        Text(slot.title)
                            .font(.caption)
                            .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        if let legend {
                            Text(verbatim: legend.layerName ?? CapLegendView.capText(for: legend))
                                .font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        } else if actions.count > 1 {
                            Text("Mixed").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Image(systemName: "plus").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(shape.fill(.quaternary.opacity(0.5)))
                    .overlay { if selected { shape.strokeBorder(Color.accentColor, lineWidth: 1.5) } }
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(slot.title): \(legend?.name ?? Self.unshared(mixed: actions.count > 1))"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityLabel(Text("Slots"))
    }
}

extension KeyText {
    /// "Keys 12, 19 and 24", or the first few and a count: "Keys 1, 2, 3 and 5 more".
    static func keyList(_ indices: [Int]) -> String {
        let shown = indices.prefix(indices.count > 6 ? 4 : 6).map(String.init)
        let rest = indices.count - shown.count
        let head = shown.dropLast(rest > 0 ? 0 : 1).joined(separator: ", ")
        if rest > 0 { return String(localized: "Keys \(head) and \(rest) more") }
        return String(localized: "Keys \(head) and \(shown.last ?? "")")
    }
}
