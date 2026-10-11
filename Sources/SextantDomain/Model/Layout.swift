import Foundation

/// A layer: a title, an optional colour, and one ``Key`` per physical key (52 on the Voyager).
public struct Layer: Identifiable, Hashable, Sendable {
    /// Stable identity (Oryx layer `hashId` when imported).
    public var id: String
    public var title: String
    /// Layer colour (Oryx shows it as a glow on keys of non-base layers; firmware uses it as the layer LED map).
    public var color: HexColor?
    public var keys: [Key]

    public init(id: String = UUID().uuidString, title: String, color: HexColor? = nil, keys: [Key]) {
        self.id = id
        self.title = title
        self.color = color
        self.keys = keys
    }

    /// A layer whose keys are all transparent.
    public static func transparent(title: String, color: HexColor? = nil, keyCount: Int = BoardDefinition.voyager.keyCount) -> Layer {
        Layer(title: title, color: color, keys: Array(repeating: .transparent, count: keyCount))
    }
}

/// A combo: pressing all of ``keyIndices`` together sends ``output``.
public struct Combo: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String?
    /// Key indices (2...6 keys).
    public var keyIndices: [Int]
    /// Restrict to one layer; nil means every layer.
    public var layer: Int?
    public var output: KeyAction

    public init(id: String = UUID().uuidString, name: String? = nil, keyIndices: [Int], layer: Int? = nil, output: KeyAction) {
        self.id = id
        self.name = name
        self.keyIndices = keyIndices
        self.layer = layer
        self.output = output
    }
}

/// The Navigator pointing device attached to one half (the user's board has a trackpad on the right).
public struct NavigatorConfig: Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable { case trackpad, trackball, knob }
    public enum Side: String, Sendable, Hashable { case left, right }
    public var kind: Kind
    public var side: Side
    /// Non-default Navigator options as stored by Oryx (e.g. `tap`, `scrollInertia`).
    public var options: [String: SettingValue]

    public init(kind: Kind, side: Side, options: [String: SettingValue] = [:]) {
        self.kind = kind
        self.side = side
        self.options = options
    }
}

/// Where an imported layout came from on Oryx (read-only provenance; never sent back).
public struct OryxRevisionInfo: Hashable, Sendable {
    /// Oryx layout hash id, e.g. `KlgM7`.
    public var layoutId: String
    /// Oryx revision hash id, e.g. `40xJ7M`.
    public var revisionId: String
    /// Firmware line Oryx compiled it with, e.g. `25.0` (`qmkVersion`).
    public var firmwareVersion: String?
    /// md5 of Oryx's compiled binary for this revision.
    public var md5: String?
    /// Oryx's `createdAt`, kept as the string Oryx wrote ("2026-09-16 05:08:01 UTC").
    public var createdAt: String?
    /// Revision message (Oryx revision `title`).
    public var message: String?

    public init(
        layoutId: String, revisionId: String, firmwareVersion: String? = nil, md5: String? = nil,
        createdAt: String? = nil, message: String? = nil
    ) {
        self.layoutId = layoutId
        self.revisionId = revisionId
        self.firmwareVersion = firmwareVersion
        self.md5 = md5
        self.createdAt = createdAt
        self.message = message
    }

    /// `layout/revision`, the form the keyboard reports as its USB serial.
    public var serial: String { "\(layoutId)/\(revisionId)" }
}

/// A complete keyboard layout: the document content Sextant edits, stores and builds.
public struct KeyboardLayout: Hashable, Sendable {
    public var title: String
    /// Board name; `voyager` for the user's board.
    public var geometry: String
    public var layers: [Layer]
    public var combos: [Combo]
    /// Sparse firmware settings: only values that differ from the catalog default (Oryx convention).
    public var settings: [String: SettingValue]
    public var navigator: NavigatorConfig?
    /// The layout's colour swatches (up to 10), user data.
    public var swatch: [HexColor]
    /// Set when the layout was imported from Oryx.
    public var oryx: OryxRevisionInfo?

    public init(
        title: String, geometry: String = "voyager", layers: [Layer], combos: [Combo] = [],
        settings: [String: SettingValue] = [:], navigator: NavigatorConfig? = nil, swatch: [HexColor] = [],
        oryx: OryxRevisionInfo? = nil
    ) {
        self.title = title
        self.geometry = geometry
        self.layers = layers
        self.combos = combos
        self.settings = settings
        self.navigator = navigator
        self.swatch = swatch
        self.oryx = oryx
    }

    /// Number of keys per layer.
    public var keyCount: Int { layers.first?.keys.count ?? board?.keyCount ?? 0 }

    /// The board this layout is for, when Sextant knows it (ADR 0017).
    public var board: BoardDefinition? { BoardDefinition.named(geometry) }

    /// Layer titles by index.
    public var layerNames: [String] { layers.map(\.title) }

