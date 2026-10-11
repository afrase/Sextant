import SwiftUI

/// Up to two glass capsules, centred (spec §3.7). Today: the status capsule (an issue, else live Follow).
struct LensLane: View {
    var model: LayoutWindowModel
    @Environment(\.motion) private var motion

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if model.lens == .lighting, let session = model.session {
                    LightingCapsule(model: model, session: session).glassEffectTransition(.materialize)
                }
                // Status by priority: error > recording > live.
                if model.recorder != nil, model.laneStatus?.isIssue != true {
                    RecordingCapsule(model: model).glassEffectTransition(.materialize)
                } else if let status = model.laneStatus {
                    capsule(status)
                        .glassEffectTransition(.materialize)
                }
            }
        }
        .animation(motion.standard, value: model.laneStatus)
        .animation(motion.standard, value: model.recorder != nil)
    }

    @ViewBuilder private func capsule(_ status: LaneStatus) -> some View {
        HStack(spacing: 8) {
            switch status {
            case let .issue(text, key):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Tokens.danger.color)
                Text(text).lineLimit(1)
                Button("Show Key") { model.showIssue(key) }.buttonStyle(.borderless)
            case let .live(text):
                let down = model.live?.pressedKeys.count ?? 0
                Circle().fill(Tokens.success.color).frame(width: 7, height: 7)
                Text(down == 0 ? text : "\(text) · \(down == 1 ? String(localized: "1 key down") : String(localized: "\(down) keys down"))")
                    .lineLimit(1)
                Button("Stop Following") { model.isFollowing = false }.buttonStyle(.borderless)
            case .recovered:
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                Text("Restored edits that weren't saved when Sextant quit").lineLimit(1)
                Button("OK") { model.session?.recoveredUnsavedChanges = false }.buttonStyle(.borderless)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}
