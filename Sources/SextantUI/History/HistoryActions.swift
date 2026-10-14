import SextantApplication
import SextantDomain

/// What History can do with the revision it shows (spec §8.7, ADR 0043): Restore, Compare, Flash This Revision… and
/// Export Source Zip…, from the inspector, the menus and the palette alike.
extension LayoutWindowModel {
    /// The revision History shows, while the page is up: what the menus' and the palette's History commands act on.
    var shownRevision: RevisionSummary? { page == .history ? history?.selected : nil }

    /// A flash is writing, from this window or another: Restore and Flash This Revision wait until it ends.
    var isFlashWriting: Bool { buildFlash?.canStop == false || live?.isWritingFirmware == true }

    // MARK: Restore

    func canRestore(_ revision: RevisionSummary) -> Bool {
        guard let history else { return false }
        return history.canRestore(revision) && !history.isRestoring && !isFlashWriting
    }

    func restore(_ revision: RevisionSummary) async {
        guard canRestore(revision) else { return }
        await history?.restore(revision)
    }

    // MARK: Flash This Revision

    /// The revision with its layout, once History has loaded it.
    func revisionLayout(_ revision: RevisionSummary) -> RevisionLayout? {
        history?.layouts[revision.id].map { RevisionLayout(revision: revision, layout: $0) }
    }

    func canFlash(_ revision: RevisionSummary) -> Bool { canBuild && !isFlashWriting && revisionLayout(revision) != nil }

    /// Builds the revision as it was recorded and flashes it through Build & Flash, which records the flash as a new
    /// revision.
    func flash(_ revision: RevisionSummary) {
        guard canFlash(revision), let target = revisionLayout(revision) else { return }
        build(.buildAndFlash, revision: target)
    }

    // MARK: Export Source Zip

    func canExportSource(of revision: RevisionSummary) -> Bool { revisionLayout(revision).map { canExport(.revisionSource($0)) } ?? false }

    /// The QMK source a build of the revision compiles, zipped, through File ▸ Export (ADR 0044).
    func exportSource(of revision: RevisionSummary) async {
        guard let target = revisionLayout(revision) else { return }
        await export(.revisionSource(target))
    }

    // MARK: Firmware size

    /// Reads the shown revision's firmware size for its delta; the inspector reads it again once a flash is recorded.
    func loadFirmwareSize() async {
        guard let history, let revision = history.selected, let buildFlash else { return }
        let size = await buildFlash.firmwareSize(of: revision)
        if history.selected?.id == revision.id { history.firmware = (revision.id, size) }
    }

    /// The palette's History commands, while History shows a revision (spec §11: every action has a menu or command).
    func historyPaletteCommands(_ add: (_ title: String, _ enabled: Bool, _ run: @escaping @MainActor () -> Void) -> Void) {
        guard let revision = shownRevision, let history else { return }
        add(String(localized: "Restore This Revision"), canRestore(revision)) { Task { await self.restore(revision) } }
        add(String(localized: "Flash This Revision…"), canFlash(revision)) { self.flash(revision) }
        add(String(localized: "Export Source Zip…"), canExportSource(of: revision)) { Task { await self.exportSource(of: revision) } }
        for comparison in [HistoryModel.Comparison.parent, .current, .onKeyboard] {
            add(
                String(localized: "Compare with: \(history.title(comparison))"),
                history.comparison != comparison && history.canCompare(with: comparison)
            ) { history.comparison = comparison }
        }
    }
}
