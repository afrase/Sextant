import SwiftUI

/// The library's layouts; the open one is marked (spec §3.6).
struct LayoutsSection: View {
    var model: LayoutWindowModel
    @Binding var layoutID: UUID?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section("Layouts") {
            ForEach(model.library.entries) { entry in
                Button {
                    show(entry.id)
                } label: {
                    Label(entry.title, systemImage: entry.id == model.session?.id ? "keyboard.fill" : "keyboard")
                        .fontWeight(entry.id == model.session?.id ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(entry.id == model.session?.id ? .isSelected : [])
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
}
