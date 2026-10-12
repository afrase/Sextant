import SextantApplication
import SextantDomain
import SwiftUI

/// Whether the bench draws its precision grid (View ▸ Show Grid Behind Keyboard; spec §4.10).
enum BenchGrid {
    static let key = "showsBenchGrid"
}

/// The centre column's fixed bands (spec §3.3). Only the board area flexes, so the board never moves when the
/// selection, lens, lane or strip change.
struct CanvasColumn: View {
    var model: LayoutWindowModel
    var session: EditSession
    @AppStorage(BenchGrid.key) private var showsGrid = true

    var body: some View {
        VStack(spacing: 0) {
            CanvasHeader(model: model, session: session).frame(height: 44)
            LensLane(model: model).frame(height: 36)
            if model.page == .history {
                ChangesBoard(model: model, showsGrid: showsGrid)
            } else {
                BoardView(
                    session: session, mode: model.legendMode, issues: model.issueMap, pressed: model.pressedKeys,
                    highlightedKind: model.highlightedKind, showsGrid: showsGrid
                )
                .environment(\.swapsKeys, model.lens == .keys)
            }
            ContextStrip(model: model, session: session).frame(height: 76)
            BoardFooter(model: model).frame(height: 32)
        }
        .background {
            ZStack {
                Bench().ignoresSafeArea(edges: .top)
                // AppKit puts an opaque white "hard" pocket with a hairline under the toolbar of a split column that
                // has no scroll view; an empty one turns it into the soft pocket, which shows the bench through.
                ScrollView {}.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

/// Layer jump menu and readout (leading), lens control, or History's comparison (trailing).
private struct CanvasHeader: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        @Bindable var model = model
        // History shows a revision's layers, which needn't be the document's.
        let history = model.page == .history ? model.history : nil
        let display = history?.display
        let (layout, shown) = display.map { ($0.layout, $0.layer) } ?? (session.layout, session.selection.layer)
        let current = layout.layers[safe: shown]
        HStack(spacing: 12) {
            Menu {
                ForEach(Array(layout.layers.enumerated()), id: \.element.id) { index, layer in
                    Toggle(
                        String(localized: "\(index) · \(layer.title)"),
                        isOn: Binding(
                            get: { shown == index },
                            set: { _ in if let history { history.show(layer: index, of: layout) } else { session.select(layer: index) } }))
                }
            } label: {
                HStack(spacing: 6) {
                    LayerChip(color: current?.color, size: 10)
                    Text(current?.title ?? "").fontWeight(.medium)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel(String(localized: "Layer: \(current?.title ?? "")"))
            Text(display.map { KeyText.readout(layout: $0.layout, layer: $0.layer, isFollowing: false) } ?? model.readout)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if model.page == .history, let history = model.history {
                CompareMenu(history: history)
            } else {
                Picker("Lens", selection: $model.lens) {
                    ForEach(Lens.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.horizontal, 20)
    }
}
