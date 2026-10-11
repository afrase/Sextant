import Foundation

extension Setting {
    /// What a layout that stores nothing for this setting gets: the default, or off for a toggleable slider (Oryx keeps
    /// `flowTap: 100`, its value when switched on, and the firmware writes `FLOW_TAP_TERM` only when it is stored).
    public var unsetValue: SettingValue? { isToggleable ? nil : defaultValue }

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
        let stored = value == setting.unsetValue ? nil : value
        if setting.isNavigatorOption { navigator?.options[setting.id] = stored } else { settings[setting.id] = stored }
    }

    /// Settings whose stored value differs from their unset value (the Firmware Settings badge and Changed list).
    public func changedSettings(in catalog: SettingsCatalog = .voyager) -> [Setting] {
        catalog.allSettings.filter { s in storedValue(of: s).map { $0 != s.unsetValue } ?? false }
    }
}
