import Foundation

/// The catalog data. Labels, names and keywords are written for Sextant.
/// Codes and aliases are QMK names (public identifiers), plus Oryx/ZSA-specific codes that appear in Oryx JSON.
enum KeycodeTable {
    static func build() -> [KeycodeEntry] {
        var out: [KeycodeEntry] = []
        out += letters()
        out += digits()
        out += modifiers()
        out += punctuation()
        out += navigation()
        out += editing()
        out += functionKeys()
        out += media()
        out += mouse()
        out += lighting()
        out += layers()
        out += system()
        out += international()
        out += numpad()
        out += navigator()
        return out
    }

    private typealias E = KeycodeEntry

    private static func letters() -> [E] {
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { ch in
            E(code: "KC_\(ch)", label: String(ch), name: String(ch), keywords: ["letter \(ch.lowercased())"], category: .letters)
        }
    }

    private static func digits() -> [E] {
        let rows: [(String, String, String)] = [
            ("1", "!", "one"), ("2", "@", "two"), ("3", "#", "three"), ("4", "$", "four"), ("5", "%", "five"),
            ("6", "^", "six"), ("7", "&", "seven"), ("8", "*", "eight"), ("9", "(", "nine"), ("0", ")", "zero"),
        ]
        return rows.map { d, s, w in
            E(code: "KC_\(d)", label: d, name: d, keywords: [w, "number", "digit"], category: .digits, shiftedLabel: s)
        }
    }

    private static func modifiers() -> [E] {
        [
            E(
                code: "KC_LEFT_CTRL", aliases: ["KC_LCTL", "KC_LCTRL"], label: "⌃", name: "Left Control", symbol: "control",
                keywords: ["ctrl", "control"], category: .modifiers, side: .left),
            E(
                code: "KC_LEFT_SHIFT", aliases: ["KC_LSFT", "KC_LSHIFT"], label: "⇧", name: "Left Shift", symbol: "shift",
                keywords: ["shift"], category: .modifiers, side: .left),
            E(
                code: "KC_LEFT_ALT", aliases: ["KC_LALT", "KC_LOPT"], label: "⌥", name: "Left Option", symbol: "option",
                keywords: ["alt", "option", "opt"], category: .modifiers, side: .left),
            E(
                code: "KC_LEFT_GUI", aliases: ["KC_LGUI", "KC_LCMD", "KC_LWIN"], label: "⌘", name: "Left Command", symbol: "command",
                keywords: ["cmd", "command", "gui", "super", "windows"], category: .modifiers, side: .left),
            E(
                code: "KC_RIGHT_CTRL", aliases: ["KC_RCTL", "KC_RCTRL"], label: "⌃", name: "Right Control", symbol: "control",
                keywords: ["ctrl", "control"], category: .modifiers, side: .right),
            E(
                code: "KC_RIGHT_SHIFT", aliases: ["KC_RSFT", "KC_RSHIFT"], label: "⇧", name: "Right Shift", symbol: "shift",
                keywords: ["shift"], category: .modifiers, side: .right),
            E(
                code: "KC_RIGHT_ALT", aliases: ["KC_RALT", "KC_ROPT", "KC_ALGR"], label: "⌥", name: "Right Option", symbol: "option",
                keywords: ["alt", "option", "opt", "altgr"], category: .modifiers, side: .right),
            E(
                code: "KC_RIGHT_GUI", aliases: ["KC_RGUI", "KC_RCMD", "KC_RWIN"], label: "⌘", name: "Right Command", symbol: "command",
                keywords: ["cmd", "command", "gui"], category: .modifiers, side: .right),
            E(
                code: "ALL_T", aliases: ["KC_HYPR", "HYPR_T"], label: "Hyper", name: "Hyper (⌃⌥⇧⌘)", symbol: "command.square",
                keywords: ["hyper", "all modifiers"], category: .modifiers),
            E(
                code: "MEH_T", aliases: ["KC_MEH"], label: "Meh", name: "Meh (⌃⌥⇧)", symbol: "option", keywords: ["meh"],
                category: .modifiers),
            E(
                code: "OSM", label: "One-shot", name: "One-Shot Modifier", symbol: "1.circle", keywords: ["sticky", "oneshot", "osm"],
                category: .modifiers, needsModifiers: true),
            E(
                code: "KC_CAPS", aliases: ["KC_CAPS_LOCK", "KC_CAPSLOCK", "KC_CLCK"], label: "⇪", name: "Caps Lock", symbol: "capslock",
                keywords: ["caps"], category: .modifiers),
            E(
                code: "CW_TOGG", aliases: ["QK_CAPS_WORD_TOGGLE", "CAPS_WORD"], label: "Caps Word", name: "Caps Word",
                symbol: "textformat.size.larger", keywords: ["caps word", "uppercase word"], category: .modifiers),
            E(
                code: "SC_LSPO", aliases: ["KC_LSPO"], label: "⇧(", name: "Left Shift / Open Paren", keywords: ["space cadet", "paren"],
                category: .modifiers, side: .left),
            E(
                code: "SC_RSPC", aliases: ["KC_RSPC"], label: "⇧)", name: "Right Shift / Close Paren", keywords: ["space cadet", "paren"],
                category: .modifiers, side: .right),
            E(
                code: "SC_LCPO", aliases: ["KC_LCPO"], label: "⌃(", name: "Left Control / Open Paren", keywords: ["space cadet"],
                category: .modifiers, side: .left),
            E(
                code: "SC_RCPC", aliases: ["KC_RCPC"], label: "⌃)", name: "Right Control / Close Paren", keywords: ["space cadet"],
                category: .modifiers, side: .right),
            E(
                code: "SC_LAPO", aliases: ["KC_LAPO"], label: "⌥(", name: "Left Option / Open Paren", keywords: ["space cadet"],
                category: .modifiers, side: .left),
            E(
                code: "SC_RAPC", aliases: ["KC_RAPC"], label: "⌥)", name: "Right Option / Close Paren", keywords: ["space cadet"],
                category: .modifiers, side: .right),
            E(
                code: "SC_SENT", aliases: ["KC_SFTENT"], label: "⇧⏎", name: "Right Shift / Return", keywords: ["space cadet", "enter"],
                category: .modifiers, side: .right),
        ]
    }

