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
    ///   - oryxLayoutID: the layout's Oryx id, when it came from Oryx.
    public init(serial: String, expected: FirmwareIdentity, libraryID: UUID, oryxLayoutID: String?) {
        if serial == expected.serial {
            self = .current
        } else if serial.hasPrefix(FirmwareIdentity.sextantPrefix(libraryID)) || oryxLayoutID.map({ serial.hasPrefix($0 + "/") }) == true {
            self = .thisLayout
        } else {
            self = .otherLayout
        }
    }
}

extension LibraryEntry {
    /// A keyboard reporting `serial` runs a build of this layout: Oryx's (`layoutId/…`) or Sextant's (`sx-<id>-…`).
    public func isOnKeyboard(serial: String) -> Bool {
        if case let .oryx(layoutId, _) = origin, serial.hasPrefix(layoutId + "/") { return true }
        return serial.hasPrefix(FirmwareIdentity.sextantPrefix(id))
    }
}

extension FirmwareIdentity {
    /// The identity a build of `layout` gets.
    /// - Parameter importedLayout: the layout of the latest import revision (``importedLayout(of:revisions:library:)``).
    public init(layout: KeyboardLayout, libraryID: UUID, importedLayout: KeyboardLayout?) {
        // Macro drafts are never compiled (ADR 0042), so they don't change what a build calls itself.
        var layout = layout
        var importedLayout = importedLayout
        layout.macroDrafts = []
        importedLayout?.macroDrafts = []
        if let oryx = layout.oryx, layout == importedLayout {
            self.init(serial: oryx.serial)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // shortcut: encoding only fails on NaN settings, which JSON imports can't produce; upgrade if a UI can set one.
        let json = (try? encoder.encode(layout)) ?? Data()
        self.init(serial: Self.sextantPrefix(libraryID) + String(format: "%08X", FirmwareImage.crc(json)))
    }

    /// The generator accepts only `[A-Za-z0-9/_-]` in a serial, and a `/` would read as an Oryx serial.
    static func sextantPrefix(_ libraryID: UUID) -> String { "sx-\(libraryID.uuidString.prefix(8))-" }

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
    /// import revision whose Oryx serial it is, or the newest flash revision whose Sextant serial it is. Nil when none
    /// matches; unreadable revisions are skipped. A serial that can't be this layout's reads nothing.
    public static func revision(
        runningSerial serial: String, of id: UUID, origin: LayoutOrigin, revisions: [RevisionSummary], library: any LayoutLibrary
    ) async -> (summary: RevisionSummary, layout: KeyboardLayout)? {
        let source: RevisionSource
        if serial.hasPrefix(sextantPrefix(id)) {
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
            // Edited layouts keep their Oryx info, so only an import's Oryx serial names it; a Sextant serial depends on
            // content alone, so no import baseline is needed.
            let built = source == .import ? layout.oryx?.serial : Self(layout: layout, libraryID: id, importedLayout: nil).serial
            if built == serial { return (summary, layout) }
        }
        return nil
    }

    private static let log = Logger(subsystem: "com.sextant.app", category: "application")
}
