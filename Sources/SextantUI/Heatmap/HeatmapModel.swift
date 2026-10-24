import AppKit
import Observation
import SextantApplication
import SextantDomain
import SwiftUI
import UniformTypeIdentifiers

/// One window's Heatmap lens (spec §8.5): its range, the open layout's counts as last read, and the confirmations it
/// asks for. The counts come from the app-wide ``HeatmapRecorder``: what it had stored when they were read, plus what it
/// has counted since, so the board's heat follows typing between writes.
@MainActor
@Observable
public final class HeatmapModel {
    /// What a load read: the layout, the range's first hour, and the stored counts then.
    struct Loaded {
        var layoutID: UUID
        var start: Date?
        var snapshot: HeatmapRecorder.Snapshot
    }

    /// The app-wide recorder; nil in tests and snapshots without one.
    @ObservationIgnored let recorder: HeatmapRecorder?
    var range: HeatmapRange = .week
    private(set) var loaded: Loaded?
    /// Recording's status where there is no recorder (snapshots).
    private var fixedStatus = HeatmapRecorder.Status.off
    /// Turn On… is asking first.
    var confirmsTurningOn = false
    /// Clear Heatmap Data… is asking first.
    var confirmsClear = false
    /// The counts with what was counted since they were read, cached for the board's 52 caps by the recorder's changes.
    @ObservationIgnored private var combined: (key: [Int], heatmap: KeyHeatmap)?

    public init(recorder: HeatmapRecorder? = nil) { self.recorder = recorder }

    var status: HeatmapRecorder.Status { recorder?.status ?? fixedStatus }
    var isOn: Bool { status != .off }
    /// Why the counts couldn't be saved or read, while that lasts.
    var error: String? { recorder?.lastError?.errorDescription }

    /// Shows fixed counts and a fixed status, with no recorder (snapshots).
    public func show(_ hours: [HeatmapHour], of layoutID: UUID, range: HeatmapRange, status: HeatmapRecorder.Status) {
        self.range = range
        fixedStatus = status
        let snapshot = HeatmapRecorder.Snapshot(heatmap: KeyHeatmap(hours), version: 0)
        loaded = Loaded(layoutID: layoutID, start: range.start(now: Date()), snapshot: snapshot)
        combined = nil
    }

    /// What a load depends on: the layout, the range and its first hour, and the store's contents.
    struct LoadKey: Equatable {
        var layoutID: UUID
        var range: HeatmapRange
        var start: Date?
        var version: Int
    }

    func loadKey(_ layoutID: UUID) -> LoadKey {
        LoadKey(layoutID: layoutID, range: range, start: recorder.flatMap { range.start(now: $0.hour) }, version: recorder?.version ?? 0)
    }

    /// Reads the layout's stored counts for the range, which slides with the recorder's hour.
    func load(_ layoutID: UUID) async {
        guard let recorder else { return }
        let range = range
        let start = range.start(now: recorder.hour)
        let snapshot = await recorder.snapshot(of: layoutID, from: start)
        guard range == self.range else { return }
        loaded = Loaded(layoutID: layoutID, start: start, snapshot: snapshot)
        combined = nil
    }

    /// The layout's counts over the range, including those not yet written; empty until a load for that layout. A new
    /// range shows the last one's until it is read.
    func heatmap(for layoutID: UUID) -> KeyHeatmap {
        guard let loaded, loaded.layoutID == layoutID else { return KeyHeatmap() }
        guard let recorder else { return loaded.snapshot.heatmap }
        let key = [recorder.changes, recorder.version, loaded.snapshot.version]
        if let combined, combined.key == key { return combined.heatmap }
        var heatmap = loaded.snapshot.heatmap
        for hour in recorder.unwritten(of: layoutID, from: loaded.start, after: loaded.snapshot.version) { heatmap.add(hour) }
        combined = (key, heatmap)
        return heatmap
    }

    func turnOn() { recorder?.isOn = true }

    func clear(_ layoutID: UUID) async {
        await recorder?.clear(layoutID)
    }
}