    private static func punctuation() -> [E] {
        let p: KeycodeCategory = .punctuation
        return [
            E(
                code: "KC_MINUS", aliases: ["KC_MINS"], label: "-", name: "Minus", keywords: ["hyphen", "dash"], category: p,
                shiftedLabel: "_"),
            E(code: "KC_EQUAL", aliases: ["KC_EQL"], label: "=", name: "Equals", keywords: ["equal"], category: p, shiftedLabel: "+"),
            E(
                code: "KC_LBRC", aliases: ["KC_LEFT_BRACKET", "KC_LBRACKET"], label: "[", name: "Left Bracket",
                keywords: ["open bracket", "square"], category: p, shiftedLabel: "{"),
            E(
                code: "KC_RBRC", aliases: ["KC_RIGHT_BRACKET", "KC_RBRACKET"], label: "]", name: "Right Bracket",
                keywords: ["close bracket", "square"], category: p, shiftedLabel: "}"),
            E(
                code: "KC_BSLS", aliases: ["KC_BACKSLASH", "KC_BSLASH"], label: "\\", name: "Backslash", keywords: ["back slash"],
                category: p, shiftedLabel: "|"),
            E(code: "KC_SCLN", aliases: ["KC_SEMICOLON", "KC_SCOLON"], label: ";", name: "Semicolon", category: p, shiftedLabel: ":"),
            E(
                code: "KC_QUOTE", aliases: ["KC_QUOT"], label: "'", name: "Quote", keywords: ["apostrophe", "single quote"], category: p,
                shiftedLabel: "\""),
            E(
                code: "KC_GRAVE", aliases: ["KC_GRV", "KC_ZKHK"], label: "`", name: "Grave Accent", keywords: ["backtick", "backquote"],
                category: p, shiftedLabel: "~"),
            E(code: "KC_COMMA", aliases: ["KC_COMM"], label: ",", name: "Comma", category: p, shiftedLabel: "<"),
            E(
                code: "KC_DOT", aliases: ["KC_PERIOD"], label: ".", name: "Period", keywords: ["dot", "full stop"], category: p,
                shiftedLabel: ">"),
            E(
                code: "KC_SLASH", aliases: ["KC_SLSH"], label: "/", name: "Slash", keywords: ["forward slash"], category: p,
                shiftedLabel: "?"),
            E(code: "KC_NONUS_HASH", aliases: ["KC_NUHS"], label: "#", name: "Non-US Hash", keywords: ["iso", "pound"], category: p),
            E(
                code: "KC_NONUS_BACKSLASH", aliases: ["KC_NUBS", "KC_NONUS_BSLASH"], label: "§", name: "Non-US Backslash (ISO § key)",
                keywords: ["iso", "section"], category: p),
            E(code: "KC_TILD", aliases: ["KC_TILDE"], label: "~", name: "Tilde", category: p),
            E(code: "KC_EXLM", aliases: ["KC_EXCLAIM"], label: "!", name: "Exclamation Mark", keywords: ["bang"], category: p),
            E(code: "KC_AT", label: "@", name: "At Sign", category: p),
            E(code: "KC_HASH", label: "#", name: "Hash", keywords: ["number sign", "pound", "octothorpe"], category: p),
            E(code: "KC_DLR", aliases: ["KC_DOLLAR"], label: "$", name: "Dollar Sign", category: p),
            E(code: "KC_PERC", aliases: ["KC_PERCENT"], label: "%", name: "Percent", category: p),
            E(code: "KC_CIRC", aliases: ["KC_CIRCUMFLEX"], label: "^", name: "Caret", keywords: ["circumflex"], category: p),
            E(code: "KC_AMPR", aliases: ["KC_AMPERSAND"], label: "&", name: "Ampersand", keywords: ["and"], category: p),
            E(code: "KC_ASTR", aliases: ["KC_ASTERISK"], label: "*", name: "Asterisk", keywords: ["star", "times"], category: p),
            E(code: "KC_LPRN", aliases: ["KC_LEFT_PAREN"], label: "(", name: "Left Parenthesis", keywords: ["open paren"], category: p),
            E(code: "KC_RPRN", aliases: ["KC_RIGHT_PAREN"], label: ")", name: "Right Parenthesis", keywords: ["close paren"], category: p),
            E(code: "KC_UNDS", aliases: ["KC_UNDERSCORE"], label: "_", name: "Underscore", category: p),
            E(code: "KC_PLUS", label: "+", name: "Plus", category: p),
            E(
                code: "KC_LCBR", aliases: ["KC_LEFT_CURLY_BRACE"], label: "{", name: "Left Brace", keywords: ["curly", "open brace"],
                category: p),
            E(
                code: "KC_RCBR", aliases: ["KC_RIGHT_CURLY_BRACE"], label: "}", name: "Right Brace", keywords: ["curly", "close brace"],
                category: p),
            E(code: "KC_PIPE", label: "|", name: "Vertical Bar", keywords: ["pipe"], category: p),
            E(code: "KC_COLN", aliases: ["KC_COLON"], label: ":", name: "Colon", category: p),
            E(code: "KC_DQUO", aliases: ["KC_DOUBLE_QUOTE", "KC_DQT"], label: "\"", name: "Double Quote", category: p),
            E(
                code: "KC_LABK", aliases: ["KC_LEFT_ANGLE_BRACKET", "KC_LT"], label: "<", name: "Less Than", keywords: ["angle bracket"],
                category: p),
            E(
                code: "KC_RABK", aliases: ["KC_RIGHT_ANGLE_BRACKET", "KC_GT"], label: ">", name: "Greater Than",
                keywords: ["angle bracket"], category: p),
            E(code: "KC_QUES", aliases: ["KC_QUESTION"], label: "?", name: "Question Mark", category: p),
        ]
    }

