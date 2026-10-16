import Foundation
import SextantDomain
import os

// The firmware identity rule (for an ADR): what a build calls itself, and how a keyboard's serial is recognised.
//
// 1. A layout imported from Oryx and still equal to its latest import revision builds with Oryx's own
//    `layoutId/revisionId` serial. The build is equivalent to Oryx's, so Keymapp, zapp and Oryx keep working.
// 2. Anything else builds with `sx-<library id, 8 hex>-<content fingerprint, 8 hex>`. The fingerprint is the
//    DFU-suffix CRC (reflected CRC-32 without the final XOR, `FirmwareImage.crc`) of the layout's canonical
//    (sorted-keys) JSON, so the same content always gets the same serial, and LiveSession can tell "runs exactly
//    this" from "runs an older build of this layout" without any lookup.
//    There is no "/" in it, so tools that read Oryx serials see non-Oryx firmware instead of asking Oryx for a
//    layout that isn't there. It is 20 ASCII characters: it fits QMK's USB serial and the 30-byte raw-HID reply.
// 3. A layout has other library ids on other Macs (its aliases, ADR 0061): a Sextant serial naming one of them is this
//    layout too, and the same fingerprint from any of them is the same content.

/// How a keyboard's firmware relates to a layout, judged from the serial the keyboard reports.
public enum FirmwareMatch: Hashable, Sendable {
    /// A build of exactly this layout as it is now.
    case current
    /// Another build of this layout: an earlier version, or Oryx's build from before later edits.
    case thisLayout
    /// Another layout, or firmware Sextant doesn't recognise.
    case otherLayout

    /// - Parameters:
    ///   - expected: the identity the layout builds to now.
    ///   - aliases: the layout's library ids on other Macs (``LibraryEntry/aliases``): their builds are this layout's, and
    ///     one with the expected fingerprint is this content, flashed from another Mac.
    ///   - oryxLayoutID: the layout's Oryx id, when it came from Oryx.
    public init(serial: String, expected: FirmwareIdentity, libraryID: UUID, aliases: Set<UUID> = [], oryxLayoutID: String?) {
        let names = FirmwareIdentity.sextantSerial(serial, names: aliases.union([libraryID]))
        let fingerprint = FirmwareIdentity.sextantFingerprint(of: serial)
        let sameContent = fingerprint != nil && fingerprint == FirmwareIdentity.sextantFingerprint(of: expected.serial)
        if serial == expected.serial || (names && sameContent) {
            self = .current
        } else if names || oryxLayoutID.map({ serial.hasPrefix($0 + "/") }) == true {
            self = .thisLayout
        } else {
            self = .otherLayout
        }
    }
}

extension LibraryEntry {
    /// A keyboard reporting `serial` runs a build of this layout: Oryx's (`layoutId/…`) or Sextant's (`sx-<id>-…`), from
    /// this Mac or, through an alias, another.
    public func isOnKeyboard(serial: String) -> Bool {
        if case let .oryx(layoutId, _) = origin, serial.hasPrefix(layoutId + "/") { return true }
        return FirmwareIdentity.sextantSerial(serial, names: aliases.union([id]))
    }
}

extension FirmwareIdentity {
    /// The identity a build of `layout` gets.
    /// - Parameter importedLayout: the layout of the latest import revision (``importedLayout(of:revisions:library:)``).
    public init(layout: KeyboardLayout, libraryID: UUID, importedLayout: KeyboardLayout?) {
        // Macro drafts are never compiled (ADR 0042), so they don't change what a build calls itself.
        var built = layout
        var imported = importedLayout
        built.macroDrafts = []
        imported?.macroDrafts = []
        if let oryx = built.oryx, built == imported {
            self.init(serial: oryx.serial)
            return
        }
        self.init(serial: Self.sextantPrefix(libraryID) + Self.fingerprint(of: layout))
    }

    /// The generator accepts only `[A-Za-z0-9/_-]` in a serial, and a `/` would read as an Oryx serial.
    static func sextantPrefix(_ libraryID: UUID) -> String { "sx-\(libraryID.uuidString.prefix(8))-" }

