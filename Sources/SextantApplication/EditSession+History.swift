import Foundation
import SextantDomain

/// History's edits (ADR 0043): reading a revision's layout, restoring one, and recording a flash of an older build.
extension EditSession {
    /// The layout a revision recorded. Revisions never change, so a caller may keep it by id.
    public func revisionLayout(_ id: String) async throws(LibraryError) -> KeyboardLayout {
        try await library.layout(ofRevision: id, in: self.id)
    }

    /// Appends a revision of a layout that isn't the document, such as a flash of a build older than the latest edits.
    /// The "Edited" baseline stays, since the document still differs from it.
    @discardableResult
    public func recordRevision(_ draft: RevisionDraft) async throws(LibraryError) -> RevisionSummary {
        let summary = try await library.appendRevision(draft, to: id)
        revisions.append(summary)
        return summary
    }

    /// Makes a revision the document again, as one undoable edit that keeps the title, and records it as a new revision
    /// ("Restored revision 3"), so nothing is lost. Edits since the last revision are checkpointed first. A failure
    /// leaves the document as it was. Undo leaves the appended revisions, as after an import (revisions are append-only).
    public func restoreRevision(_ revision: RevisionSummary) async throws(LibraryError) {
        let recorded = try await revisionLayout(revision.id)
        func restored() -> KeyboardLayout {
            var next = recorded
            next.title = layout.title
            return next
        }
        guard restored() != layout else { return }
        try await checkpoint(String(localized: "Before restoring revision \(revision.number)"))
        // Read after the checkpoint's wait: the title may have changed meanwhile.
        let next = restored()
        let draft = RevisionDraft(source: .save, message: String(localized: "Restored revision \(revision.number)"), layout: next)
        revisions.append(try await library.appendRevision(draft, to: id))
        revisionBaseline = next
        edit(
            String(localized: "Restore Revision"),
            select: { selection, doc in
                selection.layer = min(selection.layer, max(doc.layers.count - 1, 0))
                // Oryx combo ids are positions, so the old id may now name another combo.
                selection.combo = nil
            }
        ) { $0 = next }
    }
}
