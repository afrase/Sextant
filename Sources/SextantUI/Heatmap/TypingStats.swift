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
        self.init(today: recorder.pressesToday(at: date), wordsPerMinute: recorder.wordsPerMinute(at: date), pause: pause)
    }

    var text: String {
        if let pause { return String(localized: "Heatmap · \(pause)") }
        let presses = HeatCount.spoken(today ?? 0)
        return wordsPerMinute > 0
            ? String(localized: "Today: \(presses) · \(wordsPerMinute) wpm") : String(localized: "Today: \(presses)")
    }
}

/// Where the typing line reads from: the app-wide recorder, or fixed stats (snapshots).
enum TypingStatsSource {
    case recorder(HeatmapRecorder)
    case fixed(TypingStats)

    @MainActor func stats(at date: Date) -> TypingStats? {
        switch self {
        case let .recorder(recorder): TypingStats(recorder, at: date)
        case let .fixed(stats): stats
        }
    }

    /// Whether the line shows, read without the counts: the panel lays out around the line, which redraws itself.
    @MainActor var isShown: Bool {
        switch self {
        case let .recorder(recorder): recorder.status != .off
        case .fixed: true
        }
    }

    /// The line says recording waits for a password field, which then says secure input is on for the mini map too.
    @MainActor var isPausedForSecureInput: Bool {
        let pause = HeatmapRecorder.Status.waiting(.secureInput)
        return switch self {
        case let .recorder(recorder): recorder.status == pause
        case let .fixed(stats): stats.pause == pause.text(recordsThisLayout: nil)
        }
    }
}

/// One line under the mini map, or nothing while recording is off. It redraws itself every few seconds, so words per
/// minute fall as typing stops with no press to redraw the panel.
struct TypingStatsLine: View {
    var source: TypingStatsSource

    var body: some View {
        if let shown = source.stats(at: .now) {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                line(source.stats(at: context.date) ?? shown)
            }
        }
    }

    private func line(_ stats: TypingStats) -> some View {
        Label {
            // The longest pause reason is wider than the panel: it wraps rather than losing the reason.
            Text(verbatim: stats.text).monospacedDigit().lineLimit(2).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "flame").foregroundStyle(.secondary)
        }
        .font(.callout)
        .foregroundStyle(stats.pause == nil ? .primary : .secondary)
    }
}
