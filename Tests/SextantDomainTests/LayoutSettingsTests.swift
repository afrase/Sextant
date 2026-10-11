import Foundation
import SextantDomain
import Testing

struct LayoutSettingsTests {
    let catalog = SettingsCatalog.voyager

    func setting(_ id: String) throws -> Setting { try #require(catalog.setting(id: id)) }

    /// Oryx stores config sparsely; a toggleable slider is off when unset and keeps its value when on (`flowTap: 100`).
    @Test func storesSparselyAndKeepsToggleableValues() throws {
        var layout = try Fixtures.layout()
        layout.store(.number(180), for: try setting("tappingTerm"))
        #expect(layout.settings["tappingTerm"] == .number(180))
        layout.store(.number(200), for: try setting("tappingTerm"))
        #expect(layout.settings["tappingTerm"] == nil, "the default is removed")
        let flowTap = try setting("flowTap")
        #expect(flowTap.unsetValue == nil)
        layout.store(.number(100), for: flowTap)
        #expect(layout.settings["flowTap"] == .number(100), "100 is flow tap's value when on, not its absence")
        #expect(layout.changedSettings().map(\.id) == ["flowTap"])
        layout.store(nil, for: flowTap)
        #expect(layout.settings["flowTap"] == nil && layout.changedSettings().isEmpty)
    }

    /// Navigator settings live with the Navigator, where Oryx and the generator read them.
    @Test func navigatorSettingsGoToTheNavigator() throws {
        var layout = try Fixtures.layout("my-layout-KlgM7-full.json")
        let time = try setting("automouseTime")
        layout.store(.number(800), for: time)
        #expect(layout.navigator?.options["automouseTime"] == .number(800) && layout.settings["automouseTime"] == nil)
        #expect(layout.storedValue(of: time) == .number(800))
        #expect(layout.changedSettings().map(\.id) == ["automouseTime"])
        var bare = try Fixtures.layout()
        bare.store(.number(800), for: time)
        #expect(bare.navigator == nil && bare.settings["automouseTime"] == nil, "no Navigator, nowhere to keep it")
    }

    /// A value field parses "nan"; JSON can't encode it, so storing it would make every later save fail.
    @Test func ignoresNumbersJSONCantHold() throws {
        let before = try Fixtures.layout()
        var layout = before
        layout.store(.number(.nan), for: try setting("tappingTerm"))
        layout.store(.number(.infinity), for: try setting("tappingTerm"))
        #expect(layout == before)
        #expect(try setting("tappingTerm").format(.number(180)) == "180 ms")
    }

    /// Spec §12.1: a blank QWERTY layout Sextant authors; every key is one the catalog knows.
    @Test func blankQWERTYFillsTheBoard() {
        let layout = KeyboardLayout.blankQWERTY(title: "Untitled Layout")
        #expect(layout.layers.count == 1 && layout.keyCount == BoardDefinition.voyager.keyCount)
        #expect(layout.layers[0].keys.allSatisfy { !Legends.legend(for: $0.tap ?? .transparent).isUnknown && !$0.isTransparent })
        #expect(layout.key(layer: 0, index: 7)?.tap?.code == "KC_Q" && layout.key(layer: 0, index: 51)?.tap?.code == "KC_BSPC")
        #expect(layout.oryx == nil && layout.swatch == KeyboardLayout.defaultSwatch)
    }
}
