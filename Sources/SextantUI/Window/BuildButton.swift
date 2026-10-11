import SwiftUI

/// The primary action (spec §3.4): Build & Flash, Stop while building or waiting, Writing… while writing.
struct BuildButton: View {
    var model: LayoutWindowModel

    var body: some View {
        switch model.activity.status {
        case .building, .waitingForFlashMode:
            Button {
                model.build(.stop)
            } label: {
                Label("Stop", systemImage: "stop.fill").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .tint(Tokens.danger.color)
            .controlSize(.large)
            .help(Text("Stop (⌘.)"))
        case let .writing(fraction, _), let .verifying(fraction, _):
            Button {
            } label: {
                Label {
                    Text("Writing…")
                } icon: {
                    ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.mini)
                }
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(true)
        default:
            Button {
                model.build(.buildAndFlash)
            } label: {
                Label("Build & Flash", systemImage: "bolt.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!model.canBuild)
            .help(Text("Build the firmware and flash the keyboard (⌘R)"))
        }
    }
}
