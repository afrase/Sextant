import Foundation
import SextantDomain
import Testing

struct LayoutCodecTests {
    @Test func decodesTheUserLayout() throws {
        let layout = try Fixtures.layout()
        #expect(layout.title == "My MacOS Layout [fork]")
        #expect(layout.layers.map(\.title) == ["Main", "Sym+Num", "Brd+Sys"])
        #expect(layout.layers[1].color?.hex == "#00F0FF")
        #expect(layout.layers[2].color?.hex == "#42FF00")
        #expect(layout.layers.allSatisfy { $0.keys.count == 52 })
        #expect(layout.oryx?.serial == "KlgM7/40xJ7M")
        #expect(layout.oryx?.firmwareVersion == "25.0")
        #expect(layout.settings == ["qmkCanary": .bool(true)])
    }

    @Test func navigatorAndSwatchesComeAlong() throws {
        let full = try Fixtures.layout("my-layout-KlgM7-full.json")
        #expect(full.navigator?.kind == .trackpad)
        #expect(full.navigator?.side == .right)
        #expect(full.navigator?.options["scrollInertia"] == .bool(true))
        #expect(full.navigator?.options["aimSpeed"] == nil, "null options mean default and are dropped")
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func otherNavigatorsAndSwatchesComeAlong() throws {
        let e5 = try Fixtures.layout("voyager-e5Rrr.json")
        #expect(e5.navigator?.kind == .trackball)
        #expect(e5.navigator?.side == .left)
        #expect(e5.swatch.count == 10)

        let jr = try Fixtures.layout("voyager-JRGQm.json")
        #expect(e5.automouseLayer == 4 && jr.automouseLayer == 7, "Oryx flags the automouse layer on the layer")
        #expect(jr.navigator?.options["automouseLayer"] == nil)
        #expect(jr.combos.first?.name == "PrevWebTab")
        #expect(jr.combos.first?.keyIndices == [14, 13, 15])
        #expect(jr.combos.first?.output.modifiers == [.leftControl, .leftShift])
    }

    /// Oryx generates KC_TRANSPARENT for keys with no actions (Brd+Sys 18 and 43 in the user's keymap.c).
    @Test func keysWithoutActionsAreTransparent() throws {
        let layout = try Fixtures.layout()
        #expect(layout.layers[2].keys[18] == .transparent)
        #expect(layout.layers[2].keys[43] == .transparent)
    }

    @Test(arguments: Fixtures.allLayoutFiles)
    func roundTripsThroughSextantsFormat(file: String) throws {
        let original = try Fixtures.layout(file)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try KeyboardLayout(oryxJSON: data)
        #expect(decoded == original)
        #expect(try encoder.encode(decoded) == data, "encoding is deterministic")
    }

    /// The automouse layer is the layout's (ADR 0035): it is saved on its layer, with or without a Navigator, and a
    /// Navigator's `automouseLayer` (older Sextant files) is read too.
    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func theAutomouseLayerIsSavedOnItsLayer() throws {
        var layout = try Fixtures.layout("voyager-JRGQm.json")
        layout.navigator = nil
        #expect(try KeyboardLayout(oryxJSON: JSONEncoder().encode(layout)).automouseLayer == 7)
        layout.navigator = NavigatorConfig(kind: .trackpad, side: .right, options: ["automouseLayer": .number(2)])
        layout.automouseLayer = nil
        let decoded = try KeyboardLayout(oryxJSON: JSONEncoder().encode(layout))
        #expect(decoded.automouseLayer == 2 && decoded.navigator?.options.isEmpty == true)
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func emptyListsEqualTheirDefault() throws {
        let e5 = try Fixtures.layout("voyager-e5Rrr.json")
        let setting = try #require(SettingsCatalog.voyager.setting(id: "disabledAnimations"))
        #expect(e5.settings["disabledAnimations"] == setting.defaultValue)
    }

    @Test func refusesLayersWithTheWrongKeyCount() throws {
        let json = #"{"title":"x","geometry":"voyager","revision":{"layers":[{"title":"Main","keys":[null]}]}}"#
        #expect(throws: OryxDecodingError.badLayerKeyCount(layer: "Main", count: 1, expected: 52)) {
            try KeyboardLayout(oryxJSON: Data(json.utf8))
        }
        #expect(throws: OryxDecodingError.missingRevision) { try KeyboardLayout(oryxJSON: Data(#"{"title":"x"}"#.utf8)) }
    }

    @Test func refusesBoardsSextantDoesNotKnow() {
        let json = #"{"title":"x","geometry":"moonlander","revision":{"layers":[{"title":"Main","keys":[null]}]}}"#
        #expect(throws: OryxDecodingError.unsupportedBoard("moonlander")) { try KeyboardLayout(oryxJSON: Data(json.utf8)) }
    }

    @Test func errorsInsideAnEnvelopeAreReportedAsThemselves() {
        let json = #"{"data":{"layout":{"title":"x","geometry":"voyager","revision":{"layers":[{"title":"Main","keys":[null]}]}}}}"#
        #expect(throws: OryxDecodingError.badLayerKeyCount(layer: "Main", count: 1, expected: 52)) {
            try KeyboardLayout(oryxJSON: Data(json.utf8))
        }
    }

    @Test func aSlotWithoutACodeIsEmpty() throws {
        let key = try JSONDecoder().decode(Key.self, from: Data(#"{"tap":{"code":"KC_A"},"hold":{"code":null,"layer":null}}"#.utf8))
        #expect(key == Key("KC_A"))
    }

    @Test func foldsOryxModifierMasks() throws {
        let action = try JSONDecoder().decode(KeyAction.self, from: Data(#"{"code":"OSM","modifier":"MOD_LSFT"}"#.utf8))
        #expect(action.modifiers == [.leftShift])
    }

    /// Imported numbers are untrusted: huge, fractional or infinite values must not trap anywhere.
    @Test func hostileNumbersDoNotCrash() throws {
        var layout = try Fixtures.layout()
        layout.settings["tappingTerm"] = .number(1e300)
        layout.navigator = NavigatorConfig(kind: .trackpad, side: .right, options: ["automouseLayer": .number(1e300)])
        #expect(try KeyboardLayout(oryxJSON: JSONEncoder().encode(layout)).automouseLayer == nil)
        #expect(SettingValue.number(1e300).description == "1e+300")
        #expect(SettingValue.number(.infinity).description == "inf")
        #expect(SettingsCatalog.voyager.setting(id: "tappingTerm")?.format(.number(1e300)) != nil)
        layout.layers.append(.transparent(title: "Extra"))
        layout.moveLayer(from: 1, to: 3)
        #expect(HexColor(red: .nan, green: 0.5, blue: 1).hex == "#0080FF")
        #expect(HexColor(hue: .nan, saturation: 1, brightness: 1).hex == "#FF0000")
    }
}
