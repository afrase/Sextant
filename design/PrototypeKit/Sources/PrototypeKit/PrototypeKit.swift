import Foundation

// # PrototypeKit
//
// Shared, visually neutral foundation for Sextant's competing UI directions. Utilities only: no
// colours, fonts or component styling. Every type is documented in place; this is the map.
//
// ## Model (Model/)
// - `KeyboardLayout` ← Oryx JSON (`KeyboardLayout(oryxJSON:)`), `Layer`, `Key`, `KeyAction`, `Macro`, `Combo`, `Modifiers`, `HexColor`.
// - `Key.kind` → `KeyKind` (regular, modifier, multiFunction, tapDance, ledControl, macro, customLabel, layerKey, transparent, none).
// - `KeyboardLayout.resolvedKey(layer:index:)` → transparent fall-through; `KeyboardLayout.keysActivating(layer:)`.
// - `KeyboardLayout.moveLayer/removeLayer` keep layer references valid; `KeyboardLayout.diff(from:)` → per-key `LayoutDiff`.
//
// ## Legends (Legends/)
// - `Legends.legend(for:layerNames:)` → `KeyLegend` (primary/secondary `ActionLegend`: text, SF Symbol, side, QMK).
// - `Legends.legend(layout:layer:index:)` resolves transparency first (`isInherited` → render dimmed).
// - `KeycodeCatalog` (≈300 entries, 15 categories, aliases) with `search(_:)` fuzzy matching.
//
// ## Geometry (Geometry/)
// - `BoardGeometry.voyager` in key units; `.layout(keySize:spacing:)` / `.layout(fitting:)` → point frames,
//   halves, bounds, hit testing, Navigator anchor.
//
// ## Mock data (Samples/)
// - `Samples.layout` (the user's real layout), `MockDevice` (live layer + pressed keys, scripted),
//   `Samples.heatmap`, `Samples.appRules`, `Samples.history`, `Samples.macros`, `Samples.combos`,
//   `BuildFlashSimulator` + `BuildFlashState`, `Samples.oryxImport`, `SettingsCatalog.voyager`.
//
// ## Editor (Editor/)
// - `EditorStore`: @Observable document + selection + undoable edits through `UndoManager`.
//
// ## Snapshots (Snapshot/)
// - `SnapshotScene` + `SnapshotRunner.run(scenes:outputDirectory:)`, `SnapshotRunner.handleCommandLine(_:)`
//   for `--snapshot <dir>`. In-process rendering only: no TCC prompts, no visible windows.
//   Read the header of Snapshot/SnapshotRunner.swift for fidelity limits.

/// Version of the PrototypeKit API. Bump the minor version for additive changes only.
public enum PrototypeKit {
    public static let version = "1.0.0"
}

/// Access to the JSON files bundled with PrototypeKit.
public enum PrototypeResources {
    /// `Resources/my-layout-KlgM7-40xJ7M.json`: the user's Oryx layout (layout KlgM7, revision 40xJ7M).
    public static var userLayoutURL: URL { url("my-layout-KlgM7-40xJ7M") }
    /// `Resources/voyager-geometry.json`: Voyager geometry research file (Oryx CSS model, QMK units, LED coordinates).
    public static var geometryURL: URL { url("voyager-geometry") }
    /// `Resources/settings-catalog.json`: trimmed firmware settings catalog with Sextant's own text.
    public static var settingsCatalogURL: URL { url("settings-catalog") }

    static func url(_ name: String) -> URL {
        guard let u = Bundle.module.url(forResource: name, withExtension: "json") else {
            fatalError("PrototypeKit: missing bundled resource \(name).json")
        }
        return u
    }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
}