    private static func navigation() -> [E] {
        let n: KeycodeCategory = .navigation
        return [
            E(code: "KC_LEFT", label: "←", name: "Left Arrow", symbol: "arrow.left", keywords: ["arrow"], category: n),
            E(code: "KC_DOWN", label: "↓", name: "Down Arrow", symbol: "arrow.down", keywords: ["arrow"], category: n),
            E(code: "KC_UP", label: "↑", name: "Up Arrow", symbol: "arrow.up", keywords: ["arrow"], category: n),
            E(
                code: "KC_RIGHT", aliases: ["KC_RGHT"], label: "→", name: "Right Arrow", symbol: "arrow.right", keywords: ["arrow"],
                category: n),
            E(code: "KC_HOME", label: "↖", name: "Home", symbol: "arrow.up.backward", keywords: ["start", "beginning"], category: n),
            E(code: "KC_END", label: "↘", name: "End", symbol: "arrow.down.forward", keywords: ["finish"], category: n),
            E(
                code: "KC_PAGE_UP", aliases: ["KC_PGUP"], label: "⇞", name: "Page Up", symbol: "arrow.up.to.line",
                keywords: ["pgup", "page"], category: n),
            E(
                code: "KC_PGDN", aliases: ["KC_PAGE_DOWN", "KC_PGDOWN"], label: "⇟", name: "Page Down", symbol: "arrow.down.to.line",
                keywords: ["pgdn", "page"], category: n),
            E(
                code: "KC_WWW_BACK", aliases: ["KC_WBAK"], label: "Back", name: "Browser Back", symbol: "chevron.backward",
                keywords: ["web", "history"], category: n),
            E(
                code: "KC_WWW_FORWARD", aliases: ["KC_WFWD"], label: "Fwd", name: "Browser Forward", symbol: "chevron.forward",
                keywords: ["web", "history"], category: n),
            E(
                code: "KC_WWW_REFRESH", aliases: ["KC_WREF"], label: "Reload", name: "Browser Reload", symbol: "arrow.clockwise",
                keywords: ["web", "refresh"], category: n),
            E(
                code: "KC_WWW_STOP", aliases: ["KC_WSTP"], label: "Stop", name: "Browser Stop", symbol: "xmark", keywords: ["web"],
                category: n),
            E(
                code: "KC_WWW_HOME", aliases: ["KC_WHOM"], label: "Web Home", name: "Browser Home", symbol: "house", keywords: ["web"],
                category: n),
            E(
                code: "KC_WWW_SEARCH", aliases: ["KC_WSCH"], label: "Search", name: "Browser Search", symbol: "magnifyingglass",
                keywords: ["web", "find"], category: n),
            E(
                code: "KC_WWW_FAVORITES", aliases: ["KC_WFAV"], label: "Favs", name: "Browser Favourites", symbol: "star",
                keywords: ["web", "bookmarks"], category: n),
        ]
    }

    private static func editing() -> [E] {
        let e: KeycodeCategory = .editing
        return [
            E(
                code: "KC_ENTER", aliases: ["KC_ENT"], label: "⏎", name: "Return", symbol: "return", keywords: ["enter", "newline"],
                category: e),
            E(
                code: "KC_ESCAPE", aliases: ["KC_ESC"], label: "⎋", name: "Escape", symbol: "escape", keywords: ["esc", "cancel"],
                category: e),
            E(
                code: "KC_BSPC", aliases: ["KC_BACKSPACE", "KC_BSPACE"], label: "⌫", name: "Delete (Backspace)", symbol: "delete.left",
                keywords: ["backspace", "delete", "erase"], category: e),
            E(
                code: "KC_DELETE", aliases: ["KC_DEL"], label: "⌦", name: "Forward Delete", symbol: "delete.right",
                keywords: ["del", "delete forward"], category: e),
            E(code: "KC_TAB", label: "⇥", name: "Tab", symbol: "arrow.right.to.line", keywords: ["indent"], category: e),
            E(
                code: "KC_SPACE", aliases: ["KC_SPC"], label: "␣", name: "Space", symbol: "space", keywords: ["spacebar", "blank"],
                category: e),
            E(code: "KC_INSERT", aliases: ["KC_INS"], label: "Ins", name: "Insert", keywords: ["insert"], category: e),
            E(code: "KC_MAC_COPY", label: "Copy", name: "Copy (⌘C)", symbol: "doc.on.doc", keywords: ["clipboard", "mac"], category: e),
            E(code: "KC_MAC_CUT", label: "Cut", name: "Cut (⌘X)", symbol: "scissors", keywords: ["clipboard", "mac"], category: e),
            E(
                code: "KC_MAC_PASTE", label: "Paste", name: "Paste (⌘V)", symbol: "doc.on.clipboard", keywords: ["clipboard", "mac"],
                category: e),
            E(
                code: "KC_MAC_UNDO", label: "Undo", name: "Undo (⌘Z)", symbol: "arrow.uturn.backward", keywords: ["mac", "revert"],
                category: e),
            E(
                code: "KC_PC_COPY", label: "Copy", name: "Copy (Ctrl+C)", symbol: "doc.on.doc",
                keywords: ["clipboard", "windows", "linux"], category: e),
            E(
                code: "KC_PC_CUT", label: "Cut", name: "Cut (Ctrl+X)", symbol: "scissors", keywords: ["clipboard", "windows", "linux"],
                category: e),
            E(
                code: "KC_PC_PASTE", label: "Paste", name: "Paste (Ctrl+V)", symbol: "doc.on.clipboard",
                keywords: ["clipboard", "windows", "linux"], category: e),
            E(
                code: "KC_PC_UNDO", label: "Undo", name: "Undo (Ctrl+Z)", symbol: "arrow.uturn.backward", keywords: ["windows", "linux"],
                category: e),
            E(code: "KC_FIND", label: "Find", name: "Find (HID)", symbol: "magnifyingglass", keywords: ["search"], category: e),
            E(code: "KC_UNDO", label: "Undo", name: "Undo (HID usage)", symbol: "arrow.uturn.backward", keywords: ["hid"], category: e),
            E(
                code: "KC_AGAIN", aliases: ["KC_AGIN"], label: "Redo", name: "Again / Redo (HID usage)", symbol: "arrow.uturn.forward",
                keywords: ["hid", "redo"], category: e),
            E(code: "KC_CUT", label: "Cut", name: "Cut (HID usage)", symbol: "scissors", keywords: ["hid"], category: e),
            E(code: "KC_COPY", label: "Copy", name: "Copy (HID usage)", symbol: "doc.on.doc", keywords: ["hid"], category: e),
            E(
                code: "KC_PASTE", aliases: ["KC_PSTE"], label: "Paste", name: "Paste (HID usage)", symbol: "doc.on.clipboard",
                keywords: ["hid"], category: e),
            E(
                code: "QK_REP", aliases: ["QK_REPEAT_KEY"], label: "Repeat", name: "Repeat Last Key", symbol: "repeat", keywords: ["again"],
                category: e),
            E(
                code: "QK_AREP", aliases: ["QK_ALT_REPEAT_KEY"], label: "Alt Rep", name: "Alternate Repeat", symbol: "repeat.1",
                keywords: ["reverse repeat"], category: e),
        ]
    }

