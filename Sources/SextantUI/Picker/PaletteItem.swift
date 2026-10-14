import SextantDomain

/// One result row or tile.
struct PaletteItem: Identifiable {
    enum Group {
        case importOryx, suggested, recent, commands, keys, layers, keycodes, settings, documents

        var title: String {
            switch self {
            case .importOryx: String(localized: "Import")
            case .suggested: String(localized: "Suggested for the selected key")
            case .recent: String(localized: "Recent commands")
            case .commands: String(localized: "Commands")
            case .keys: String(localized: "Keys in this layout")
            case .layers: String(localized: "Layers")
            case .keycodes: String(localized: "Keycodes")
            case .settings: String(localized: "Firmware settings")
            case .documents: String(localized: "Documents")
            }
        }
    }

    enum Leading {
        case cap(KeyCapModel)
        case chip(HexColor?)
        case symbol(String)
    }

    var id: String
    var group: Group
    var title: String
    /// Trailing: a shortcut, QMK codes or a setting's value.
    var detail = ""
    /// A second line.
    var note: String?
    var leading: Leading
    /// What a keycode row assigns: the live preview and the ✓ read it.
    var keycode: KeyAction?
    var isCurrent = false
    var perform: @MainActor () -> Void
}
