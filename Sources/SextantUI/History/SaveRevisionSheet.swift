import SextantApplication
import SwiftUI

/// Presents Save Revision while the window's history has a message to suggest.
struct SaveRevisionSheetPresenter: ViewModifier {
    var model: LayoutWindowModel

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(get: { model.history?.saveMessage != nil }, set: { if !$0 { model.history?.saveMessage = nil } })
        ) {
            SaveRevisionSheet(model: model)
        }
    }
}

/// Save Revision… (⌘S, spec §8.7): a message, prefilled from what changed since the last revision.
public struct SaveRevisionSheet: View {
    var model: LayoutWindowModel
    @State private var message: String
    @State private var error: LibraryError?
    @State private var isSaving = false

    public init(model: LayoutWindowModel) {
        self.model = model
        _message = State(initialValue: model.history?.saveMessage ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Save Revision").font(.title2.weight(.semibold))
            }
            Text("A revision is a checkpoint in History. You can compare the layout with it or restore it later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Message", text: $message, prompt: Text("What changed"))
                .textFieldStyle(.roundedBorder)
            if let error {
                Label {
                    Text(error.localizedDescription).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(Tokens.danger.color)
                }
                .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.history?.saveMessage = nil }.keyboardShortcut(.cancelAction)
                Button("Save Revision", action: save).keyboardShortcut(.defaultAction).disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save() {
        guard let history = model.history else { return }
        error = nil
        isSaving = true
        // Unstructured on purpose: closing the sheet must not cancel a save in progress.
        Task {
            do throws(LibraryError) {
                try await history.save(message: message)
            } catch {
                self.error = error
            }
            isSaving = false
        }
    }
}