    private static func functionKeys() -> [E] {
        (1...24).map { i in E(code: "KC_F\(i)", label: "F\(i)", name: "F\(i)", keywords: ["function"], category: .functionKeys) }
    }

    private static func media() -> [E] {
        let m: KeycodeCategory = .media
        return [
            E(
                code: "KC_AUDIO_VOL_UP", aliases: ["KC_VOLU", "KC__VOLUP"], label: "Vol+", name: "Volume Up", symbol: "speaker.wave.3.fill",
                keywords: ["louder", "sound"], category: m),
            E(
                code: "KC_AUDIO_VOL_DOWN", aliases: ["KC_VOLD", "KC__VOLDOWN"], label: "Vol−", name: "Volume Down",
                symbol: "speaker.wave.1.fill", keywords: ["quieter", "sound"], category: m),
            E(
                code: "KC_AUDIO_MUTE", aliases: ["KC_MUTE", "KC__MUTE"], label: "Mute", name: "Mute", symbol: "speaker.slash.fill",
                keywords: ["silence", "sound"], category: m),
            E(
                code: "KC_MEDIA_PLAY_PAUSE", aliases: ["KC_MPLY"], label: "Play", name: "Play / Pause", symbol: "playpause.fill",
                keywords: ["pause", "music"], category: m),
            E(
                code: "KC_MEDIA_NEXT_TRACK", aliases: ["KC_MNXT"], label: "Next", name: "Next Track", symbol: "forward.end.fill",
                keywords: ["skip", "music"], category: m),
            E(
                code: "KC_MEDIA_PREV_TRACK", aliases: ["KC_MPRV"], label: "Prev", name: "Previous Track", symbol: "backward.end.fill",
                keywords: ["back", "music"], category: m),
            E(
                code: "KC_MEDIA_STOP", aliases: ["KC_MSTP"], label: "Stop", name: "Stop", symbol: "stop.fill", keywords: ["music"],
                category: m),
            E(
                code: "KC_MEDIA_FAST_FORWARD", aliases: ["KC_MFFD"], label: "FF", name: "Fast Forward", symbol: "forward.fill",
                keywords: ["seek"], category: m),
            E(
                code: "KC_MEDIA_REWIND", aliases: ["KC_MRWD"], label: "Rew", name: "Rewind", symbol: "backward.fill", keywords: ["seek"],
                category: m),
            E(code: "KC_MEDIA_EJECT", aliases: ["KC_EJCT"], label: "Eject", name: "Eject", symbol: "eject.fill", category: m),
            E(
                code: "KC_MEDIA_SELECT", aliases: ["KC_MSEL"], label: "Media", name: "Media Player", symbol: "music.note",
                keywords: ["music app"], category: m),
            E(
                code: "KC_CALCULATOR", aliases: ["KC_CALC"], label: "Calc", name: "Calculator", symbol: "plus.forwardslash.minus",
                keywords: ["app"], category: m),
            E(code: "KC_MAIL", label: "Mail", name: "Mail", symbol: "envelope", keywords: ["email", "app"], category: m),
            E(
                code: "KC_MY_COMPUTER", aliases: ["KC_MYCM"], label: "Files", name: "File Browser", symbol: "folder",
                keywords: ["finder", "my computer"], category: m),
        ]
    }

    private static func mouse() -> [E] {
        let m: KeycodeCategory = .mouse
        return [
            E(
                code: "KC_MS_UP", aliases: ["KC_MS_U", "MS_UP"], label: "↑", name: "Pointer Up", symbol: "arrow.up.circle",
                keywords: ["mouse", "move", "cursor"], category: m),
            E(
                code: "KC_MS_DOWN", aliases: ["KC_MS_D", "MS_DOWN"], label: "↓", name: "Pointer Down", symbol: "arrow.down.circle",
                keywords: ["mouse", "move", "cursor"], category: m),
            E(
                code: "KC_MS_LEFT", aliases: ["KC_MS_L", "MS_LEFT"], label: "←", name: "Pointer Left", symbol: "arrow.left.circle",
                keywords: ["mouse", "move", "cursor"], category: m),
            E(
                code: "KC_MS_RIGHT", aliases: ["KC_MS_R", "MS_RGHT"], label: "→", name: "Pointer Right", symbol: "arrow.right.circle",
                keywords: ["mouse", "move", "cursor"], category: m),
            E(
                code: "KC_MS_BTN1", aliases: ["KC_BTN1", "MS_BTN1"], label: "Click", name: "Left Click", symbol: "cursorarrow.click",
                keywords: ["mouse", "button 1", "primary"], category: m),
            E(
                code: "KC_MS_BTN2", aliases: ["KC_BTN2", "MS_BTN2"], label: "R-Click", name: "Right Click",
                symbol: "contextualmenu.and.cursorarrow", keywords: ["mouse", "button 2", "secondary", "context"], category: m),
            E(
                code: "KC_MS_BTN3", aliases: ["KC_BTN3", "MS_BTN3"], label: "M-Click", name: "Middle Click", symbol: "computermouse",
                keywords: ["mouse", "button 3", "wheel click"], category: m),
            E(
                code: "KC_MS_BTN4", aliases: ["KC_BTN4", "MS_BTN4"], label: "Btn 4", name: "Mouse Button 4 (Back)",
                symbol: "chevron.backward.circle", keywords: ["mouse", "back"], category: m),
            E(
                code: "KC_MS_BTN5", aliases: ["KC_BTN5", "MS_BTN5"], label: "Btn 5", name: "Mouse Button 5 (Forward)",
                symbol: "chevron.forward.circle", keywords: ["mouse", "forward"], category: m),
            E(
                code: "KC_MS_BTN6", aliases: ["KC_BTN6", "MS_BTN6"], label: "Btn 6", name: "Mouse Button 6", keywords: ["mouse"],
                category: m),
            E(
                code: "KC_MS_BTN7", aliases: ["KC_BTN7", "MS_BTN7"], label: "Btn 7", name: "Mouse Button 7", keywords: ["mouse"],
                category: m),
            E(
                code: "KC_MS_BTN8", aliases: ["KC_BTN8", "MS_BTN8"], label: "Btn 8", name: "Mouse Button 8", keywords: ["mouse"],
                category: m),
            E(
                code: "KC_MS_WH_UP", aliases: ["KC_WH_U", "MS_WHLU"], label: "Scroll ↑", name: "Scroll Up", symbol: "arrow.up.square",
                keywords: ["mouse", "wheel"], category: m),
            E(
                code: "KC_MS_WH_DOWN", aliases: ["KC_WH_D", "MS_WHLD"], label: "Scroll ↓", name: "Scroll Down", symbol: "arrow.down.square",
                keywords: ["mouse", "wheel"], category: m),
            E(
                code: "KC_MS_WH_LEFT", aliases: ["KC_WH_L", "MS_WHLL"], label: "Scroll ←", name: "Scroll Left", symbol: "arrow.left.square",
                keywords: ["mouse", "wheel"], category: m),
            E(
                code: "KC_MS_WH_RIGHT", aliases: ["KC_WH_R", "MS_WHLR"], label: "Scroll →", name: "Scroll Right",
                symbol: "arrow.right.square", keywords: ["mouse", "wheel"], category: m),
            E(
                code: "KC_MS_ACCEL0", aliases: ["KC_ACL0", "MS_ACL0"], label: "Slow", name: "Pointer Speed: Slow", symbol: "tortoise",
                keywords: ["mouse", "acceleration"], category: m),
            E(
                code: "KC_MS_ACCEL1", aliases: ["KC_ACL1", "MS_ACL1"], label: "Medium", name: "Pointer Speed: Medium",
                symbol: "gauge.with.dots.needle.50percent", keywords: ["mouse", "acceleration"], category: m),
            E(
                code: "KC_MS_ACCEL2", aliases: ["KC_ACL2", "MS_ACL2"], label: "Fast", name: "Pointer Speed: Fast", symbol: "hare",
                keywords: ["mouse", "acceleration"], category: m),
            E(
                code: "KC_MS_DBL_CLICK", label: "Dbl Click", name: "Double Click", symbol: "cursorarrow.click.2", keywords: ["mouse"],
                category: m),
            E(
                code: "KC_MS_JIGGLER_TOGGLE", label: "Jiggler", name: "Mouse Jiggler", symbol: "cursorarrow.motionlines",
                keywords: ["keep awake", "caffeinate"], category: m),
        ]
    }

