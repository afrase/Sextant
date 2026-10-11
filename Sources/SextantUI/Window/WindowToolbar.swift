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
                state: model.activity, boardName: model.boardName,
                onShowDevice: model.live == nil ? nil : { model.devicePopover = .capsule },
                onShowLog: model.buildFlash == nil ? nil : { model.showsBuildSheet = true },
                // The toolbar sizes items by their ideal width: at the narrowest, the trailing items need the room.
                idealWidth: windowWidth >= 1280 ? 440 : 280
            )
            // A new identity when the width changes, so the toolbar measures the item again.
            .id(windowWidth >= 1280)
            .devicePopover(model, from: .capsule)
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
            .help(followHelp)
        }
        ToolbarItem(id: "search", placement: .primaryAction) {
            Button {
                model.openPalette()
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
            .disabled(model.session == nil)
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

extension WindowToolbar {
    /// Why Follow is off, when it is: live access off or Keymapp holding the keyboard leaves no layer to follow.
    private var followHelp: Text {
        if model.canFollow { return Text("Follow the keyboard’s layer (⌘L)") }
        if model.session == nil { return Text("Open a layout to follow the keyboard’s layer") }
        if model.connectedKeyboard == nil { return Text("Connect your keyboard to follow its layer") }
        return Text("Sextant can’t read the keyboard’s layer")
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
