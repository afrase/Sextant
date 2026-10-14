import Foundation

/// Why pasteboard data isn't keys Sextant will paste (ADR 0047).
public enum CopiedKeysError: Error, Equatable, Sendable {
    /// More than ``CopiedKeys/maxBytes``.
    case tooLarge
    /// Not JSON of the keys format, or a key that doesn't decode.
    case malformed
    /// A format version this build doesn't read.
    case unsupportedVersion(Int)
    /// No keys, more keys than the board has, or a key count no board has.
    case badKeyCount
    /// An index outside the board, or the same index twice.
    case badIndex(Int)
    /// A keycode that isn't a QMK identifier, or a layer outside QMK's 32.
    case badAction(index: Int)
}

/// Keys copied from a layout (⌘C or ⌘X on the board, ADR 0047): each key as stored, by its board index, with the board
/// they came from. The pasteboard is outside Sextant's control, so ``init(data:)`` checks everything before a key can
/// reach a layout: the size, the board's key count, each index, and each keycode and layer; labels, descriptions, macro
/// names and waits, and tapping terms are clamped to what Sextant itself allows. A macro keeps all its steps: Oryx
/// layouts hold macros longer than the 24 steps Sextant's editor makes (JRGQm has one of 25).
public struct CopiedKeys: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var index: Int
        public var key: Key

        public init(index: Int, key: Key) {
            self.index = index
            self.key = key
        }
    }

    /// The pasteboard type of the JSON flavor.
    public static let pasteboardType = "com.sextant.keys"
    /// The most data ``init(data:)`` reads: a full layer of 24-step macros in every slot fits with room to spare.
    public static let maxBytes = 1 << 20
    static let formatVersion = 1
    /// QMK supports 32 layers.
    static let layerRange = 0...31
    static let maxCodeLength = 64
    static let labelLength = 10
    static let descriptionLength = 30
    static let macroNameLength = 64

    /// The board's name (`voyager`).
    public var board: String
    public var keyCount: Int
    /// The keys by ascending index, each index once.
    public var entries: [Entry]

    public init(board: String, keyCount: Int, entries: [Entry]) {
        self.board = board
        self.keyCount = keyCount
        self.entries = entries.sorted { $0.index < $1.index }
    }

    /// The keys at `indices` on a layer, as stored; nil when none of them is on it.
    public init?(layout: KeyboardLayout, layer: Int, indices: [Int]) {
        let entries = Set(indices).compactMap { i in layout.key(layer: layer, index: i).map { Entry(index: i, key: $0) } }
        guard !entries.isEmpty else { return nil }
        self.init(board: layout.geometry, keyCount: layout.keyCount, entries: entries)
    }

    /// The keys' QMK expressions in index order, for the plain-text flavor: `LT(1, KC_ENTER), KC_TRNS`.
    public var qmkExpressions: String { entries.map { Legends.qmkExpression(for: $0.key) }.joined(separator: ", ") }

    /// True when the keys can go back to the same places on `layout`: the same board, so each index is the same key.
    public func fitsPositions(of layout: KeyboardLayout) -> Bool { board == layout.geometry && keyCount == layout.keyCount }

    /// The keys ready for a layout with `layerCount` layers: a layer action whose layer it lacks does nothing (`KC_NO`),
    /// as after Delete Layer.
    public func entries(forLayerCount layerCount: Int) -> [Entry] {
        entries.map { entry in
            var entry = entry
            for slot in KeySlot.allCases {
                guard let action = entry.key[slot], action.isLayerAction, let layer = action.layer, layer >= layerCount else { continue }
                entry.key[slot] = KeyAction.none
            }
            return entry
        }
    }

    // MARK: JSON

    private struct Payload: Codable {
        struct Item: Codable {
            var index: Int
            var key: Key
        }

        var format: String
        var version: Int
        var board: String
        var keyCount: Int
        var keys: [Item]
    }

    /// The JSON flavor; nil only if a key can't be encoded.
    public func encoded() -> Data? {
        let payload = Payload(
            format: Self.pasteboardType, version: Self.formatVersion, board: board, keyCount: keyCount,
            keys: entries.map { Payload.Item(index: $0.index, key: $0.key) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(payload)
    }

    /// Reads and checks the JSON flavor.
    public init(data: Data) throws(CopiedKeysError) {
        guard data.count <= Self.maxBytes else { throw .tooLarge }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw .malformed
        }
        guard payload.format == Self.pasteboardType else { throw .malformed }
        guard payload.version == Self.formatVersion else { throw .unsupportedVersion(payload.version) }
        // No board has more keys than a full-size keyboard; the cap keeps a hostile count from meaning anything.
        guard (1...256).contains(payload.keyCount), (1...payload.keyCount).contains(payload.keys.count) else { throw .badKeyCount }
        var seen = Set<Int>()
        var entries: [Entry] = []
        for item in payload.keys {
            guard (0..<payload.keyCount).contains(item.index), seen.insert(item.index).inserted else { throw .badIndex(item.index) }
            guard let key = Self.checked(item.key) else { throw .badAction(index: item.index) }
            entries.append(Entry(index: item.index, key: key))
        }
        self.init(board: String(payload.board.prefix(Self.maxCodeLength)), keyCount: payload.keyCount, entries: entries)
    }

    /// The key with its text clamped, or nil when an action holds what no layout may: a code that isn't a QMK
    /// identifier (it would land in generated C) or a layer outside QMK's range.
    private static func checked(_ key: Key) -> Key? {
        var key = key
        for slot in KeySlot.allCases {
            guard var action = key[slot] else { continue }
            guard isIdentifier(action.code), action.layer.map(layerRange.contains) ?? true else { return nil }
            action.description = clamped(action.description, to: descriptionLength)
            if var macro = action.macro {
                guard macro.steps.allSatisfy({ isIdentifier($0.code) }) else { return nil }
                for i in macro.steps.indices { macro.steps[i].delay = min(max(macro.steps[i].delay, 0), Macro.maxDelay) }
                macro.name = clamped(macro.name, to: macroNameLength)
                action.macro = macro
            }
            key[slot] = action
        }
        key.customLabel = clamped(key.customLabel, to: labelLength)
        key.tappingTerm = key.tappingTerm.flatMap { KeyboardLayout.tappingTermRange.contains($0) ? $0 : nil }
        return key
    }

    private static func isIdentifier(_ code: String) -> Bool {
        (1...maxCodeLength).contains(code.utf8.count)
            && code.utf8.allSatisfy {
                $0 == UInt8(ascii: "_") || (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
            }
    }

    private static func clamped(_ text: String?, to length: Int) -> String? { text.map { String($0.prefix(length)) } }
}
