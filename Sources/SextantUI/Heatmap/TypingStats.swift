import SextantApplication
import SwiftUI

/// The menu bar panel's typing line (spec §8.3): today's presses and words per minute, shown only while heatmap
/// recording is on. A value, so snapshots draw it without a keyboard.
public struct TypingStats: Equatable, Sendable {
    /// Presses counted today for the layout being recorded; nil before one has been.
    var today: Int?
    var wordsPerMinute: Int
    /// Why nothing is being counted now.
    var pause: String?

    public init(today: Int?, wordsPerMinute: Int, pause: String? = nil) {
        self.today = today
        self.wordsPerMinute = wordsPerMinute
        self.pause = pause
    }

    /// The recorder as it is at `date`; nil while recording is off.
    @MainActor
    init?(_ recorder: HeatmapRecorder, at date: Date) {
        let status = recorder.status
        guard status != .off else { return nil }
        let pause: String? = if case .recording = status { nil } else { status.text(recordsThisLayout: nil) }
        self.init(today: recorder.today, wordsPerMinute: recorder.wordsPerMinute(at: date), pause: pause)
    }

    var text: String {
        if let pause { return String(localized: "Heatmap · \(pause)") }
        let presses = HeatCount.spoken(today ?? 0)
        return wordsPerMinute > 0
            ? String(localized: "Today: \(presses) · \(wordsPerMinute) wpm") : String(localized: "Today: \(presses)")
    }
}

/// One line under the mini map.
struct TypingStatsLine: View {
    var stats: TypingStats

    var body: some View {
        Label {
            Text(verbatim: stats.text).monospacedDigit().lineLimit(1).truncationMode(.tail)
        } icon: {
            Image(systemName: "flame").foregroundStyle(.secondary)
        }
        .font(.callout)
        .foregroundStyle(stats.pause == nil ? .primary : .secondary)
    }
}