    /// Safe key lookup.
    public func key(layer: Int, index: Int) -> Key? {
        guard layers.indices.contains(layer), layers[layer].keys.indices.contains(index) else { return nil }
        return layers[layer].keys[index]
    }

    /// Mutating access to one key (no-op when out of range).
    public mutating func updateKey(layer: Int, index: Int, _ body: (inout Key) -> Void) {
        guard layers.indices.contains(layer), layers[layer].keys.indices.contains(index) else { return }
        body(&layers[layer].keys[index])
    }

    /// Effective value of a firmware setting (sparse override, else the catalog default).
    public func settingValue(_ id: String, catalog: SettingsCatalog = .voyager) -> SettingValue? {
        settings[id] ?? catalog.setting(id: id)?.defaultValue
    }
}

// MARK: - Transparent resolution

/// The key that actually acts at a position, after following transparent keys downwards.
public struct ResolvedKey: Hashable, Sendable {
    /// The key as stored on the requested layer.
    public var own: Key
    /// The key that acts (equal to ``own`` unless ``isInherited``).
    public var effective: Key
    /// Layer the effective key lives on; nil when nothing below defines it (falls through to "nothing").
    public var sourceLayer: Int?
    /// True when ``own`` is transparent and ``effective`` came from a lower layer.
    public var isInherited: Bool
    public var layer: Int
    public var index: Int
}

extension KeyboardLayout {
    /// Resolves transparency for one key.
    ///
    /// QMK looks through *active* layers from the highest down. With `activeLayers == nil` this assumes
    /// `{0, layer}`, i.e. the layer was reached from the base layer (e.g. holding MO(2) on Main). That is
    /// what Oryx shows: on Brd+Sys a transparent key displays Main's legend even though Sym+Num sits in between.
    /// Pass an explicit set to model stacked layers.
    public func resolvedKey(layer: Int, index: Int, activeLayers: Set<Int>? = nil) -> ResolvedKey {
        let own = key(layer: layer, index: index) ?? .transparent
        guard own.isTransparent else {
            return ResolvedKey(own: own, effective: own, sourceLayer: layer, isInherited: false, layer: layer, index: index)
        }
        let active = activeLayers ?? [0, layer]
        for l in stride(from: layer - 1, through: 0, by: -1) where active.contains(l) {
            if let k = key(layer: l, index: index), !k.isTransparent {
                return ResolvedKey(own: own, effective: k, sourceLayer: l, isInherited: true, layer: layer, index: index)
            }
        }
        return ResolvedKey(own: own, effective: own, sourceLayer: nil, isInherited: false, layer: layer, index: index)
    }

    /// Resolved keys for a whole layer, by key index.
    public func resolvedKeys(layer: Int, activeLayers: Set<Int>? = nil) -> [ResolvedKey] {
        (0..<keyCount).map { resolvedKey(layer: layer, index: $0, activeLayers: activeLayers) }
    }

    /// Keys on other layers whose actions lead to `layer` (e.g. the thumb key that holds MO(1)).
    /// Oryx hatches such a key while showing the target layer.
    public func keysActivating(layer target: Int) -> [(layer: Int, index: Int, slot: KeySlot, action: KeyAction)] {
        var out: [(Int, Int, KeySlot, KeyAction)] = []
        for (li, l) in layers.enumerated() where li != target {
            for (ki, k) in l.keys.enumerated() {
                for (slot, a) in k.actions where a.isLayerAction && a.layer == target { out.append((li, ki, slot, a)) }
            }
        }
        return out.map { (layer: $0.0, index: $0.1, slot: $0.2, action: $0.3) }
    }
}

// MARK: - Layer operations (used by EditorStore; usable directly)

extension KeyboardLayout {
    /// Applies `map` to every layer reference in keys, combos and Navigator options. Returning nil from `map`
    /// (a deleted layer) turns a key action into `KC_NO`, removes combos limited to that layer and drops it from
    /// Navigator layer lists.
    public mutating func remapLayerReferences(_ map: (Int) -> Int?) {
        func fix(_ a: inout KeyAction?) {
            guard var act = a, act.isLayerAction, let l = act.layer else { return }
            if let n = map(l) { act.layer = n } else { act = KeyAction.none }
            a = act
        }
        for li in layers.indices {
            for ki in layers[li].keys.indices {
                for slot in KeySlot.allCases { fix(&layers[li].keys[ki][slot]) }
            }
        }
        // A combo limited to a deleted layer goes with it (nil would mean "every layer").
        combos.removeAll { combo in combo.layer.map { map($0) == nil } ?? false }
        for ci in combos.indices {
            var out: KeyAction? = combos[ci].output
            fix(&out)
            combos[ci].output = out ?? KeyAction.none
            combos[ci].layer = combos[ci].layer.flatMap(map)
        }
        // Navigator options that name layers (aim, turbo, drag-scroll, automouse) follow too.
        if var options = navigator?.options {
            for (id, value) in options {
                switch value {
                case let .integers(list) where id.hasSuffix("Layers"): options[id] = .integers(list.compactMap(map))
                case let .number(n) where id == "automouseLayer": options[id] = map(Int(n)).map { .number(Double($0)) }
                default: break
                }
            }
            navigator?.options = options
        }
    }

