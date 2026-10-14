import SwiftUI

/// Up to two glass capsules, centred (spec §3.7). Today: the status capsule (``LayoutWindowModel/laneStatus``).
struct LensLane: View {
    var model: LayoutWindowModel
    @Environment(\.motion) private var motion
    @AppStorage(SettingsKey.showsKeyPresses) private var showsPresses = true

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if model.page == .history, let history = model.history {
                    HistoryCapsule(history: history).glassEffectTransition(.materialize)
                } else if model.page == .combos, let session = model.session {
                    ComboCapsule(model: model, session: session).glassEffectTransition(.materialize)
                } else if model.lens == .lighting, let session = model.session {
                    LightingCapsule(model: model, session: session).glassEffectTransition(.materialize)
                } else if model.lens == .heatmap, let session = model.session {
                    HeatmapCapsule(model: model, session: session).glassEffectTransition(.materialize)
                }
                // Status by priority: a pick (the only place that says what a click does) or Select Key by Pressing It (the
                // only place that says what a press does) > an issue > recording > the rest. Record Key hides a pick while it
                // holds the keyboard, since esc ends it first (spec §9.3).
                if let pick = model.boardPick, model.recorder == nil {
                    PickCapsule(model: model, prompt: pick.prompt).glassEffectTransition(.materialize)
                } else if model.selectsByPress {
                    SelectByPressCapsule(model: model).glassEffectTransition(.materialize)
                } else if model.recorder != nil, model.laneStatus?.isIssue != true {
                    RecordingCapsule(model: model).glassEffectTransition(.materialize)
                } else if let status = model.laneStatus {
                    capsule(status)
                        .glassEffectTransition(.materialize)
                } else if let id = model.session?.id, let text = model.appLayers.laneText(id),
                    let short = model.appLayers.shortLaneText(id)
                {
                    // Last in priority (spec §3.7).
                    AppRuleCapsule(model: model, text: text, shortText: short).glassEffectTransition(.materialize)
                }
            }
        }
        .animation(motion.standard, value: model.laneStatus)
        .animation(motion.standard, value: model.recorder != nil)
        .animation(motion.standard, value: model.boardPick != nil)
        .animation(motion.standard, value: model.selectsByPress)
    }

    @ViewBuilder private func capsule(_ status: LaneStatus) -> some View {
        HStack(spacing: 8) {
            switch status {
            case let .issue(text, key):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Tokens.danger.color)
                Text(text).lineLimit(1)
                Button("Show Key") { model.showIssue(key) }.buttonStyle(.borderless)
            case let .live(text):
                // With presses off the board, the count leaves too (Settings › Keyboard).
                let down = showsPresses ? model.live?.pressedKeys.count ?? 0 : 0
                Circle().fill(Tokens.success.color).frame(width: 7, height: 7)
                Text(down == 0 ? text : "\(text) · \(down == 1 ? String(localized: "1 key down") : String(localized: "\(down) keys down"))")
                    .lineLimit(1)
                Button("Stop Following") { model.isFollowing = false }.buttonStyle(.borderless)
            case .recovered:
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                Text(verbatim: LayoutWindowModel.recoveredNotice).lineLimit(1)
                Button("OK") { model.session?.recoveredUnsavedChanges = false }.buttonStyle(.borderless)
            case let .saveFailed(reason):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.danger.color)
                Text("Sextant couldn’t save: \(reason)").lineLimit(1).help(reason)
                Button("Try Again") { Task { await model.session?.flush() } }.buttonStyle(.borderless)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}

/// A board pick's prompt, with [Cancel] as esc does (spec §6.3, §6.4).
private struct PickCapsule: View {
    var model: LayoutWindowModel
    var prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left").foregroundStyle(Color.accentColor).accessibilityHidden(true)
            Text(prompt).lineLimit(1)
            Button("Cancel") { model.cancelBoardPick() }.buttonStyle(.borderless)
                // esc reaches the window even when the board's exit command doesn't: right after Assign to Key leaves its page
                // for the board, a probe saw about 1 esc in 25 missed (ADR 0042).
                .keyboardShortcut(.cancelAction)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}

/// The frontmost app's rule as it holds (spec §3.7, §8.6), with [Rules…] for the App Layers page. Beside a lens's tools
/// in a narrow lane it says "Xcode → Sym+Num", so the layer's name, the one fact it shows, isn't cut off.
private struct AppRuleCapsule: View {
    var model: LayoutWindowModel
    var text: String
    var shortText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow.on.rectangle").foregroundStyle(.secondary).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                Text(verbatim: text).lineLimit(1)
                Text(verbatim: shortText).lineLimit(1).accessibilityLabel(Text(verbatim: text))
            }
            Button("Rules…") { model.destination = .appLayers }.buttonStyle(.borderless)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}
