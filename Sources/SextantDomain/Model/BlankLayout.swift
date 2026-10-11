import Foundation

extension KeyboardLayout {
    /// A one-layer QWERTY layout for the ZSA Voyager, authored by Sextant (spec §12.1 "Start from a blank QWERTY
    /// layout"). Keys follow the board's index order: each half's four rows of six, then its two thumb keys.
    public static func blankQWERTY(title: String) -> Self {
        let left = [
            "KC_ESCAPE", "KC_1", "KC_2", "KC_3", "KC_4", "KC_5",
            "KC_TAB", "KC_Q", "KC_W", "KC_E", "KC_R", "KC_T",
            "KC_LEFT_CTRL", "KC_A", "KC_S", "KC_D", "KC_F", "KC_G",
            "KC_LEFT_SHIFT", "KC_Z", "KC_X", "KC_C", "KC_V", "KC_B",
            "KC_LEFT_GUI", "KC_SPACE",
        ]
        let right = [
            "KC_6", "KC_7", "KC_8", "KC_9", "KC_0", "KC_MINUS",
            "KC_Y", "KC_U", "KC_I", "KC_O", "KC_P", "KC_BSLS",
            "KC_H", "KC_J", "KC_K", "KC_L", "KC_SCLN", "KC_QUOTE",
            "KC_N", "KC_M", "KC_COMMA", "KC_DOT", "KC_SLASH", "KC_RIGHT_SHIFT",
            "KC_ENTER", "KC_BSPC",
        ]
        let main = Layer(title: String(localized: "Main"), keys: (left + right).map { Key($0) })
        return Self(title: title, layers: [main], swatch: defaultSwatch)
    }
}
