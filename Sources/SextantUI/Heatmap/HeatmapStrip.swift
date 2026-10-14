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

/// The Heatmap lens's capsule in the lens lane (spec §3.7, §8.5): "175,044 presses · 7 days · Main 87%", and why nothing
/// is being counted, with the way to start. It also reads the counts whenever the layout, the range or the store
/// changes, and asks before turning recording on or clearing.
struct HeatmapCapsule: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let heatmap = model.heatmap
        let heat = heatmap.heatmap(for: session.id)
        let stats = HeatmapStats(heat, layout: session.layout)
        let status = heatmap.status
        HStack(spacing: 8) {
            Image(systemName: "flame").foregroundStyle(.secondary).accessibilityHidden(true)
            if stats.total > 0 {
                // Beside the live capsule at the smallest window, the summary sheds the range, then the busiest layer.
                ViewThatFits(in: .horizontal) {
                    ForEach(summaries(stats, range: heatmap.range), id: \.self) { Text($0).monospacedDigit().lineLimit(1) }
                }
                // With counts to show, only a word for why none are being added; the whole reason is in the help tag.
                switch status {
                case .off, .waiting:
                    let reason = status.text(recordsThisLayout: nil)
                    Text(status == .off ? "Off" : "Paused").foregroundStyle(.secondary).lineLimit(1).help(reason)
                        .accessibilityLabel(reason)
                case .recording: EmptyView()
                }
            } else {
                switch status {
                case .off: Text("Heatmap recording is off").lineLimit(1)
                case .waiting: Text(status.text(recordsThisLayout: nil)).foregroundStyle(.secondary).lineLimit(1)
                case .recording: Text("No presses recorded in this range yet").lineLimit(1)
                }
            }
            switch status {
            case .off: Button("Turn On…") { heatmap.confirmsTurningOn = true }.buttonStyle(.borderless)
            case .waiting(.liveViewOff):
                Button("Turn On Live View") { model.isLive = true }.buttonStyle(.borderless).disabled(!model.canGoLive)
            case .waiting, .recording: EmptyView()
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
        // The live capsule beside it says what a press does now; this one gives way first.
        .layoutPriority(-1)
        .task(id: heatmap.loadKey(session.id)) { await heatmap.load(session.id) }
        .modifier(HeatmapConfirmations(heatmap: heatmap, session: session))
    }

    /// "175,044 presses · 7 days · Main 87%", then shorter ones for a narrow lane.
    private func summaries(_ stats: HeatmapStats, range: HeatmapRange) -> [String] {
        let presses = HeatCount.spoken(stats.total)
        guard let top = stats.layers.max(by: { $0.share < $1.share }), let name = session.layout.layers[safe: top.layer]?.title else {
            return ["\(presses) · \(range.phrase)", presses]
        }
        let share = "\(name) \(top.share.formatted(.percent.precision(.fractionLength(0))))"
        return ["\(presses) · \(range.phrase) · \(share)", "\(presses) · \(share)", presses]
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
