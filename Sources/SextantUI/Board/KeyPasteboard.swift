import AppKit
import SextantApplication
import SextantDomain
import UniformTypeIdentifiers
import os

/// Copied keys on a pasteboard (ADR 0047): a `com.sextant.keys` JSON flavor that pastes back into Sextant, and the
/// keys' QMK expressions as plain text for anywhere else. The board writes through SwiftUI's copy command, which takes
/// item providers; reading goes straight to a pasteboard, so tests use one of their own, never the general one.
enum KeyPasteboard {
    static let type = NSPasteboard.PasteboardType(CopiedKeys.pasteboardType)
    /// Declared in Info.plist; ⌘V is on only while the pasteboard holds this flavor.
    static let utType = UTType(exportedAs: CopiedKeys.pasteboardType, conformingTo: .json)

    /// Both flavors, for `onCopyCommand` and `onCutCommand`; nil when the keys can't be encoded.
    static func itemProvider(_ copied: CopiedKeys) -> NSItemProvider? {
        guard let data = copied.encoded() else { return nil }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: CopiedKeys.pasteboardType, visibility: .all) { done in
            done(data, nil)
            return nil
        }
        let text = Data(copied.qmkExpressions.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { done in
            done(text, nil)
            return nil
        }
        return provider
    }

    /// The keys on `pasteboard`: nil when it holds none, and a ``CopiedKeysError`` when what it holds isn't safe to paste.
    static func read(from pasteboard: NSPasteboard) throws(CopiedKeysError) -> CopiedKeys? {
        guard let data = pasteboard.data(forType: type) else { return nil }
        return try CopiedKeys(data: data)
    }
}

extension LayoutWindowModel {
    /// ⌘C on the board: the selected keys, as an item provider for SwiftUI to put on the pasteboard.
    func copyKeys() -> [NSItemProvider] {
        guard hasSelectedKey, let copied = session?.copiedKeys, let provider = KeyPasteboard.itemProvider(copied) else { return [] }
        return [provider]
    }

    /// ⌘X on the board: copies the selected keys and makes them transparent.
    func cutKeys() -> [NSItemProvider] {
        guard hasSelectedKey, let copied = session?.cutKeys(), let provider = KeyPasteboard.itemProvider(copied) else { return [] }
        return [provider]
    }

    /// ⌘V on the board. False, with a beep in the app, when the pasteboard's keys are refused or don't fit.
    @discardableResult
    func pasteKeys(from pasteboard: NSPasteboard) -> Bool {
        guard page == nil, let session else { return false }
        do {
            guard let copied = try KeyPasteboard.read(from: pasteboard) else { return false }
            return session.pasteKeys(copied)
        } catch {
            // Never log the payload: keys can hold macros, and macros can hold secrets.
            Logger(subsystem: "com.sextant.app", category: "ui").notice(
                "Refused pasted keys: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
