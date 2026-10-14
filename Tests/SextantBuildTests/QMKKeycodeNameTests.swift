import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// Every catalog code and alias the generator accepts comes out of it as a name the pinned QMK declares: a legacy
/// spelling QMK has dropped (`KC_BSPACE`, `KC_LCTRL`, `KC_LSPO`) is written as the catalog's own code, which it declares.
/// LayoutIssues passes those spellings, so writing them as stored failed the build after the live check said it was fine.
struct QMKKeycodeNameTests {
    static let identity = FirmwareIdentity(serial: "sx-names")
    static let codes = KeycodeCatalog.entries.flatMap { [$0.code] + $0.aliases }

    /// A blank layout with the setting-gated families switched on, so their keys build.
    static func layout(_ key: Key, combo output: KeyAction? = nil) -> KeyboardLayout {
        var layout = KeyboardLayout.blankQWERTY(title: "Names")
        layout.settings["enableSpaceCadet"] = .bool(true)
        layout.settings["autoshift"] = .bool(true)
        layout.updateKey(layer: 0, index: 1) { $0 = key }
        if let output { layout.combos = [Combo(id: "c", keyIndices: [13, 14], layer: 0, output: output)] }
        return layout
    }

    /// A code in every place the generator writes one: alone, with modifiers, as a mod-tap's tap, in a dual-function
    /// key, in a tap dance and as a combo's output.
    static func layouts(_ code: String) -> [KeyboardLayout] {
        let action = KeyAction.code(code)
        return [
            layout(Key(tap: action)),
            layout(Key(tap: KeyAction(code: code, modifiers: .leftCommand))),
            layout(Key(tap: action, hold: .code("KC_LEFT_SHIFT"))),
            layout(Key(tap: action, hold: .code("KC_B"))),
            layout(Key(tap: action, doubleTap: .code("KC_B"))),
            layout(Key(tap: .code("KC_A")), combo: action),
        ]
    }

    /// The keycode a key alone writes, or nil when the generator refuses it.
    static func written(_ code: String) -> String? {
        let layout = layout(Key(tap: .code(code)))
        guard (try? QMKGenerator().generate(layout, identity: identity)) != nil else { return nil }
        return try? KeymapPlan(layout).tokens[0][1]
    }

    @Test func writesTheCatalogsCodeForASpellingQMKDropped() throws {
        for code in Self.codes {
            guard let name = Self.written(code) else { continue }
            #expect(!QMKCodes.undeclaredLegacyNames.contains(name), "\(code) → \(name)")
            if QMKCodes.undeclaredLegacyNames.contains(code) {
                #expect(name == KeycodeCatalog.canonicalCode(code), "\(code) → \(name)")
            }
        }
        // Spellings QMK still declares stay as stored, as Oryx writes them (the golden tests compare with Oryx's source).
        #expect(Self.written("KC_NUBS") == "KC_NUBS" && Self.written("KC_LCTL") == "KC_LCTL")
        #expect(Self.written("KC_BSPACE") == "KC_BSPC" && Self.written("KC_LCTRL") == "KC_LEFT_CTRL")
    }

    /// No dropped spelling reaches any line of the keymap, wherever the code sits. (Only a stored one could: the test
    /// above shows none is written in place of another code.)
    @Test func noDroppedSpellingReachesTheKeymap() throws {
        let dropped = QMKCodes.undeclaredLegacyNames
        for code in dropped.sorted() {
            var built = 0
            for layout in Self.layouts(code) {
                guard let keymap = (try? QMKGenerator().generate(layout, identity: Self.identity))?.files["keymap.c"] else { continue }
                built += 1
                let words = Set(keymap.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init))
                #expect(words.isDisjoint(with: dropped), "\(code): \(words.intersection(dropped).sorted())")
            }
            // Each builds somewhere: a key alone at least.
            #expect(built > 0, "\(code)")
        }
    }

    /// The list names catalog spellings only, never a catalog's own code.
    @Test func droppedSpellingsAreCatalogAliases() {
        for name in QMKCodes.undeclaredLegacyNames {
            let entry = KeycodeCatalog.entry(for: name)
            #expect(entry != nil && entry?.code != name, "\(name)")
        }
    }

    /// Against the pinned QMK's own headers, when the toolchain is set up (it is never downloaded here): every name the
    /// generator writes for a catalog code is declared, or defined by `keymap.c` or `i18n.h`, and every name on the list
    /// is really missing.
    @Test(.enabled(if: PinnedQMK.declared != nil))
    func pinnedQMKDeclaresEveryNameWritten() throws {
        let declared = try #require(PinnedQMK.declared)
        let ownNames: Set<String> = ["RGB_SLD", "MOON_LED_LEVEL"]
        for code in Self.codes {
            guard let name = Self.written(code), name.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil else { continue }
            let defined = declared.contains(name) || ownNames.contains(name) || QMKCodes.locale[name] != nil
            #expect(defined, "\(code) → \(name)")
        }
        for name in QMKCodes.undeclaredLegacyNames { #expect(!declared.contains(name), "\(name) is declared") }
    }
}

/// The keycode names the pinned QMK declares where a keymap sees them, read from the set-up toolchain.
enum PinnedQMK {
    static let declared: Set<String>? = {
        let installer = ToolchainInstaller()
        guard installer.isInstalled else { return nil }
        let root = NativeToolchain(installer: installer).firmware
        let headers = [
            "quantum/keycodes.h", "quantum/quantum_keycodes.h", "quantum/keymap_extras/keymap_us.h",
            "quantum/quantum_keycodes_legacy.h", "modules/zsa/defaults/defaults.h",
        ]
        var names: Set<String> = []
        // `#define NAME …`, or an enum member alone on its line: `NAME = 0x0004,` or `NAME,`.
        let definition = /\s*(?:#\s*define\s+([A-Za-z_]\w*)\b.*|([A-Za-z_]\w*)\s*(?:=[^,]*)?,?\s*(?:\/\/.*)?)/
        for header in headers {
            guard let text = try? String(contentsOf: root.appending(path: header), encoding: .utf8) else { return nil }
            for line in text.split(separator: "\n") {
                if let match = line.wholeMatch(of: definition), let name = match.1 ?? match.2 { names.insert(String(name)) }
            }
        }
        // Each module's keycodes and their aliases (`qmk_module.json`).
        let modules = root.appending(path: "modules/zsa")
        for module in (try? FileManager.default.contentsOfDirectory(atPath: modules.path)) ?? [] {
            guard let json = try? String(contentsOf: modules.appending(path: "\(module)/qmk_module.json"), encoding: .utf8) else {
                continue
            }
            for match in json.matches(of: /"key"\s*:\s*"(\w+)"/) { names.insert(String(match.1)) }
            for list in json.matches(of: /"aliases"\s*:\s*\[([^\]]*)\]/) {
                for match in list.1.matches(of: /"(\w+)"/) { names.insert(String(match.1)) }
            }
        }
        return names
    }()
}
