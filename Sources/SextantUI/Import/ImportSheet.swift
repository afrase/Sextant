import SextantApplication
import SextantDomain
import SwiftUI

extension LayoutWindowModel {
    /// Opens Import from Oryx (spec §8.1), optionally with a link or serial already filled in (a link pasted into ⌘K,
    /// the device card's [Import]); a filled-in reference is fetched at once. Does nothing where importing is off.
    func openImport(_ input: String? = nil) {
        guard let makeImport else { return }
        let flow = makeImport()
        flow.input = input ?? ""
        importFlow = flow
    }

    /// Importing is wired (it is off in tests and snapshots).
    var canImport: Bool { makeImport != nil }

    /// The connected keyboard's serial when it runs an Oryx build (`layout/revision`), for Import from Connected Keyboard.
    var connectedOryxSerial: String? { Self.oryxSerial(live?.firmwareSerial) }

    /// Sextant's own builds report `sx-…`, which names no Oryx layout.
    static func oryxSerial(_ serial: String?) -> String? {
        guard let serial, serial.contains("/"), OryxReference(serial) != nil else { return nil }
        return serial
    }

    /// The layout to bring forward in another window after an import, or nil: this window shows it, Open after
    /// importing is off, or this window is empty and opens the new layout itself (``ImportSheet``'s save).
    func windowToReveal(_ id: UUID, open: Bool) -> UUID? {
        guard open, id != session?.id, session != nil || library.isOpen(id) else { return nil }
        return id
    }
}

/// Presents Import from Oryx while the window has an import flow.
struct ImportSheetPresenter: ViewModifier {
    var model: LayoutWindowModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { model.importFlow != nil }, set: { if !$0 { model.importFlow = nil } })) {
            if let flow = model.importFlow {
                // A new flow (another Import request) starts a fresh sheet, so its filled-in link is fetched.
                ImportSheet(flow: flow, model: model).id(ObjectIdentifier(flow))
            }
        }
    }
}

/// Import from Oryx (spec §8.1): a link or the connected keyboard, the progress checklist, the preview, then a new
/// layout or a revision of the one imported before.
public struct ImportSheet: View {
    enum Source: Hashable { case link, keyboard }

    @Bindable var flow: ImportFromOryx
    var model: LayoutWindowModel
    @State private var source: Source
    /// Bumped to start a fetch; the task restarts, cancelling the last one.
    @State private var fetches: Int
    @State private var saveError: LibraryError?
    @Environment(\.openWindow) private var openWindow

    public init(flow: ImportFromOryx, model: LayoutWindowModel) {
        self.flow = flow
        self.model = model
        _source = State(initialValue: !flow.input.isEmpty && flow.input == model.connectedOryxSerial ? .keyboard : .link)
        _fetches = State(initialValue: flow.reference == nil ? 0 : 1)
    }