    private static func lighting() -> [E] {
        let l: KeycodeCategory = .lighting
        return [
            E(
                code: "RGB_TOG", aliases: ["RM_TOGG", "UG_TOGG"], label: "RGB", name: "Lighting On/Off", symbol: "lightbulb",
                keywords: ["led", "toggle", "light"], category: l),
            E(
                code: "RGB_MODE_FORWARD", aliases: ["RGB_MOD", "RM_NEXT", "UG_NEXT"], label: "Effect ›", name: "Next Animation",
                symbol: "wand.and.stars", keywords: ["led", "mode", "effect"], category: l),
            E(
                code: "RGB_MODE_REVERSE", aliases: ["RGB_RMOD", "RM_PREV", "UG_PREV"], label: "‹ Effect", name: "Previous Animation",
                symbol: "wand.and.stars.inverse", keywords: ["led", "mode", "effect"], category: l),
            E(
                code: "RGB_SLD", label: "Solid", name: "Solid Colour (Stop Animation)", symbol: "pause.circle",
                keywords: ["led", "static", "still"], category: l),
            E(
                code: "RGB_VAI", aliases: ["RM_VALU", "UG_VALU"], label: "LED+", name: "Lighting Brighter", symbol: "sun.max",
                keywords: ["led", "brightness", "value"], category: l),
            E(
                code: "RGB_VAD", aliases: ["RM_VALD", "UG_VALD"], label: "LED−", name: "Lighting Dimmer", symbol: "sun.min",
                keywords: ["led", "brightness", "value"], category: l),
            E(
                code: "RGB_HUI", aliases: ["RM_HUEU", "UG_HUEU"], label: "Hue+", name: "Hue Forward", symbol: "paintpalette",
                keywords: ["led", "colour", "color"], category: l),
            E(
                code: "RGB_HUD", aliases: ["RM_HUED", "UG_HUED"], label: "Hue−", name: "Hue Back", symbol: "paintpalette",
                keywords: ["led", "colour", "color"], category: l),
            E(
                code: "RGB_SAI", aliases: ["RM_SATU", "UG_SATU"], label: "Sat+", name: "Saturation Up", symbol: "drop.fill",
                keywords: ["led", "saturation"], category: l),
            E(
                code: "RGB_SAD", aliases: ["RM_SATD", "UG_SATD"], label: "Sat−", name: "Saturation Down", symbol: "drop",
                keywords: ["led", "saturation"], category: l),
            E(
                code: "RGB_SPI", aliases: ["RM_SPDU", "UG_SPDU"], label: "Speed+", name: "Animation Faster", symbol: "hare",
                keywords: ["led", "speed"], category: l),
            E(
                code: "RGB_SPD", aliases: ["RM_SPDD", "UG_SPDD"], label: "Speed−", name: "Animation Slower", symbol: "tortoise",
                keywords: ["led", "speed"], category: l),
            E(
                code: "RGB", label: "Colour", name: "Set Colour", symbol: "paintbrush.pointed.fill",
                keywords: ["led", "color", "colour", "paint"], category: l, needsColor: true),
            E(
                code: "TOGGLE_LAYER_COLOR", label: "Layer RGB", name: "Toggle Layer Colours", symbol: "square.3.layers.3d.top.filled",
                keywords: ["led", "layer colours", "per layer"], category: l),
            E(
                code: "LED_LEVEL", aliases: ["MOON_LED_LEVEL"], label: "Status LEDs", name: "Status LED Brightness", symbol: "light.max",
                keywords: ["indicator", "led"], category: l),
        ]
    }

