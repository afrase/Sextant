import Foundation
import SextantDomain

/// The layout read back from the keyboard's firmware (ADR 0061), made the document.
extension EditSession {
    /// Records the layout a keyboard runs in History ("From the keyboard"), then makes it the document as one undoable edit.
    /// Unlike an import it is kept exactly, title and layer ids included, since its fingerprint is what names it on the
    /// keyboard; only the macro drafts stay, which no firmware holds (ADR 0047). Edits since the last revision are
    /// checkpointed first; a failure leaves the document as it was. Undo leaves the appended revisions, as after an import.
    /// - Parameter source: `.flash` for a Sextant serial, `.import` for an Oryx one (so the import rule finds it).
    @discardableResult
    func useKeyboardLayout(_ keyboard: KeyboardLayout, source: RevisionSource) async throws(LibraryError) -> RevisionSummary {
        try await checkpoint(String(localized: "Before using the keyboard's layout"))
        var next = keyboard
        next.macroDrafts = layout.macroDrafts
        let draft = RevisionDraft(source: source, message: String(localized: "From the keyboard"), layout: next)
        let summary = try await recordRevision(draft)
        edit(
            String(localized: "Use the Keyboard's Layout"),
            select: { selection, doc in
                selection.layer = min(selection.layer, max(doc.layers.count - 1, 0))
                // Combo ids are positions, so the old id may now name another combo.
                selection.combo = nil
            }
        ) { $0 = next }
        await flush()
        // A temporary session (no window open) is discarded after this; its save error must not be.
        if let saveError { throw saveError }
        return summary
    }

    /// [Use It]: makes a revision read back from the keyboard the document again, as one undoable edit. Unlike History's
    /// ``restoreRevision(_:)``, which keeps the working copy's title, it takes the revision exactly, title included, since
    /// its fingerprint is what names it on the keyboard; only the macro drafts stay, which no firmware holds (ADR 0047).
    /// Recorded as a new revision ("Restored revision 3") after edits since the last revision are checkpointed. A failure
    /// leaves the document as it was. Undo leaves the appended revisions, as after a restore.
    public func restoreKeyboardRevision(_ revision: RevisionSummary) async throws(LibraryError) {
        let recorded = try await revisionLayout(revision.id)
        func restored() -> KeyboardLayout {
            var next = recorded
            next.macroDrafts = layout.macroDrafts
            return next
        }
        guard restored() != layout else { return }
        try await checkpoint(String(localized: "Before restoring revision \(revision.number)"))
        // Read after the checkpoint's wait: the drafts may have changed meanwhile.
        let next = restored()
        let draft = RevisionDraft(source: .save, message: String(localized: "Restored revision \(revision.number)"), layout: next)
        try await recordRevision(draft)
        edit(
            String(localized: "Use the Keyboard's Layout"),
            select: { selection, doc in
                selection.layer = min(selection.layer, max(doc.layers.count - 1, 0))
                // Combo ids are positions, so the old id may now name another combo.
                selection.combo = nil
            }
        ) { $0 = next }
    }
}
