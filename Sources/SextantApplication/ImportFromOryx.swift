import Foundation
import Observation
import SextantDomain
import os

/// Import from Oryx (spec §8.1): read the link, fetch the layout read-only, check Oryx's firmware for it, convert,
/// preview, then save it as a new layout or as a revision of the layout imported earlier from the same Oryx layout.
@MainActor
@Observable
public final class ImportFromOryx {
    /// The progress checklist, in order.
    public enum Step: CaseIterable, Hashable, Sendable {
        case readLink, fetchLayout, checkFirmware, convert

        public var title: String {
            switch self {
            case .readLink: String(localized: "Read link")
            case .fetchLayout: String(localized: "Fetch layout")
            case .checkFirmware: String(localized: "Check firmware")
            case .convert: String(localized: "Convert")
            }
        }
    }

    public enum StepState: Hashable, Sendable { case pending, running, done, warning, failed }

    /// One parsed part of the link, shown as a chip ("Layout KlgM7").
    public struct Token: Identifiable, Hashable, Sendable {
        public var label: String
        public var value: String
        public var id: String { label }
    }

    /// What the import will bring in, shown before anything is saved.
    public struct Preview: Sendable {
        /// The layout as it will be saved (Oryx's " [fork]" suffix removed).
        public var layout: KeyboardLayout
        public var summary: ImportSummary
        public var notes: [String]
        /// The library layout imported from the same Oryx layout, which this import can become a revision of.
        public var existing: LibraryEntry?
        /// Oryx's md5-verified image for this revision, when it was downloaded.
        public var firmware: Data?
    }

    /// A saved import: the layout, and whether to open it ("Open after importing").
    public struct Imported: Hashable, Sendable {
        public var id: UUID
        public var open: Bool
    }

    /// The link or keyboard serial; changing it discards the previous result.
    public var input = "" {
        didSet { if input != oldValue { reset() } }
    }
    public var openAfterImporting = true
    /// Each step's state; a missing step is pending.
    public private(set) var steps: [Step: StepState] = [:]
    public private(set) var preview: Preview?
    /// Why the last fetch failed.
    public private(set) var error: OryxError?

    @ObservationIgnored private let oryx: any OryxReader
    @ObservationIgnored private let library: Library
    /// Bumped by every reset, so a fetch that finishes after the input changed is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.sextant.app", category: "application")

    public init(oryx: any OryxReader, library: Library) {
        self.oryx = oryx
        self.library = library
    }

    /// The parsed input, or nil while it isn't a link, serial or layout id (live validation).
    public var reference: OryxReference? { OryxReference(input) }

    /// Board, layout, revision and layer chips for the parsed input.
    public var tokens: [Token] {
        guard let reference else { return [] }
        var tokens: [Token] = []
        if let g = reference.geometry {
            tokens.append(Token(label: String(localized: "Board"), value: BoardDefinition.named(g)?.displayName ?? g.capitalized))
        }
        tokens.append(Token(label: String(localized: "Layout"), value: reference.layoutID))
        tokens.append(Token(label: String(localized: "Revision"), value: reference.revisionID ?? String(localized: "Latest")))
        if let layer = reference.layer { tokens.append(Token(label: String(localized: "Layer"), value: String(layer))) }
        return tokens
    }

    /// Runs read link → fetch layout → check firmware → convert, ending with ``preview`` or ``error``.
    public func fetch() async {
        reset()
        let run = generation
        guard let reference else {
            steps[.readLink] = .failed
            return
        }
        steps[.readLink] = .done
        steps[.fetchLayout] = .running
        var layout: KeyboardLayout
        do {
            layout = try await oryx.layout(reference)
        } catch {
            guard isCurrent(run) else { return }
            log.error("Fetching from Oryx failed: \(String(describing: error), privacy: .public)")
            steps[.fetchLayout] = .failed
            self.error = error
            return
        }
        guard isCurrent(run) else { return }
        steps[.fetchLayout] = .done

        steps[.checkFirmware] = .running
        var notes: [String] = []
        var firmware: Data?
        if let info = layout.oryx, let md5 = info.md5 {
            do {
                firmware = try await oryx.firmware(revisionID: info.revisionId, expectedMD5: md5)
            } catch {
                log.error("Oryx's firmware wasn't kept: \(String(describing: error), privacy: .public)")
                notes.append(
                    error == .checksumMismatch
                        ? error.localizedDescription
                        : String(localized: "Sextant couldn't download Oryx's firmware for this revision. The layout imported fine."))
            }
            guard isCurrent(run) else { return }
        }
        // A draft revision has no md5 and no firmware; there is nothing to check.
        steps[.checkFirmware] = notes.isEmpty ? .done : .warning

        steps[.convert] = .running
        layout.title = Library.cleanImportedTitle(layout.title)
        let summary = ImportSummary(layout)
        notes += Self.notes(for: summary)
        await library.refresh()
        guard isCurrent(run) else { return }
        let oryxID = layout.oryx?.layoutId
        let existing = library.entries.first { entry in
            if case let .oryx(layoutId, _) = entry.origin { layoutId == oryxID } else { false }
        }
        preview = Preview(layout: layout, summary: summary, notes: notes, existing: existing, firmware: firmware)
        steps[.convert] = .done
    }

    /// Saves the preview as a new layout or, with `asRevision`, as a new revision of ``Preview/existing``.
    /// Returns nil when there is nothing to save. A preview is saved once; it comes back if saving fails, unless the
    /// input changed meanwhile.
    public func importLayout(asRevision: Bool = false) async throws(LibraryError) -> Imported? {
        guard let preview else { return nil }
        self.preview = nil  // a second click while this one saves finds nothing to import
        let run = generation
        do {
            let entry = try await library.add(
                imported: preview.layout, asRevisionOf: asRevision ? preview.existing?.id : nil, firmware: preview.firmware)
            return Imported(id: entry.id, open: openAfterImporting)
        } catch {
            if run == generation { self.preview = preview }
            throw error
        }
    }

    private static func notes(for summary: ImportSummary) -> [String] {
        var notes: [String] = []
        if summary.unknownCodes > 0 {
            notes.append(
                String(localized: "\(summary.unknownCodes) keys use codes Sextant doesn't know yet. They're kept as they are and marked."))
        }
        if summary.customLabels > 0 {
            notes.append(String(localized: "\(summary.customLabels) custom labels are shown in Sextant only."))
        }
        if let navigator = summary.navigator {
            let kind =
                switch navigator.kind {
                case .trackpad: String(localized: "trackpad")
                case .trackball: String(localized: "trackball")
                case .knob: String(localized: "knob")
                }
            notes.append(
                navigator.side == .left
                    ? String(localized: "Navigator \(kind) found on the left half; its settings come along.")
                    : String(localized: "Navigator \(kind) found on the right half; its settings come along."))
        }
        notes.append(String(localized: "Oryx stays read-only. Sextant keeps its own copy."))
        return notes
    }

    private func isCurrent(_ run: Int) -> Bool { run == generation && !Task.isCancelled }

    private func reset() {
        generation += 1
        steps = [:]
        preview = nil
        error = nil
    }
}
