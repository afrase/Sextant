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
    public mutating func store(_ value: SettingValue?, for setting: Setting) {
        // JSON can't hold NaN or infinity: one stored would make every later save of the layout fail.
        if case let .number(n)? = value, !n.isFinite { return }
        let stored = value == setting.unsetValue ? nil : value
        if setting.isNavigatorOption { navigator?.options[setting.id] = stored } else { settings[setting.id] = stored }
    }

    /// Settings whose stored value differs from their unset value (the Firmware Settings badge and Changed list).
    public func changedSettings(in catalog: SettingsCatalog = .voyager) -> [Setting] {
        catalog.allSettings.filter { s in storedValue(of: s).map { $0 != s.unsetValue } ?? false }
    }
}
