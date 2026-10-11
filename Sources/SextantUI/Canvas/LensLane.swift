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
                if let status = model.laneStatus {
                    capsule(status)
                        .glassEffectTransition(.materialize)
                }
            }
        }
        .animation(motion.standard, value: model.laneStatus)
    }

    @ViewBuilder private func capsule(_ status: LaneStatus) -> some View {
        HStack(spacing: 8) {
            switch status {
            case let .issue(text, key):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Tokens.danger.color)
                Text(text).lineLimit(1)
                Button("Show Key") { model.showIssue(key) }.buttonStyle(.borderless)
            case let .live(text):
                Circle().fill(Tokens.success.color).frame(width: 7, height: 7)
                Text(text).lineLimit(1)
                Button("Stop Following") { model.isFollowing = false }.buttonStyle(.borderless)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}
