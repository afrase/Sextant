import SextantApplication
import SwiftUI

/// The customisable window toolbar (spec §3.4), leading to trailing: Build & Flash, the activity capsule,
/// Undo / Redo, Follow Keyboard, Search and the inspector toggle. The sidebar toggle is the system's.
struct WindowToolbar: CustomizableToolbarContent {
    var model: LayoutWindowModel
    var windowWidth: CGFloat

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "build", placement: .navigation) {
            BuildButton(model: model)
        }
        ToolbarItem(id: "activity", placement: .principal) {
            ActivityCapsule(
                state: model.activity, boardName: model.session?.layout.board?.displayName ?? "",
                onShowLog: model.onBuild == nil ? nil : { model.build(.showLog) },
                // The toolbar sizes items by their ideal width: at the narrowest, the trailing items need the room.
                idealWidth: windowWidth >= 1280 ? 440 : 280
            )
            // A new identity when the width changes, so the toolbar measures the item again.
            .id(windowWidth >= 1280)
        }
        ToolbarSpacer(.flexible)
        ToolbarItem(id: "undo", placement: .primaryAction) {
            UndoButton(session: model.session, redo: false)
        }
        ToolbarItem(id: "redo", placement: .primaryAction) {
            UndoButton(session: model.session, redo: true)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(id: "follow", placement: .primaryAction) {
            Toggle(isOn: Binding(get: { model.isFollowing }, set: { model.isFollowing = $0 })) {
                Label("Follow Keyboard", systemImage: "dot.radiowaves.left.and.right")
            }
            .toggleStyle(.button)
            .disabled(!model.canFollow)
            .help(model.canFollow ? Text("Follow the keyboard’s layer (⌘L)") : Text("Connect your keyboard to follow its layer"))
        }
        ToolbarItem(id: "search", placement: .primaryAction) {
            // shortcut: the command palette (spec step 5) wires this; until then it is shown but off.
            Button {
            } label: {
                if windowWidth >= 1280 {
                    // A view, not a Label: toolbars draw Labels as icons only.
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                        Text(verbatim: "⌘K").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Search"))
                } else {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            // A new identity when the label changes, so the toolbar measures the item again.
            .id(windowWidth >= 1280)
            .disabled(true)
            .help(Text("Search commands, keys, layers and settings (⌘K)"))
        }
        ToolbarItem(id: "inspector", placement: .primaryAction) {
            Button {
                model.showsInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(model.showsInspector ? Text("Hide Inspector") : Text("Show Inspector"))
        }
    }
}

/// Undo or Redo, named after the action it will take, like the Edit menu (spec §3.4).
private struct UndoButton: View {
    var session: EditSession?
    var redo: Bool

    var body: some View {
        let undoManager = session?.undoManager
        // The session's `canUndo` / `canRedo` follow every edit, undo and redo, so the names refresh with them.
        let can = (redo ? session?.canRedo : session?.canUndo) ?? false
        let title = (redo ? undoManager?.redoMenuItemTitle : undoManager?.undoMenuItemTitle) ?? ""
        return Button {
            if redo { undoManager?.redo() } else { undoManager?.undo() }
        } label: {
            Label(redo ? "Redo" : "Undo", systemImage: redo ? "arrow.uturn.forward" : "arrow.uturn.backward")
        }
        .disabled(!can)
        .help(Text(verbatim: "\(title) (\(redo ? "⇧⌘Z" : "⌘Z"))"))
    }
}

/// The primary action (spec §3.4): Build & Flash, Stop while building or waiting, Writing… while writing.
private struct BuildButton: View {
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
