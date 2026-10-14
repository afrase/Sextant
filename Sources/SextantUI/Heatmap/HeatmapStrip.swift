import SextantApplication
import SextantDomain
import SwiftUI

/// The Heatmap lens's context strip (spec §3.7): each layer's share of the range's presses, or, with a key selected, that
/// key's presses on each layer. A card shows its layer.
struct HeatmapStrip: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let heat = model.heatmap.heatmap(for: session.id)
        let stats = HeatmapStats(heat, layout: session.layout)
        let key = session.selection.keyIndex
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(session.layout.layers.enumerated()), id: \.element.id) { index, layer in
                        card(index, layer, line: line(index, layer: layer, key: key, heat: heat, stats: stats))
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity)
            }
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo(session.currentLayer?.id, anchor: .center) }
        }
    }

    private func line(_ index: Int, layer: Layer, key: Int?, heat: KeyHeatmap, stats: HeatmapStats) -> String {
        if let key { return HeatCount.spoken(heat.count(layer: layer.id, index: key)) }
        guard let share = stats.layers[safe: index], share.presses > 0 else { return HeatCount.spoken(0) }
        let percent = share.share.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(percent) · \(HeatCount.spoken(share.presses))")
    }

    private func card(_ index: Int, _ layer: Layer, line: String) -> some View {
        Button {
            session.select(layer: index)
        } label: {
            HStack(spacing: 8) {
                LayerChip(color: layer.color, size: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(line).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 150, maxHeight: 60, alignment: .leading)
            .background(ContextStrip.card(dashed: false, current: index == session.selection.layer))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(index == session.selection.layer ? .isSelected : [])
    }
}

/// The Heatmap lens's capsule in the lens lane (spec §3.7, §8.5): "175,044 presses · 7 days · Main 87%", or why nothing
/// is being counted, with the way to start. It also reads the counts whenever the layout, the range or the store
/// changes, and asks before turning recording on or clearing.
struct HeatmapCapsule: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let heatmap = model.heatmap
        let heat = heatmap.heatmap(for: session.id)
        let stats = HeatmapStats(heat, layout: session.layout)
        HStack(spacing: 8) {
            Image(systemName: "flame").foregroundStyle(.secondary).accessibilityHidden(true)
            if stats.total > 0 {
                Text(summary(stats, range: heatmap.range)).monospacedDigit().lineLimit(1)
            }
            switch heatmap.status {
            case .off:
                if stats.total == 0 { Text("Heatmap recording is off").lineLimit(1) }
                Button("Turn On…") { heatmap.confirmsTurningOn = true }.buttonStyle(.borderless)
            case .waiting(.liveViewOff):
                Text("Paused: Live View is off").foregroundStyle(.secondary).lineLimit(1)
                Button("Turn On Live View") { model.isLive = true }.buttonStyle(.borderless).disabled(!model.canGoLive)
            case .waiting, .recording:
                if stats.total == 0 { Text("No presses recorded in this range yet").lineLimit(1) }
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
        .task(id: heatmap.loadKey(session.id)) { await heatmap.load(session.id) }
        .modifier(HeatmapConfirmations(heatmap: heatmap, session: session))
    }

    /// "175,044 presses · 7 days · Main 87%".
    private func summary(_ stats: HeatmapStats, range: HeatmapRange) -> String {
        let presses = HeatCount.spoken(stats.total)
        guard let top = stats.layers.max(by: { $0.share < $1.share }), let name = session.layout.layers[safe: top.layer]?.title else {
            return "\(presses) · \(range.phrase)"
        }
        return "\(presses) · \(range.phrase) · \(name) \(top.share.formatted(.percent.precision(.fractionLength(0))))"
    }
}

/// Turn On… and Clear Heatmap Data… ask first.
private struct HeatmapConfirmations: ViewModifier {
    @Bindable var heatmap: HeatmapModel
    var session: EditSession

    func body(content: Content) -> some View {
        content
            .alert(Text("Record a heatmap of key presses?"), isPresented: $heatmap.confirmsTurningOn) {
                Button("Turn On") { heatmap.turnOn() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(HeatmapNote.consent)
            }
            .alert(Text("Clear the heatmap of “\(session.layout.title)”?"), isPresented: $heatmap.confirmsClear) {
                Button("Clear", role: .destructive) { Task { await heatmap.clear(session.id) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes every key press counted for this layout. It can’t be undone.")
            }
    }
}

/// What recording keeps, in Sextant's words.
enum HeatmapNote {
    static var consent: String {
        String(
            localized: """
                Sextant counts presses per key position, by the hour, while Live View is on and the keyboard runs a layout \
                in your library. It never records the characters you type or the order of keys, and pauses while a password \
                field has focus. The counts stay on this Mac.
                """)
    }
}
