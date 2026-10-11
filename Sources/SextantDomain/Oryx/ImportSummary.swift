import Foundation

/// What a layout brings in, as the Oryx import preview counts it (spec §8.1: "3 layers, 130 keys, 6 dual-function…").
public struct ImportSummary: Hashable, Sendable {
    public var layers: Int
    /// Keys that aren't transparent, across all layers.
    public var assignedKeys: Int
    /// Keys with both a tap and a hold action.
    public var dualFunctionKeys: Int
    /// Keys with a custom label (shown in Sextant only; labels never reach the firmware).
    public var customLabels: Int
    /// Keys that set an RGB colour.
    public var colorKeys: Int
    /// Actions that play a macro.
    public var macros: Int
    public var combos: Int
    public var navigator: NavigatorConfig?

    public init(_ layout: KeyboardLayout) {
        let keys = layout.layers.flatMap(\.keys)
        layers = layout.layers.count
        assignedKeys = keys.count { !$0.isTransparent }
        dualFunctionKeys = keys.count { $0.tap != nil && $0.hold != nil }
        customLabels = keys.count { !($0.customLabel ?? "").isEmpty }
        colorKeys = keys.count { $0.actions.contains { $0.action.canonicalCode == "RGB" } }
        macros = keys.reduce(0) { $0 + $1.actions.count { $0.action.macro != nil } }
        combos = layout.combos.count
        navigator = layout.navigator
    }
}