    public var body: some View {
        // The header and footer stay put while the rest scrolls, so a tall preview can't push them out of the sheet.
        VStack(alignment: .leading, spacing: 0) {
            header.padding([.horizontal, .top], 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch source {
                    case .link: linkField
                    case .keyboard: keyboardRow
                    }
                    if !flow.steps.isEmpty { ImportSteps(flow: flow, retry: fetch) }
                    if let preview = flow.preview { ImportPreview(preview: preview) }
                    if let saveError { ImportError(text: saveError.localizedDescription) }
                    Toggle("Open after importing", isOn: $flow.openAfterImporting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer.padding([.horizontal, .bottom], 20)
        }
        .frame(width: 560)
        .frame(maxHeight: 640)  // spec §7.2's cap; the middle scrolls past it
        .task(id: fetches) { if fetches > 0 { await flow.fetch() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Import from Oryx").font(.title2.weight(.semibold))
            Spacer()
            Picker("Source", selection: $source) {
                Text("Link").tag(Source.link)
                Text("Connected Keyboard").tag(Source.keyboard)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .onChange(of: source) {
            guard source == .keyboard else { return }
            flow.input = model.connectedOryxSerial ?? ""
            if !flow.input.isEmpty { fetch() }
        }
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Oryx link", text: $flow.input, prompt: Text(verbatim: "https://configure.zsa.io/voyager/layouts/…"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                // ⏎ fetches until there is a preview, then imports.
                Button("Fetch", action: fetch)
                    .keyboardShortcut(flow.preview == nil ? .defaultAction : nil)
                    .disabled(flow.reference == nil)
            }
            if flow.reference != nil {
                HStack(spacing: 6) {
                    ForEach(flow.tokens) { token in
                        HStack(spacing: 4) {
                            Text(token.label).foregroundStyle(.secondary)
                            Text(token.value)
                        }
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary))
                        .accessibilityElement(children: .combine)
                    }
                }
                if matchesKeyboard {
                    Label("Matches the connected keyboard", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                }
            } else {
                Text("Paste a configure.zsa.io link, or a layout ID such as KlgM7/40xJ7M.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var keyboardRow: some View {
        Group {
            if let serial = model.connectedOryxSerial {
                Label {
                    Text("Your Voyager reports \(Text(verbatim: serial).monospaced()). Sextant fetches that layout from Oryx, read-only.")
                } icon: {
                    Image(systemName: "keyboard")
                }
            } else if model.live?.firmwareSerial != nil {
                Label("This keyboard runs a layout Sextant built, so there is no Oryx layout to fetch.", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            } else {
                Label("Connect your Voyager with a USB cable.", systemImage: "cable.connector").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { model.importFlow = nil }.keyboardShortcut(.cancelAction)
            if let existing = flow.preview?.existing {
                Button("Add as Revision of ‘\(existing.title)’") { save(asRevision: true) }
            }
            Button("Import as New Layout") { save(asRevision: false) }
                .keyboardShortcut(flow.preview == nil ? nil : .defaultAction)
                .disabled(flow.preview == nil)
        }
    }

    /// "Matches the connected keyboard": the link names the revision the keyboard runs.
    private var matchesKeyboard: Bool {
        guard let reference = flow.reference, let revision = reference.revisionID else { return false }
        return model.connectedOryxSerial == "\(reference.layoutID)/\(revision)"
    }

    private func fetch() {
        guard flow.reference != nil else { return }
        fetches += 1
    }

    private func save(asRevision: Bool) {
        saveError = nil
        // Unstructured on purpose: closing the sheet must not cancel a save in progress.
        Task {
            do throws(LibraryError) {
                guard let imported = try await flow.importLayout(asRevision: asRevision) else { return }
                let reveal = model.windowToReveal(imported.id, open: imported.open)
                model.importFlow = nil
                if let reveal {
                    openWindow(id: "layout", value: reveal)
                } else if imported.open, model.session == nil {
                    await model.open(imported.id)
                }
            } catch {
                saveError = error
            }
        }
    }
}

/// The progress checklist (spec §8.1, §12.5), with the fetch error under it.
private struct ImportSteps: View {
    var flow: ImportFromOryx
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ImportFromOryx.Step.allCases, id: \.self) { step in
                let state = flow.steps[step] ?? .pending
                HStack(spacing: 8) {
                    StepIcon(state: state).frame(width: 16)
                    Text(step.title).foregroundStyle(state == .pending ? .secondary : .primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(StepIcon.description(state))
            }
            if let error = flow.error {
                HStack(alignment: .firstTextBaseline) {
                    ImportError(text: error.localizedDescription)
                    if error == .offline { Button("Try Again", action: retry) }
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct StepIcon: View {
    var state: ImportFromOryx.StepState

    var body: some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running: DelayedSpinner()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    static func description(_ state: ImportFromOryx.StepState) -> String {
        switch state {
        case .pending: String(localized: "Not started")
        case .running: String(localized: "In progress")
        case .done: String(localized: "Done")
        case .warning: String(localized: "Done, with a note")
        case .failed: String(localized: "Failed")
        }
    }
}

/// What the import brings in, before anything is saved: layers, counts and notes.
private struct ImportPreview: View {
    var preview: ImportFromOryx.Preview

    var body: some View {
        let s = preview.summary
        VStack(alignment: .leading, spacing: 12) {
            Text(preview.layout.title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(Array(preview.layout.layers.enumerated()), id: \.offset) { index, layer in
                    HStack(spacing: 6) {
                        LayerChip(color: layer.color, size: 10)
                        Text(verbatim: "\(index)").monospacedDigit().foregroundStyle(.secondary)
                        Text(layer.title).lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(spacing: 0) {
                stat(s.layers, "layers")
                stat(s.assignedKeys, "keys")
                stat(s.dualFunctionKeys, "dual-function")
                stat(s.customLabels, "labels")
                stat(s.colorKeys, "color keys")
                stat(s.macros, "macros")
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(preview.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quinary))
    }

    private func stat(_ value: Int, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(value)").font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ImportError: View {
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
        .font(.callout)
    }
}

/// A small spinner that shows only after a second, so quick work doesn't flicker (spec §12.5).
struct DelayedSpinner: View {
    @State private var isVisible = false

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .opacity(isVisible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(1))
                isVisible = true
            }
            .accessibilityLabel(String(localized: "Loading"))
    }
}