    private static func layers() -> [E] {
        let l: KeycodeCategory = .layers
        return [
            E(
                code: "MO", label: "Hold Layer", name: "Momentary Layer (hold)", symbol: "square.stack.3d.up",
                keywords: ["mo", "while held", "layer"], category: l, needsLayer: true),
            E(
                code: "TG", label: "Toggle Layer", name: "Toggle Layer", symbol: "square.stack.3d.up.fill",
                keywords: ["tg", "layer", "switch"], category: l, needsLayer: true),
            E(
                code: "TO", label: "Go to Layer", name: "Switch to Layer", symbol: "arrow.right.square", keywords: ["to", "layer", "go"],
                category: l, needsLayer: true),
            E(
                code: "TT", label: "Tap-Toggle", name: "Tap-Toggle Layer", symbol: "square.stack.3d.down.right", keywords: ["tt", "layer"],
                category: l, needsLayer: true),
            E(
                code: "OSL", label: "One-shot Layer", name: "One-Shot Layer", symbol: "1.square", keywords: ["osl", "sticky", "layer"],
                category: l, needsLayer: true),
            E(
                code: "LM", label: "Layer + Mods", name: "Layer with Modifiers (hold)", symbol: "square.stack.3d.up.badge.automatic",
                keywords: ["lm", "layer", "modifier"], category: l, needsLayer: true, needsModifiers: true),
            E(
                code: "DF", label: "Base Layer", name: "Set Default Layer", symbol: "house", keywords: ["df", "default"], category: l,
                needsLayer: true),
            E(
                code: "QK_LLCK", aliases: ["QK_LAYER_LOCK"], label: "Lock Layer", name: "Lock Current Layer", symbol: "lock.square.stack",
                keywords: ["layer lock"], category: l),
            E(
                code: "KC_TRANSPARENT", aliases: ["KC_TRNS", "_______"], label: "▽", name: "Transparent (use the layer below)",
                symbol: "arrow.down.to.line", keywords: ["trns", "inherit", "fall through", "blank"], category: l),
            E(
                code: "KC_NO", aliases: ["XXXXXXX"], label: "∅", name: "None (disable key)", symbol: "nosign",
                keywords: ["disable", "nothing", "block", "no"], category: l),
        ]
    }

