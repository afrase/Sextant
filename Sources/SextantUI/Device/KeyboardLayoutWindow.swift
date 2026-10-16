import SextantApplication
import SextantDomain
import SwiftUI

/// The Layout on the Keyboard window (ADR 0061): the layout Sextant read from the keyboard that no library layout is
/// linked to, and where to add it. Add to Library… opens it from the device card, the Device popover and the menu bar.
/// When the pull moves on from what it found, the window says what happened, or closes when there is nothing to say.
public struct KeyboardLayoutWindow: View {
    /// The window scene's id.
    public static let sceneID = "keyboard-layout"

    var pull: KeyboardLayoutPull
    var library: Library
    @Environment(WindowRouter.self) private var windows: WindowRouter?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    public init(pull: KeyboardLayoutPull, library: Library) {
        self.pull = pull
        self.library = library
    }

    public var body: some View {
        content
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
            // Forgotten (the keyboard went away, or another one came): there is nothing left to add.
            .onChange(of: pull.status == .idle, initial: true) { _, idle in
                if idle { close() }
            }
    }

    @ViewBuilder private var content: some View {
        switch pull.status {
        case let .found(found):
            KeyboardLayoutForm(found: found, library: library, add: { await add(to: $0) }, cancel: { close() })
                // A layout read again (Try Again, another keyboard) starts over with its own suggestion.
                .id(found.serial)
        case let .reading(fraction):
            VStack(alignment: .leading, spacing: 10) {
                Text("Reading the layout from the keyboard…").font(.callout)
                ProgressView(value: min(max(fraction, 0), 1)).progressViewStyle(.linear)
                    .accessibilityLabel(Text("Reading the layout from the keyboard"))
            }
            .padding(20)
        case .noRecord:
            outcome(Text(KeyboardLayoutPrompt.noRecordText), symbol: "info.circle", tint: .secondary) {
                Button("Close") { close() }.keyboardShortcut(.defaultAction)
            }
        case let .failed(failure):
            outcome(Text(verbatim: failure.localizedDescription), symbol: "exclamationmark.triangle.fill", tint: Tokens.warning.color) {
                Button("Close") { close() }.keyboardShortcut(.cancelAction)
                Button("Try Again") { Task { await pull.read(startingLiveView: true) } }.keyboardShortcut(.defaultAction)
            }
        case let .added(added):
            outcome(Text(addedText(added)), symbol: "checkmark.circle.fill", tint: Tokens.success.color) {
                Button("Close") { close() }.keyboardShortcut(.cancelAction)
                Button("Show Layout") { showLayout(added.entryID) }.keyboardShortcut(.defaultAction)
            }
        case .idle:
            Color.clear.frame(height: 1)
        }
    }

    /// What happened instead of a layout to add, with the buttons that go on from it.
    private func outcome(_ text: Text, symbol: String, tint: Color, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                text.fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.callout)
            HStack {
                Spacer()
                buttons()
            }
        }
        .padding(20)
    }

    /// Adds the layout, then shows the layout it went to and closes. A failure stays here, with Try Again.
    private func add(to target: UUID?) async {
        await pull.add(to: target)
        guard case let .added(added) = pull.status else { return }
        showLayout(added.entryID)
        close()
    }

    /// The layout's window, opened or brought forward, also when Sextant is only in the menu bar.
    private func showLayout(_ id: UUID) {
        guard let windows else { return openWindow.layout(id) }
        windows.showWindow { openWindow.layout(id) }
    }

    private func close() { dismissWindow(id: Self.sceneID) }

    private func addedText(_ added: KeyboardLayoutPull.Added) -> String {
        guard let title = library.entries.first(where: { $0.id == added.entryID })?.title else {
            return String(localized: "Sextant put the keyboard’s layout in your library.")
        }
        return String(localized: "Sextant put the keyboard’s layout in ‘\(title)’.")
    }

    /// Where a layout read from the keyboard came from: the Oryx revision when the keyboard reports that revision's
    /// serial, otherwise a Sextant build on another Mac.
    static func origin(of layout: KeyboardLayout, serial: String) -> String {
        guard let oryx = layout.oryx, oryx.serial == serial else { return String(localized: "Flashed from Sextant on another Mac") }
        return String(localized: "Oryx revision \(oryx.revisionId)")
    }

    /// The suggested library layout's name in the Add to menu, with why: it came from the same Oryx layout, or else it has
    /// the same name.
    static func suggestion(_ entry: LibraryEntry, for layout: KeyboardLayout) -> String {
        if case let .oryx(layoutId, _) = entry.origin, layoutId == layout.oryx?.layoutId {
            return String(localized: "\(entry.title) (same Oryx layout)")
        }
        return String(localized: "\(entry.title) (same name)")
    }
}

/// The layout read from the keyboard: its name, where it came from, its layers and its base layer, then where to add it.
private struct KeyboardLayoutForm: View {
    var found: KeyboardLayoutPull.Found
    var library: Library
    var add: @MainActor (UUID?) async -> Void
    var cancel: @MainActor () -> Void
    /// Where to add it: a library layout, or a new one (nil).
    @State private var target: UUID?
    @State private var isAdding = false

    init(
        found: KeyboardLayoutPull.Found, library: Library, add: @escaping @MainActor (UUID?) async -> Void,
        cancel: @escaping @MainActor () -> Void
    ) {
        self.found = found
        self.library = library
        self.add = add
        self.cancel = cancel
        // The layout it most likely is, chosen already.
        let suggested = found.suggested.flatMap { id in library.entries.contains(where: { $0.id == id }) ? id : nil }
        _target = State(initialValue: suggested)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            layers
            LayerMap(layout: found.layout, layer: 0)
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("The keyboard’s \(found.layout.layers.first?.title ?? "") layer"))
            Divider()
            destination
            buttons
        }
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "keyboard").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: found.layout.title).font(.headline)
                Text(KeyboardLayoutWindow.origin(of: found.layout, serial: found.serial)).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Each layer as a chip: its colour, number and name.
    private var layers: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(found.layout.layers.enumerated()), id: \.offset) { index, layer in
                HStack(spacing: 5) {
                    LayerChip(color: layer.color, size: 9)
                    Text(verbatim: "\(index)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(verbatim: layer.title).font(.callout).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(layer.title), layer \(index)"))
            }
        }
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Add to", selection: $target) {
                Text("New Layout").tag(UUID?.none)
                Divider()
                ForEach(library.entries) { entry in
                    Text(verbatim: title(entry)).tag(Optional(entry.id))
                }
            }
            .disabled(isAdding)
            if target != nil {
                Text("Becomes its working copy. Your current version stays in History.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A library layout's name in the menu: the suggested one says why.
    private func title(_ entry: LibraryEntry) -> String {
        entry.id == found.suggested ? KeyboardLayoutWindow.suggestion(entry, for: found.layout) : entry.title
    }

    private var buttons: some View {
        HStack {
            if isAdding { ProgressView().controlSize(.small).accessibilityLabel(Text("Adding")) }
            Spacer()
            Button("Cancel", role: .cancel) { cancel() }.keyboardShortcut(.cancelAction)
            Button("Add") {
                isAdding = true
                // Unstructured on purpose: closing the window must not cancel an add in progress.
                Task {
                    await add(target)
                    isAdding = false
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isAdding)
        }
    }
}