    /// Moves a layer and keeps every MO/TG/TO/... reference pointing at the same layer.
    /// The base layer (index 0) can be moved too, though firmware always starts on index 0.
    public mutating func moveLayer(from source: Int, to destination: Int) {
        guard layers.indices.contains(source), layers.indices.contains(destination), source != destination else { return }
        var order = Array(layers.indices)
        let moved = order.remove(at: source)
        order.insert(moved, at: destination)
        // order[newIndex] = oldIndex
        var newIndexOf = [Int: Int]()
        for (newIndex, oldIndex) in order.enumerated() { newIndexOf[oldIndex] = newIndex }
        layers = order.map { layers[$0] }
        remapLayerReferences { newIndexOf[$0] }
    }

    /// Removes a layer. References to it become `KC_NO`; references above it shift down.
    public mutating func removeLayer(at index: Int) {
        guard layers.indices.contains(index), layers.count > 1 else { return }
        layers.remove(at: index)
        remapLayerReferences { l in l == index ? nil : (l > index ? l - 1 : l) }
    }
}

// MARK: - Diff

/// One changed key between two layouts.
public struct KeyChange: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable { case added, removed, modified }
    public var id: String { "\(layerID)-\(index)" }
    /// Layer index in the *new* layout (or old one for removed layers).
    public var layer: Int
    public var layerID: String
    public var index: Int
    public var before: Key?
    public var after: Key?
    public var kind: Kind
    /// Slots whose action changed.
    public var changedSlots: [KeySlot]
    public var labelChanged: Bool
    public var colorChanged: Bool
}

/// A layer whose title changed between two layouts.
public struct LayerRename: Hashable, Sendable {
    public var id: String
    public var from: String
    public var to: String
}

/// The difference between two layouts, matched by layer id then key index.
public struct LayoutDiff: Hashable, Sendable {
    public var keyChanges: [KeyChange]
    public var addedLayers: [Layer]
    public var removedLayers: [Layer]
    public var renamedLayers: [LayerRename]
    /// Ids of layers whose colour changed.
    public var recoloredLayers: [String]
    public var isEmpty: Bool {
        keyChanges.isEmpty && addedLayers.isEmpty && removedLayers.isEmpty && renamedLayers.isEmpty && recoloredLayers.isEmpty
    }

    /// Changes on one layer index of the new layout.
    public func changes(onLayer layer: Int) -> [KeyChange] { keyChanges.filter { $0.layer == layer } }
}

extension KeyboardLayout {
    /// Key-by-key difference from `old` to `self`, matching layers by id.
    public func diff(from old: KeyboardLayout) -> LayoutDiff {
        var changes: [KeyChange] = []
        var renamed: [LayerRename] = []
        var recolored: [String] = []
        let oldByID = Dictionary(old.layers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newIDs = Set(layers.map(\.id))
        for (li, layer) in layers.enumerated() {
            guard let prev = oldByID[layer.id] else { continue }
            if prev.title != layer.title { renamed.append(LayerRename(id: layer.id, from: prev.title, to: layer.title)) }
            if prev.color != layer.color { recolored.append(layer.id) }
            for ki in 0..<max(layer.keys.count, prev.keys.count) {
                let a = prev.keys.indices.contains(ki) ? prev.keys[ki] : nil
                let b = layer.keys.indices.contains(ki) ? layer.keys[ki] : nil
                guard a != b else { continue }
                let slots = KeySlot.allCases.filter { a?[$0] != b?[$0] }
                let wasEmpty = a?.isTransparent ?? true, isEmpty = b?.isTransparent ?? true
                let kind: KeyChange.Kind = wasEmpty && !isEmpty ? .added : !wasEmpty && isEmpty ? .removed : .modified
                changes.append(
                    KeyChange(
                        layer: li, layerID: layer.id, index: ki, before: a, after: b, kind: kind,
                        changedSlots: slots, labelChanged: a?.customLabel != b?.customLabel,
                        colorChanged: a?.glowColor != b?.glowColor || a?.tap?.color != b?.tap?.color))
            }
        }
        return LayoutDiff(
            keyChanges: changes,
            addedLayers: layers.filter { oldByID[$0.id] == nil },
            removedLayers: old.layers.filter { !newIDs.contains($0.id) },
            renamedLayers: renamed,
            recoloredLayers: recolored)
    }
}

extension KeyboardLayout {
    /// Sextant's own 10 swatches for new layouts (spec §10.1: not Oryx's set).
    public static let defaultSwatch: [HexColor] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE", "#30B0C7", "#007AFF", "#5856D6", "#AF52DE", "#FF2D55",
    ].compactMap(HexColor.init(hex:))
}