    private static func system() -> [E] {
        let s: KeycodeCategory = .system
        return [
            E(
                code: "QK_BOOT", aliases: ["QK_BOOTLOADER", "RESET"], label: "Reset", name: "Enter Bootloader (Flash Mode)",
                symbol: "memorychip", keywords: ["bootloader", "flash", "boot", "reset", "firmware"], category: s),
            E(
                code: "QK_RBT", aliases: ["QK_REBOOT"], label: "Reboot", name: "Restart Keyboard", symbol: "arrow.clockwise.circle",
                keywords: ["restart", "firmware"], category: s),
            E(
                code: "EE_CLR", aliases: ["QK_CLEAR_EEPROM", "EEP_RST", "EEPROM_RESET"], label: "Clear EEPROM",
                name: "Clear Stored Settings (EEPROM)", symbol: "eraser", keywords: ["eeprom", "factory", "firmware"], category: s),
            E(
                code: "NK_TOGG", aliases: ["MAGIC_TOGGLE_NKRO", "QK_MAGIC_TOGGLE_NKRO"], label: "NKRO", name: "Toggle N-Key Rollover",
                symbol: "keyboard", keywords: ["rollover", "firmware"], category: s),
            E(
                code: "DB_TOGG", aliases: ["QK_DEBUG_TOGGLE", "DEBUG"], label: "Debug", name: "Toggle Debug Output", symbol: "ladybug",
                keywords: ["console", "firmware"], category: s),
            E(
                code: "DT_UP", aliases: ["QK_DYNAMIC_TAPPING_TERM_UP"], label: "Term+", name: "Tapping Term Longer", symbol: "timer",
                keywords: ["dynamic tapping term"], category: s),
            E(
                code: "DT_DOWN", aliases: ["QK_DYNAMIC_TAPPING_TERM_DOWN"], label: "Term−", name: "Tapping Term Shorter", symbol: "timer",
                keywords: ["dynamic tapping term"], category: s),
            E(
                code: "DT_PRNT", aliases: ["QK_DYNAMIC_TAPPING_TERM_PRINT"], label: "Term?", name: "Type Current Tapping Term",
                symbol: "text.bubble", keywords: ["dynamic tapping term", "print"], category: s),
            E(
                code: "AS_TOGG", aliases: ["KC_ASTG", "QK_AUTO_SHIFT_TOGGLE"], label: "AutoShift", name: "Toggle Auto Shift",
                symbol: "shift", keywords: ["auto shift"], category: s),
            E(
                code: "AS_ON", aliases: ["KC_ASON", "QK_AUTO_SHIFT_ON"], label: "AS On", name: "Auto Shift On", keywords: ["auto shift"],
                category: s),
            E(
                code: "AS_OFF", aliases: ["KC_ASOFF", "QK_AUTO_SHIFT_OFF"], label: "AS Off", name: "Auto Shift Off",
                keywords: ["auto shift"], category: s),
            E(
                code: "AS_UP", aliases: ["KC_ASUP", "QK_AUTO_SHIFT_UP"], label: "AS+", name: "Auto Shift Delay Longer",
                keywords: ["auto shift"], category: s),
            E(
                code: "AS_DOWN", aliases: ["KC_ASDN", "QK_AUTO_SHIFT_DOWN"], label: "AS−", name: "Auto Shift Delay Shorter",
                keywords: ["auto shift"], category: s),
            E(
                code: "AS_RPT", aliases: ["KC_ASRP", "QK_AUTO_SHIFT_REPORT"], label: "AS?", name: "Type Auto Shift Delay",
                keywords: ["auto shift"], category: s),
            E(
                code: "CM_TOGG", aliases: ["CMB_TOG", "QK_COMBO_TOGGLE"], label: "Combos", name: "Toggle Combos", symbol: "link",
                keywords: ["combo"], category: s),
            E(code: "CM_ON", aliases: ["CMB_ON", "QK_COMBO_ON"], label: "Combos On", name: "Combos On", keywords: ["combo"], category: s),
            E(
                code: "CM_OFF", aliases: ["CMB_OFF", "QK_COMBO_OFF"], label: "Combos Off", name: "Combos Off", keywords: ["combo"],
                category: s),
            E(
                code: "DM_REC1", aliases: ["DYN_REC_START1", "QK_DYNAMIC_MACRO_RECORD_START_1"], label: "Rec 1", name: "Record Macro 1",
                symbol: "record.circle", keywords: ["dynamic macro"], category: s),
            E(
                code: "DM_REC2", aliases: ["DYN_REC_START2", "QK_DYNAMIC_MACRO_RECORD_START_2"], label: "Rec 2", name: "Record Macro 2",
                symbol: "record.circle", keywords: ["dynamic macro"], category: s),
            E(
                code: "DM_PLY1", aliases: ["DYN_MACRO_PLAY1", "QK_DYNAMIC_MACRO_PLAY_1"], label: "Play 1", name: "Play Macro 1",
                symbol: "play.circle", keywords: ["dynamic macro"], category: s),
            E(
                code: "DM_PLY2", aliases: ["DYN_MACRO_PLAY2", "QK_DYNAMIC_MACRO_PLAY_2"], label: "Play 2", name: "Play Macro 2",
                symbol: "play.circle", keywords: ["dynamic macro"], category: s),
            E(
                code: "DM_RSTP", aliases: ["DYN_REC_STOP", "QK_DYNAMIC_MACRO_RECORD_STOP"], label: "Stop Rec", name: "Stop Recording",
                symbol: "stop.circle", keywords: ["dynamic macro"], category: s),
            E(
                code: "KC_BRIGHTNESS_UP", aliases: ["KC_BRIU", "KC_BRMU"], label: "Bright+", name: "Display Brighter",
                symbol: "sun.max.fill", keywords: ["screen", "display"], category: s),
            E(
                code: "KC_BRIGHTNESS_DOWN", aliases: ["KC_BRID", "KC_BRMD"], label: "Bright−", name: "Display Dimmer",
                symbol: "sun.min.fill", keywords: ["screen", "display"], category: s),
            E(code: "MAC_LOCK", label: "Lock", name: "Lock Screen", symbol: "lock.fill", keywords: ["mac", "security"], category: s),
            E(
                code: "MAC_SPOTLIGHT", label: "Spotlight", name: "Spotlight", symbol: "magnifyingglass", keywords: ["mac", "search"],
                category: s),
            E(
                code: "MAC_MISSION_CONTROL", aliases: ["KC_MISSION_CONTROL", "KC_MCTL"], label: "Mission", name: "Mission Control",
                symbol: "rectangle.3.group", keywords: ["mac", "spaces", "expose"], category: s),
            E(
                code: "KC_LAUNCHPAD", aliases: ["KC_LPAD"], label: "Apps", name: "Launchpad / Apps", symbol: "square.grid.3x3",
                keywords: ["mac", "applications"], category: s),
            E(code: "MAC_SIRI", label: "Dictate", name: "Dictation", symbol: "mic.fill", keywords: ["mac", "voice", "siri"], category: s),
            E(
                code: "MAC_DND", label: "Focus", name: "Do Not Disturb", symbol: "moon.fill", keywords: ["mac", "focus", "notifications"],
                category: s),
            E(
                code: "KC_SYSTEM_POWER", aliases: ["KC_PWR"], label: "Power", name: "Power", symbol: "power", keywords: ["shutdown"],
                category: s),
            E(
                code: "KC_SYSTEM_SLEEP", aliases: ["KC_SLEP"], label: "Sleep", name: "Sleep", symbol: "moon.zzz", keywords: ["suspend"],
                category: s),
            E(
                code: "KC_SYSTEM_WAKE", aliases: ["KC_WAKE"], label: "Wake", name: "Wake", symbol: "sun.horizon", keywords: ["resume"],
                category: s),
            E(
                code: "KC_PSCR", aliases: ["KC_PRINT_SCREEN", "KC_PSCREEN"], label: "PrtSc", name: "Print Screen",
                symbol: "camera.viewfinder", keywords: ["screenshot", "f13"], category: s),
            E(
                code: "KC_SCRL", aliases: ["KC_SCROLL_LOCK", "KC_SLCK", "KC_SCROLLLOCK"], label: "ScrLk", name: "Scroll Lock",
                keywords: ["f14"], category: s),
            E(
                code: "KC_PAUSE", aliases: ["KC_PAUS", "KC_BRK"], label: "Pause", name: "Pause / Break", keywords: ["break", "f15"],
                category: s),
            E(
                code: "KC_APPLICATION", aliases: ["KC_APP"], label: "Menu", name: "Context Menu Key", symbol: "filemenu.and.selection",
                keywords: ["application", "menu"], category: s),
            E(
                code: "WEBUSB_PAIR", label: "Pair", name: "Pair with Web Configurator", symbol: "link.circle",
                keywords: ["webusb", "live", "pairing"], category: s),
            E(
                code: "ORYX_SL_TOGG", label: "App Layers", name: "Toggle App-Aware Layers", symbol: "app.badge",
                keywords: ["smart layer", "app"], category: s),
            E(
                code: "ORYX_SL_TRIGG", label: "App Layer", name: "Trigger App-Aware Layer", symbol: "app.badge.checkmark",
                keywords: ["smart layer", "app"], category: s),
        ]
    }

