import SextantApplication
import SextantDomain
import SwiftUI

/// The Heatmap lens's inspector (spec §3.8, §8.5): the range, whether presses are being counted, the totals, layer
/// share, hand balance, a finger histogram, the busiest keys and the layers reached, then Export and Clear.
struct HeatmapInspector: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        @Bindable var heatmap = model.heatmap
        let heat = heatmap.heatmap(for: session.id)
        let stats = HeatmapStats(heat, layout: session.layout)
        Text("Heatmap").font(.title3.weight(.semibold))
        Picker("Range", selection: $heatmap.range) {
            ForEach(HeatmapRange.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        status
        if stats.total == 0 {
            empty
        } else {
            HeatmapStatsView(session: session, stats: stats)
        }
        Divider()
        HStack(spacing: 8) {
            Button("Export CSV…") { model.exportHeatmap(json: false) }
            Button("Export JSON…") { model.exportHeatmap(json: true) }
        }
        .disabled(stats.total == 0 || model.exports.pending?.file != nil)
        Button("Clear Heatmap Data…") { heatmap.confirmsClear = true }.disabled(heatmap.recorder == nil)
        Text("Counted on this Mac only. Nothing is uploaded.").font(.callout).foregroundStyle(.secondary)
    }

    /// Recording's state: counting, or why not, with the way to start when it is off or Live View is, and a failed
    /// save or read.
    @ViewBuilder private var status: some View {
        let status = model.heatmap.status
        let isRecording = status == .recording(session.id)
        HStack(spacing: 6) {
            Circle().fill(isRecording ? Tokens.danger.color : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(status.text(recordsThisLayout: isRecording)).font(.callout).foregroundStyle(isRecording ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        switch status {
        case .off: Button("Turn On…") { model.heatmap.confirmsTurningOn = true }.controlSize(.small)
        case .waiting(.liveViewOff):
            Button("Turn On Live View") { model.isLive = true }.controlSize(.small).disabled(!model.canGoLive)
        case .waiting, .recording: EmptyView()
        }
        if let error = model.heatmap.error {
            Label {
                Text(error).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.danger.color)
            }
            .font(.callout)
        }
    }

    @ViewBuilder private var empty: some View {
        if model.heatmap.isOn {
            Text("No presses recorded in this range yet.").foregroundStyle(.secondary)
        } else {
            Text("Sextant can count key presses on this Mac to show which keys you use most.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The range's statistics, once there are presses to show.
private struct HeatmapStatsView: View {
    var session: EditSession
    var stats: HeatmapStats

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stats.total.formatted()).font(.title2.weight(.semibold)).monospacedDigit()
            Text(stats.total == 1 ? "press" : "presses").font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        Divider()
        Text("Layers").font(.headline)
        ShareBar(parts: stats.layers.map { ($0.share, LayerChip.fill(session.layout.layers[safe: $0.layer]?.color)) })
        ForEach(stats.layers, id: \.layer) { share in
            let layer = session.layout.layers[safe: share.layer]
            HStack(spacing: 6) {
                LayerChip(color: layer?.color, size: 10)
                Text(layer?.title ?? "").lineLimit(1)
                Spacer()
                Text(share.share.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                Text(share.presses.formatted()).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 56, alignment: .trailing)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }
        Divider()
        Text("Hands").font(.headline)
        HandsBar(left: stats.left, right: stats.right)
        Divider()
        Text("Fingers").font(.headline)
        FingerHistogram(fingers: stats.fingers)
        Divider()
        Text("Busiest keys").font(.headline)
        ForEach(stats.top, id: \.self) { key in busiest(key) }
        if !stats.reached.isEmpty {
            Divider()
            Text("Layers reached").font(.headline)
            ForEach(stats.reached, id: \.layer) { reach in
                let layer = session.layout.layers[safe: reach.layer]
                HStack(spacing: 6) {
                    LayerChip(color: layer?.color, size: 10)
                    Text(layer?.title ?? "").lineLimit(1)
                    Spacer()
                    Text(reach.times == 1 ? String(localized: "1 time") : String(localized: "\(reach.times.formatted()) times"))
                        .monospacedDigit()
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// One of the busiest keys: its cap on its layer, which a click shows and selects.
    private func busiest(_ key: HeatmapStats.KeyCount) -> some View {
        let resolved = Legends.legend(layout: session.layout, layer: key.layer, index: key.index)
        let line = KeyText.stripLine(resolved)
        let layer = session.layout.layers[safe: key.layer]?.title ?? ""
        return Button {
            session.select(layer: key.layer)
            session.select(key: key.index)
        } label: {
            HStack(spacing: 8) {
                KeyCap(model: KeyCapModel(layout: session.layout, layer: key.layer, index: key.index), u: 26).frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(line.text).lineLimit(1)
                    Text(layer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(key.presses.formatted()).monospacedDigit()
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(line.spoken) on \(layer)"))
        .accessibilityValue(Text(HeatCount.spoken(key.presses)))
        .accessibilityHint(Text("Shows the key"))
    }
}

/// Shares as one bar of segments, each in its colour.
private struct ShareBar: View {
    var parts: [(share: Double, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.share > 0 { Rectangle().fill(part.color).frame(width: max(1, (proxy.size.width - 1) * part.share)) }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Tokens.capUnlit.color)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// Left and right as one bar, each side's share at its end.
private struct HandsBar: View {
    var left: Int
    var right: Int

    var body: some View {
        let total = max(left + right, 1)
        let share = (left: Double(left) / Double(total), right: Double(right) / Double(total))
        let format = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0))
        VStack(spacing: 4) {
            ShareBar(parts: [(share.left, Tokens.heat(0.85).color), (share.right, Tokens.heat(0.5).color)])
            HStack {
                Text("Left \(share.left.formatted(format))")
                Spacer()
                Text("Right \(share.right.formatted(format))")
            }
            .font(.callout)
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hands"))
        .accessibilityValue(Text("Left \(share.left.formatted(format)), right \(share.right.formatted(format))"))
    }
}

/// Presses per finger, the left hand's pinky to thumb and the right's thumb to pinky, as the hands lie on the board.
private struct FingerHistogram: View {
    var fingers: [HeatmapStats.FingerCount]

    var body: some View {
        let most = max(fingers.map(\.presses).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(fingers.enumerated()), id: \.offset) { index, finger in
                if index == fingers.count / 2 { Divider().frame(height: 52) }
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Tokens.heat(0.15 + 0.85 * Double(finger.presses) / Double(most)).color)
                        .frame(height: max(2, 44 * CGFloat(finger.presses) / CGFloat(most)))
                    Text(Self.initial(finger.finger)).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Self.name(finger)))
                .accessibilityValue(Text(HeatCount.spoken(finger.presses)))
            }
        }
        .frame(height: 64, alignment: .bottom)
    }

    static func initial(_ finger: BoardDefinition.Finger) -> String {
        switch finger {
        case .pinky: String(localized: "P", comment: "Pinky, under its bar in the finger histogram")
        case .ring: String(localized: "R", comment: "Ring finger, under its bar in the finger histogram")
        case .middle: String(localized: "M", comment: "Middle finger, under its bar in the finger histogram")
        case .index: String(localized: "I", comment: "Index finger, under its bar in the finger histogram")
        case .thumb: String(localized: "T", comment: "Thumb, under its bar in the finger histogram")
        }
    }

    static func name(_ count: HeatmapStats.FingerCount) -> String {
        switch (count.hand, count.finger) {
        case (.left, .pinky): String(localized: "Left pinky")
        case (.left, .ring): String(localized: "Left ring finger")
        case (.left, .middle): String(localized: "Left middle finger")
        case (.left, .index): String(localized: "Left index finger")
        case (.left, .thumb): String(localized: "Left thumb")
        case (.right, .pinky): String(localized: "Right pinky")
        case (.right, .ring): String(localized: "Right ring finger")
        case (.right, .middle): String(localized: "Right middle finger")
        case (.right, .index): String(localized: "Right index finger")
        case (.right, .thumb): String(localized: "Right thumb")
        }
    }
}

extension LayerChip {
    /// The chip's fill for a layer colour, for bars drawn in layer colours.
    static func fill(_ color: HexColor?) -> Color { color.map { LayerTones($0).display.color } ?? Tokens.neutralChip.color }
}
