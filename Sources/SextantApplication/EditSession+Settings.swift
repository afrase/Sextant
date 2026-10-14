import Foundation
import SextantDomain

extension EditSession {
    /// Puts every firmware setting Sextant offers back to its default as one undo step, "Reset Firmware Settings".
    /// Settings it doesn't offer keep their imported values (``KeyboardLayout/keptSettings(in:)``).
    public func resetSettings(catalog: SettingsCatalog = .voyager) {
        edit(String(localized: "Reset Firmware Settings")) { doc in
            for setting in doc.changedSettings(in: catalog) { doc.store(nil, for: setting) }
        }
    }
}
