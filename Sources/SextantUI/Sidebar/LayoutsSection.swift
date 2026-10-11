import SextantApplication
import SwiftUI

/// The library's layouts; the open one is marked (spec §3.6). Each row has Rename…, Duplicate and Move to Trash….
struct LayoutsSection: View {
    var model: LayoutWindowModel
    @Binding var layoutID: UUID?
    @Environment(\.openWindow) private var openWindow
    @State private var pendingTrash: UUID?

    var body: some View {
        Section("Layouts") {
            ForEach(model.library.entries) { entry in
                let isOpenHere = entry.id == model.session?.id
                Button {
                    show(entry.id)
                } label: {
                    Label(model.title(of: entry.id), systemImage: isOpenHere ? "keyboard.fill" : "keyboard")
                        .fontWeight(isOpenHere ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOpenHere ? .isSelected : [])
                .contextMenu {
                    Button("Rename…") { model.layoutPendingRename = entry.id }
                    Button("Duplicate") { Task { await model.library.duplicate(entry.id) } }
                    Divider()
                    // A layout open in another window is closed there first; this window can't end that session.
                    Button("Move to Trash…") { pendingTrash = entry.id }.disabled(!model.canTrash(entry.id))
                }
                .confirmationDialog(
                    Text("Move “\(model.title(of: entry.id))” to the Trash?"),
                    isPresented: Binding(get: { pendingTrash == entry.id }, set: { if !$0 { pendingTrash = nil } })
                ) {
                    Button("Move to Trash", role: .destructive) { Task { await trash(entry.id) } }
                } message: {
                    Text("You can put it back from the Trash in Finder.")
                }
            }
        }
    }

    /// Opens a layout in this window, or brings forward the window that has it (one window per layout).
    private func show(_ id: UUID) {
        if id != model.session?.id, model.library.isOpen(id) {
            openWindow(id: "layout", value: id)
        } else {
            layoutID = id
        }
    }

    private func trash(_ id: UUID) async {
        let wasOpenHere = id == model.session?.id
        await model.trashLayout(id)
        // The window loads the next free layout itself, or shows its empty state.
        if wasOpenHere { layoutID = nil }
    }
}

extension LayoutWindowModel {
    /// A layout's title as the sidebar shows it: the open document's, so a rename or its undo shows at once.
    func title(of id: UUID) -> String {
        if let session, session.id == id { return session.layout.title }
        return library.entries.first { $0.id == id }?.title ?? ""
    }

    /// Another window's document can't be ended from here, so only a layout open here or nowhere can go to the Trash.
    func canTrash(_ id: UUID) -> Bool { id == session?.id || !library.isOpen(id) }

    /// Moves a layout to the Trash. The layout open here closes first: its Build & Flash stops (a waiting run would
    /// flash the next keyboard), its last edit is written, its undo steps go, and the window is left empty.
    func trashLayout(_ id: UUID) async {
        guard canTrash(id) else { return }
        if let session, session.id == id {
            onBuild?(.stop, session)
            await library.close(session)
            session.undoManager?.removeAllActions(withTarget: session)
            self.session = nil
        }
        await library.trash(id)
    }
}

/// Rename Layout… (File menu and the sidebar): the new title goes through the library, which renames an open document
/// in place so its autosave keeps the new title.
struct RenameLayoutAlert: ViewModifier {
    var model: LayoutWindowModel
    @State private var title = ""

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Rename Layout"),
                isPresented: Binding(get: { model.layoutPendingRename != nil }, set: { if !$0 { model.layoutPendingRename = nil } }),
                presenting: model.layoutPendingRename
            ) { id in
                TextField("Name", text: $title)
                Button("Rename") { Task { await model.library.rename(id, to: title) } }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: model.layoutPendingRename) {
                if let id = model.layoutPendingRename { title = model.title(of: id) }
            }
    }
}
