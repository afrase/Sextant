import SwiftUI

/// The primary action (spec §3.4): Build & Flash, Stop while setting up, building or waiting, Writing… while flashing.
struct BuildButton: View {
    var model: LayoutWindowModel

    var body: some View {
        switch model.activity.status {
        case .settingUp, .generating, .building, .linking, .waitingForFlashMode:
            Button {
                model.build(.stop)
            } label: {
                Label("Stop", systemImage: "stop.fill").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .tint(Tokens.danger.color)
            .controlSize(.large)
            .help(Text("Stop (⌘.)"))
        case .erasing, .writing, .verifying:
            let fraction: Double =
                switch model.activity.status {
                case let .erasing(fraction), let .writing(fraction, _): fraction
                default: 1
                }
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