    private static func international() -> [E] {
        let i: KeycodeCategory = .international
        let ints: [(Int, String, String)] = [
            (1, "ろ", "JIS Ro"), (2, "かな", "JIS Katakana/Hiragana"), (3, "¥", "JIS Yen"), (4, "変換", "JIS Henkan"),
            (5, "無変換", "JIS Muhenkan"), (6, "Int 6", "JIS Numpad Comma"), (7, "Int 7", "International 7"),
            (8, "Int 8", "International 8"), (9, "Int 9", "International 9"),
        ]
        let langs: [(Int, String, String)] = [
            (1, "かな", "Kana (Mac) / Han-Yeong"), (2, "英数", "Eisu (Mac) / Hanja"), (3, "Katakana", "Katakana"),
            (4, "Hiragana", "Hiragana"), (5, "Zen/Han", "Zenkaku/Hankaku"), (6, "Lang 6", "Language 6"),
            (7, "Lang 7", "Language 7"), (8, "Lang 8", "Language 8"), (9, "Lang 9", "Language 9"),
        ]
        // Common locale-specific codes seen in public Voyager layouts (QMK keymap_extras names).
        let locale: [(String, String, String)] = [
            ("UK_PND", "£", "Pound Sign (UK)"), ("UK_EURO", "€", "Euro Sign (UK)"), ("UK_AT", "@", "At Sign (UK)"),
            ("UK_DLR", "$", "Dollar Sign (UK)"), ("UK_GRV", "`", "Grave Accent (UK)"), ("UK_HASH", "#", "Hash (UK)"),
            ("UK_MINS", "-", "Minus (UK)"), ("UK_PERC", "%", "Percent (UK)"), ("UK_PIPE", "|", "Vertical Bar (UK)"),
            ("UK_TILD", "~", "Tilde (UK)"), ("UK_DQUO", "\"", "Double Quote (UK)"), ("UK_NOT", "¬", "Not Sign (UK)"),
            ("US_AACU", "á", "A Acute (US Intl)"), ("US_EACU", "é", "E Acute (US Intl)"), ("US_IACU", "í", "I Acute (US Intl)"),
            ("US_OACU", "ó", "O Acute (US Intl)"), ("US_UACU", "ú", "U Acute (US Intl)"), ("US_UDIA", "ü", "U Diaeresis (US Intl)"),
            ("US_NTIL", "ñ", "N Tilde (US Intl)"), ("US_CCED", "ç", "C Cedilla (US Intl)"), ("US_EURO", "€", "Euro Sign (US Intl)"),
        ]
        let localeEntries = locale.map { code, label, name in
            E(
                code: code, label: label, name: name,
                keywords: ["accent", "locale", code.hasPrefix("UK") ? "british" : "us international"], category: i)
        }
        return localeEntries
            + ints.map { n, label, name in
                E(
                    code: "KC_INTERNATIONAL_\(n)",
                    aliases: ["KC_INT\(n)"]
                        + (n == 1
                            ? ["KC_RO"] : n == 2 ? ["KC_KANA"] : n == 3 ? ["KC_JYEN"] : n == 4 ? ["KC_HENK"] : n == 5 ? ["KC_MHEN"] : []),
                    label: label, name: "International \(n) (\(name))", keywords: ["international", "jis", "japanese"], category: i)
            }
            + langs.map { n, label, name in
                E(
                    code: "KC_LANGUAGE_\(n)", aliases: ["KC_LNG\(n)", "KC_LANG\(n)"], label: label, name: "Language \(n) (\(name))",
                    keywords: ["language", "ime", "input source"], category: i)
            }
    }

    private static func numpad() -> [E] {
        let n: KeycodeCategory = .numpad
        var out: [E] = [
            E(
                code: "KC_NUM_LOCK", aliases: ["KC_NUM", "KC_NUMLOCK", "KC_NLCK"], label: "Num", name: "Num Lock / Clear",
                symbol: "number.square", keywords: ["keypad", "clear"], category: n),
            E(code: "KC_KP_SLASH", aliases: ["KC_PSLS"], label: "/", name: "Keypad Divide", keywords: ["keypad", "divide"], category: n),
            E(
                code: "KC_KP_ASTERISK", aliases: ["KC_PAST"], label: "*", name: "Keypad Multiply", keywords: ["keypad", "times"],
                category: n),
            E(code: "KC_KP_MINUS", aliases: ["KC_PMNS"], label: "-", name: "Keypad Minus", keywords: ["keypad", "subtract"], category: n),
            E(code: "KC_KP_PLUS", aliases: ["KC_PPLS"], label: "+", name: "Keypad Plus", keywords: ["keypad", "add"], category: n),
            E(
                code: "KC_KP_ENTER", aliases: ["KC_PENT"], label: "⌤", name: "Keypad Enter", symbol: "return",
                keywords: ["keypad", "return"], category: n),
            E(
                code: "KC_KP_DOT", aliases: ["KC_PDOT"], label: ".", name: "Keypad Decimal Point", keywords: ["keypad", "period"],
                category: n),
            E(code: "KC_KP_EQUAL", aliases: ["KC_PEQL"], label: "=", name: "Keypad Equals", keywords: ["keypad"], category: n),
            E(code: "KC_KP_COMMA", aliases: ["KC_PCMM"], label: ",", name: "Keypad Comma", keywords: ["keypad"], category: n),
        ]
        for d in 0...9 {
            out.append(
                E(
                    code: "KC_KP_\(d)", aliases: ["KC_P\(d)"], label: "\(d)", name: "Keypad \(d)", keywords: ["keypad", "numpad"],
                    category: n))
        }
        return out
    }

    private static func navigator() -> [E] {
        let n: KeycodeCategory = .navigator
        return [
            E(
                code: "NAVIGATOR_AIM", label: "Aim", name: "Aim (precise, while held)", symbol: "scope",
                keywords: ["trackball", "precision", "slow"], category: n),
            E(
                code: "NAVIGATOR_TURBO", label: "Turbo", name: "Turbo (fast, while held)", symbol: "hare.fill",
                keywords: ["trackball", "speed"], category: n),
            E(
                code: "DRAG_SCROLL", label: "Drag Scroll", name: "Drag Scroll (while held)", symbol: "hand.draw",
                keywords: ["scroll", "trackball", "trackpad"], category: n),
            E(code: "TOGGLE_AIM", label: "Aim ⇄", name: "Toggle Aim", symbol: "scope", keywords: ["trackball"], category: n),
            E(code: "TOGGLE_TURBO", label: "Turbo ⇄", name: "Toggle Turbo", symbol: "hare", keywords: ["trackball"], category: n),
            E(
                code: "TOGGLE_SCROLL", label: "Scroll ⇄", name: "Toggle Scroll Mode", symbol: "scroll",
                keywords: ["trackball", "trackpad"], category: n),
            E(
                code: "NV_VSCR", label: "V-Scroll", name: "Vertical Scroll Lock", symbol: "arrow.up.and.down",
                keywords: ["scroll", "vertical"], category: n),
            E(
                code: "NAVIGATOR_INC_CPI", label: "CPI+", name: "Increase Sensitivity", symbol: "plus.circle",
                keywords: ["dpi", "cpi", "sensitivity"], category: n),
            E(
                code: "NAVIGATOR_DEC_CPI", label: "CPI−", name: "Decrease Sensitivity", symbol: "minus.circle",
                keywords: ["dpi", "cpi", "sensitivity"], category: n),
            E(
                code: "NAVIGATOR_CLEAR_SPEED", label: "Speed ⟲", name: "Reset Aim/Turbo Speed", symbol: "gauge.with.dots.needle.50percent",
                keywords: ["normal speed"], category: n),
        ]
    }
}