extension HeatmapRange {
    /// The inspector's range picker.
    var title: String {
        switch self {
        case .day: String(localized: "24 h")
        case .week: String(localized: "7 days")
        case .month: String(localized: "30 days")
        case .all: String(localized: "All")
        }
    }

    /// The range in the lens lane's summary: "7 days".
    var phrase: String {
        switch self {
        case .day: String(localized: "24 hours")
        case .week: String(localized: "7 days")
        case .month: String(localized: "30 days")
        case .all: String(localized: "all time")
        }
    }
}

extension HeatmapRecorder.Status {
    /// Why nothing is being counted, or what is: Sextant's words for the inspector and the menu bar.
    func text(recordsThisLayout: Bool?) -> String {
        switch self {
        case .off: String(localized: "Recording is off")
        case .recording:
            switch recordsThisLayout {
            case false?: String(localized: "Recording the layout on the keyboard, not this one")
            default: String(localized: "Recording key presses")
            }
        case let .waiting(pause):
            switch pause {
            case .noKeyboard: String(localized: "Paused: no keyboard connected")
            case .flashMode: String(localized: "Paused: the keyboard is in flash mode")
            case .liveViewOff: String(localized: "Paused: Live View is off")
            case .heldByAnotherApp: String(localized: "Paused: Keymapp is using the keyboard")
            case .otherLayout: String(localized: "Paused: the keyboard runs a layout that isn’t in your library")
            case .secureInput: String(localized: "Paused while you type in a password field")
            }
        }
    }
}

extension LayoutWindowModel {
    /// A cap's heat on the Heatmap lens (spec §8.5): the ramp's colour on a log scale against the layer's busiest key, and
    /// the count under the legend. Plain caps on a layer with no presses in the range.
    func heatDecoration(layer: Int, index: Int) -> CapDecoration {
        guard let session, let id = session.layout.layers[safe: layer]?.id else { return CapDecoration() }
        let heat = heatmap.heatmap(for: session.id)
        guard heat.total(layer: id) > 0 else { return CapDecoration() }
        let count = heat.count(layer: id, index: index)
        var decoration = CapDecoration()
        decoration.fill = Tokens.heat(heat.intensity(layer: id, index: index))
        decoration.count = CapDecoration.Count(text: HeatCount.compact(count), accessibilityText: HeatCount.spoken(count))
        return decoration
    }

    /// Export CSV… and Export JSON…: the range's counts through File ▸ Export's save panel.
    func exportHeatmap(json: Bool) {
        guard let session, exports.pending?.file == nil else { return }
        guard NSApp?.mainWindow?.attachedSheet == nil else { return NSSound.beep() }
        let heat = heatmap.heatmap(for: session.id)
        let name = String(localized: "\(LayoutExport.filename(session.layout.title)) Heatmap")
        if json {
            let start = heatmap.loaded?.start
            guard let data = try? HeatmapExport.json(heat, layout: session.layout, from: start, to: Date()) else {
                return exports.pending = .failed(String(localized: "The heatmap couldn’t be written as JSON."))
            }
            exports.pending = .saving(ExportFile(data: data, contentType: .json, filename: name))
        } else {
            let csv = HeatmapExport.csv(heat, layout: session.layout)
            exports.pending = .saving(ExportFile(data: Data(csv.utf8), contentType: .commaSeparatedText, filename: name))
        }
    }
}

/// Press counts as the caps and VoiceOver say them.
enum HeatCount {
    /// "312", "1.2k", "22k", "1.4M": short enough for a cap.
    static func compact(_ count: Int) -> String {
        let decimals = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        switch count {
        case ..<1000: return "\(count)"
        case ..<10_000: return "\((Double(count) / 1000).formatted(decimals))k"
        case ..<1_000_000: return "\(count / 1000)k"
        default: return "\((Double(count) / 1_000_000).formatted(decimals))M"
        }
    }

    /// "No presses", "1 press", "22,044 presses".
    static func spoken(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "No presses")
        case 1: String(localized: "1 press")
        default: String(localized: "\(count.formatted()) presses")
        }
    }
}
