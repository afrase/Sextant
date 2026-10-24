import SextantApplication
import SwiftUI

/// The library's layouts; the open one is marked, and the one the keyboard runs badged (spec §2.3, §3.6). Each row
/// has Rename…, Duplicate and Move to Trash….
struct LayoutsSection: View {
    var model: LayoutWindowModel
    @Binding var layoutID: UUID?
    @Environment(\.openWindow) private var openWindow

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
                .badge(model.live?.firmwareSerial.map(entry.isOnKeyboard) == true ? Text("On keyboard") : nil)
                .badgeProminence(.decreased)
                .accessibilityAddTraits(isOpenHere ? .isSelected : [])
                .contextMenu {
                    Button("Rename…") { model.layouts.pendingRename = entry.id }
                    Button("Duplicate") { Task { await model.library.duplicate(entry.id) } }
                    Divider()
                    Button("Move to Trash…") { model.layouts.pendingTrash = entry.id }.disabled(!model.canTrash(entry.id))
                }
            }
            // The Welcome's choices once the library has a layout (spec §12.1, File ▸ New and Import).
            Menu {
                Button("New Layout") { Task { await addBlankLayout(to: model.library, from: model, openWindow: openWindow) } }
                Divider()
                Button("Import from Oryx…") { model.openImport() }.disabled(!model.canImport)
                Button("Import from Connected Keyboard") { model.openImport(model.connectedOryxSerial) }
                    .disabled(!model.canImport || model.connectedOryxSerial == nil)
            } label: {
                Label("Add Layout", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
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

}

extension LayoutWindowModel {
    /// A layout's title as the sidebar shows it: the open document's, so a rename or its undo shows at once.
    func title(of id: UUID) -> String {
        if let session, session.id == id { return session.layout.title }
        return library.entries.first { $0.id == id }?.title ?? ""
    }

    /// Any layout but one whose firmware is being written, which can't be stopped (spec §7.4). A layout open in
    /// another window closes there first (``TrashLayoutDialog``), which stops a run that is building or waiting.
    func canTrash(_ id: UUID) -> Bool {
        id == session?.id ? buildFlash?.canStop != false : !(live?.flashingLayoutID == id && live?.isWritingFirmware == true)
    }

    /// Moves a layout to the Trash. The layout open here closes first: its Build & Flash stops (a waiting run would
    /// flash the next keyboard), its last edit is written, its undo steps go, and the window is left empty.
    func trashLayout(_ id: UUID) async {
        guard canTrash(id) else { return }
        if let session, session.id == id {
            await close()
            session.undoManager?.removeAllActions(withTarget: session)
            self.session = nil
            buildFlash = nil
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
                isPresented: Binding(get: { model.layouts.pendingRename != nil }, set: { if !$0 { model.layouts.pendingRename = nil } }),
                presenting: model.layouts.pendingRename
            ) { id in
                TextField("Name", text: $title)
                Button("Rename") { Task { await model.library.rename(id, to: title) } }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: model.layouts.pendingRename) {
                if let id = model.layouts.pendingRename { title = model.title(of: id) }
            }
    }
}

/// Move to Trash… for a layout, from its sidebar row or File ▸ Move Layout to Trash…. A layout open in another window
/// closes there first, which writes its last edit and lets it go; the library refuses one that is still open.
struct TrashLayoutDialog: ViewModifier {
    var model: LayoutWindowModel
    @Binding var layoutID: UUID?
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        let pending = model.layouts.pendingTrash
        content.confirmationDialog(
            Text("Move “\(pending.map(model.title(of:)) ?? "")” to the Trash?"),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { model.layouts.pendingTrash = nil } }),
            presenting: pending
        ) { id in
            Button("Move to Trash", role: .destructive) { Task { await trash(id) } }
        } message: { _ in
            Text("You can put it back from the Trash in Finder.")
        }
    }

    private func trash(_ id: UUID) async {
        if id != model.session?.id, model.library.isOpen(id) {
            dismissWindow(id: "layout", value: id)
            for _ in 0..<30 where model.library.isOpen(id) { try? await Task.sleep(for: .milliseconds(100)) }
        }
        let wasOpenHere = id == model.session?.id
        await model.trashLayout(id)
        // The window loads the next free layout itself, or shows its empty state.
        if wasOpenHere { layoutID = nil }
    }
}
