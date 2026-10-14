import Foundation

/// One app's rule (spec §8.6): while the app is frontmost, the keyboard is on the rule's layer. Kept beside the layout,
/// never in it, so a rule edit changes no content hash or firmware fingerprint (ADR 0054).
public struct AppLayerRule: Identifiable, Hashable, Sendable, Codable {
    /// What happens when another app comes forward that has no rule of its own.
    public enum Leaving: String, Hashable, Sendable, Codable, CaseIterable {
        /// The keyboard goes back to layer 0.
        case returnToMain
        /// The keyboard stays on the rule's layer.
        case stay
    }

    public var bundleID: String
    /// The app's name as it was added; the switch history and the table show it.
    public var name: String
    /// The layer's id, so the rule follows the layer when layers move.
    public var layerID: String
    public var leaving: Leaving
    public var isEnabled: Bool

    public var id: String { bundleID }

    public init(bundleID: String, name: String, layerID: String, leaving: Leaving = .returnToMain, isEnabled: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.layerID = layerID
        self.leaving = leaving
        self.isEnabled = isEnabled
    }
}

/// A layout's App Layers: the master switch and one rule per app.
public struct AppLayerRules: Hashable, Sendable, Codable {
    /// "Switch layers when you change apps". Off until the user turns it on: with at least one enabled rule, that is the
    /// consent to change the keyboard's layer without a click each time (ADR 0054).
    public var isOn: Bool
    public var rules: [AppLayerRule]

    public init(isOn: Bool = false, rules: [AppLayerRule] = []) {
        self.isOn = isOn
        self.rules = rules
    }

    /// The switch is on and a rule is enabled: an app switch may move the keyboard.
    public var isActive: Bool { isOn && rules.contains(where: \.isEnabled) }

    public func rule(for bundleID: String) -> AppLayerRule? { rules.first { $0.bundleID == bundleID } }

    /// Adds a rule for an app that has none; false when it already has one.
    @discardableResult
    public mutating func add(_ rule: AppLayerRule) -> Bool {
        guard self.rule(for: rule.bundleID) == nil else { return false }
        rules.append(rule)
        return true
    }

    /// Replaces the rule for the same app; nothing when it has none.
    public mutating func update(_ rule: AppLayerRule) {
        guard let index = rules.firstIndex(where: { $0.bundleID == rule.bundleID }) else { return }
        rules[index] = rule
    }

    public mutating func remove(_ bundleID: String) { rules.removeAll { $0.bundleID == bundleID } }

    /// Where the rule's layer is in `layout`; nil when the layout has no such layer (deleted, or not flashed yet).
    public static func layerIndex(of rule: AppLayerRule, in layout: KeyboardLayout) -> Int? {
        layout.layers.firstIndex { $0.id == rule.layerID }
    }

    /// The layer the keyboard moves to when `activated` comes forward after `previous`; nil when nothing is sent.
    ///
    /// - The activated app's enabled rule wins, when `layout` (the layout on the keyboard) has its layer.
    /// - Otherwise, leaving an app whose enabled rule says Return to Main goes back to layer 0, if that rule could have
    ///   moved the keyboard (its layer is in `layout`).
    /// - Otherwise the keyboard stays. A rule whose layer `layout` lacks counts as no rule: nothing is sent for a layer
    ///   the keyboard may not have.
    public func target(activated: String, previous: String?, in layout: KeyboardLayout) -> Int? {
        guard isOn else { return nil }
        if let rule = applicable(activated, in: layout), let index = Self.layerIndex(of: rule, in: layout) { return index }
        guard let previous, previous != activated, let left = applicable(previous, in: layout), left.leaving == .returnToMain else {
            return nil
        }
        return 0
    }

    private func applicable(_ bundleID: String, in layout: KeyboardLayout) -> AppLayerRule? {
        rule(for: bundleID).flatMap { $0.isEnabled && Self.layerIndex(of: $0, in: layout) != nil ? $0 : nil }
    }
}
