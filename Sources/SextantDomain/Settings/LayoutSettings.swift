import Foundation

extension Setting {
    /// What a layout that stores nothing for this setting gets: the default, or off for a toggleable slider (Oryx keeps
    /// `flowTap: 100`, its value when switched on, and the firmware writes `FLOW_TAP_TERM` only when it is stored).
    public var unsetValue: SettingValue? { isToggleable ? nil : defaultValue }

    /// The unit as shown after a value: ms, s, min, °, or nothing.
    public var unitSymbol: String {
        switch unit {
        case "milliseconds", "ms": "ms"
        case "seconds": "s"
        case "minutes": "min"
        case "degrees": "°"
        default: ""
        }
    }

    /// Navigator settings live with the Navigator (Oryx's `navigators`), the rest in the layout's config.
    var isNavigatorOption: Bool { navigatorKinds != nil }
}

extension KeyboardLayout {
    /// The value stored for a setting; nil means ``Setting/unsetValue``.
    public func storedValue(of setting: Setting) -> SettingValue? {
        setting.isNavigatorOption ? navigator?.options[setting.id] : settings[setting.id]
    }

    /// Stores a setting sparsely, as Oryx does: the unset value is removed. A Navigator setting needs a Navigator.
    /// Settings that go together change together, as in Oryx (``Coupling``).
    public mutating func store(_ value: SettingValue?, for setting: Setting) {
        // JSON can't hold NaN or infinity: one stored would make every later save of the layout fail.
        if case let .number(n)? = value, !n.isFinite { return }
        let stored = value == setting.unsetValue ? nil : value
        if setting.isNavigatorOption { navigator?.options[setting.id] = stored } else { settings[setting.id] = stored }
        couple(setting.id)
    }

    /// Whether this layout shows `setting`: one Sextant offers (``SettingsCatalog/offers(_:)``), for this layout's
    /// Navigator, and with the setting it depends on set. The Firmware Settings page, its filters and the changed counts
    /// all follow this, so a value counted as changed always has a row to change it from.
    public func offers(_ setting: Setting, in catalog: SettingsCatalog = .voyager) -> Bool {
        guard catalog.offers(setting) else { return false }
        if let kinds = setting.navigatorKinds, !kinds.contains(navigator?.kind.rawValue ?? "") { return false }
        guard let dependency = setting.dependsOn, let other = catalog.setting(id: dependency.id) else { return true }
        return (storedValue(of: other) ?? other.unsetValue) == dependency.value
    }

    /// Settings this layout shows whose stored value differs from their unset value (the Firmware Settings badge and
    /// Changed list).
    public func changedSettings(in catalog: SettingsCatalog = .voyager) -> [Setting] {
        catalog.allSettings.filter { offers($0, in: catalog) && isChanged($0) }
    }

    /// Stored values that differ from their unset value but that this layout doesn't show: a setting Sextant doesn't
    /// offer, another Navigator's option, or one whose setting it depends on is off. Kept in the layout (for Oryx, or
    /// for when they apply again); Sextant's builds don't use them.
    public func keptSettings(in catalog: SettingsCatalog = .voyager) -> [Setting] {
        catalog.allSettings.filter { !offers($0, in: catalog) && isChanged($0) }
    }

    private func isChanged(_ setting: Setting) -> Bool { storedValue(of: setting).map { $0 != setting.unsetValue } ?? false }

    /// Whether the keycode picker offers `code`: a locale's codes only while its International toggle is on (only the
    /// locales Sextant has codes for show; ``SettingsCatalog/localeCodePrefixes``).
    public func offersKeycode(_ code: String) -> Bool {
        SettingsCatalog.localeCodePrefixes.allSatisfy { id, prefix in !code.hasPrefix(prefix) || settings[id] == .bool(true) }
    }

    // MARK: Coupling

    /// Settings Oryx changes together (spec §8.8), so a layout edited in Sextant reads the same in Oryx.
    public enum Coupling {
        /// A tapping term above this turns on Permissive hold.
        public static let permissiveHoldTerm = 500.0
        /// The Auto Shift key groups that switch Auto Shift off when all are off (Tab isn't one of them).
        static let autoShiftGroups = ["autoshiftEnableSpecial", "autoshiftEnableNumeric", "autoshiftEnableAlpha"]
    }

    /// Applies the coupling rules after `id` changed. Values stay sparse: on is stored, a default (off, or on for the
    /// key groups) is removed.
    private mutating func couple(_ id: String) {
        switch id {
        case "tappingTerm":
            if let term = settings[id]?.doubleValue, term > Coupling.permissiveHoldTerm { settings["permissiveHold"] = .bool(true) }
        case "chordalHold":
            settings["chordalHoldExcludeThumbs"] = settings[id] == .bool(true) ? .bool(true) : nil
        case "autoshift":
            if settings[id] == .bool(true), !anyAutoShiftGroupOn {
                for group in Coupling.autoShiftGroups { settings[group] = nil }
            }
        case _ where Coupling.autoShiftGroups.contains(id):
            if !anyAutoShiftGroupOn { settings["autoshift"] = nil }
        default: break
        }
    }

    private var anyAutoShiftGroupOn: Bool { Coupling.autoShiftGroups.contains { settings[$0]?.boolValue ?? true } }
}
