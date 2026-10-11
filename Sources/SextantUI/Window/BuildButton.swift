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
            // A progress display, not a control: a disabled prominent button would keep its tint and fade its label.
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
            .allowsHitTesting(false)
            .accessibilityRemoveTraits(.isButton)
            .accessibilityLabel(Text("Writing firmware, \(Int((fraction * 100).rounded())) percent"))
        default:
            Group {
                if model.canBuild {
                    buildAndFlash.buttonStyle(.glassProminent)
                } else {
                    // Disabled prominent glass keeps its full tint with a faded label; plain glass reads as off.
                    buildAndFlash.buttonStyle(.glass).disabled(true)
                }
            }
            .controlSize(.large)
            .help(Text("Build the firmware and flash the keyboard (⌘R)"))
        }
    }

    private var buildAndFlash: some View {
        Button {
            model.build(.buildAndFlash)
        } label: {
            Label("Build & Flash", systemImage: "bolt.fill").labelStyle(.titleAndIcon)
        }
    }
}