    // shortcut: firmwareJSON is empty only on NaN settings, which JSON imports can't produce; upgrade if a UI can set one.
    /// A Sextant serial's fingerprint of `layout`: the CRC of ``KeyboardLayout/firmwareJSON()`` as 8 hex digits.
    static func fingerprint(of layout: KeyboardLayout) -> String { String(format: "%08X", FirmwareImage.crc(layout.firmwareJSON())) }

    /// The content fingerprint in a Sextant serial (`sx-<id, 8>-<fingerprint, 8>`): the 8 hex digits after the id. Nil for
    /// any other serial.
    public static func sextantFingerprint(of serial: String) -> String? {
        let parts = serial.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "sx", parts[1].count == 8 else { return nil }
        let fingerprint = parts[2]
        return fingerprint.count == 8 && fingerprint.allSatisfy(\.isHexDigit) ? String(fingerprint) : nil
    }

    /// Whether `serial` is a Sextant build of a layout with one of `ids` (an entry's id and its aliases).
    public static func sextantSerial(_ serial: String, names ids: Set<UUID>) -> Bool {
        ids.contains { serial.hasPrefix(sextantPrefix($0)) }
    }

    /// The layout of the latest import revision, which the rule compares against. Nil when there is none or it
    /// can't be read; the rule then falls back to a Sextant serial, which is always safe.
    public static func importedLayout(of id: UUID, revisions: [RevisionSummary], library: any LayoutLibrary) async -> KeyboardLayout? {
        guard let revision = revisions.last(where: { $0.source == .import }) else { return nil }
        do {
            return try await library.layout(ofRevision: revision.id, in: id)
        } catch {
            log.error("Import revision unreadable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The revision of a library layout that a keyboard reporting `serial` runs, with its layout (ADR 0039): the newest
    /// import revision whose Oryx serial it is, or the newest flash revision with its Sextant serial's fingerprint, when the
    /// serial names the layout's id or one of its `aliases` (the same content flashed from another Mac, ADR 0061). Nil
    /// when none matches; unreadable revisions are skipped. A serial that can't be this layout's reads nothing.
    public static func revision(
        runningSerial serial: String, of id: UUID, aliases: Set<UUID> = [], origin: LayoutOrigin, revisions: [RevisionSummary],
        library: any LayoutLibrary
    ) async -> (summary: RevisionSummary, layout: KeyboardLayout)? {
        let source: RevisionSource
        let serialFingerprint = sextantFingerprint(of: serial)
        if serialFingerprint != nil, sextantSerial(serial, names: aliases.union([id])) {
            source = .flash
        } else if case let .oryx(layoutId, _) = origin, serial.hasPrefix(layoutId + "/") {
            source = .import
        } else {
            return nil
        }
        for summary in revisions.reversed() where summary.source == source {
            let layout: KeyboardLayout
            do {
                layout = try await library.layout(ofRevision: summary.id, in: id)
            } catch {
                log.error("Revision unreadable: \(String(describing: error), privacy: .public)")
                continue
            }
            // Edited layouts keep their Oryx info, so only an import's Oryx serial names it; a Sextant serial's fingerprint
            // depends on content alone, so no import baseline is needed.
            let matches = source == .import ? layout.oryx?.serial == serial : fingerprint(of: layout) == serialFingerprint
            if matches { return (summary, layout) }
        }
        return nil
    }

    /// This identity with the layout record a build of `layout` stores (ADR 0061), naming the layout's library ids: its
    /// own first, then its aliases. Without one when the record would be too large; the serial is the same either way.
    public func storingRecord(of layout: KeyboardLayout, libraryID: UUID, aliases: Set<UUID>) -> FirmwareIdentity {
        let ids = [libraryID] + aliases.subtracting([libraryID]).sorted { $0.uuidString < $1.uuidString }
        let record = LayoutRecord(layout: layout, libraryIDs: ids)
        do {
            _ = try record.encoded()
        } catch {
            // The error names a size or a version, never the layout.
            Self.log.error("Building without the layout record: \(String(describing: error), privacy: .public)")
            return self
        }
        var identity = self
        identity.record = record
        return identity
    }

    private static let log = Logger(subsystem: "com.sextant.app", category: "application")
}
