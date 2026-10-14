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

    // MARK: Coupling (spec §8.8)

    /// A tapping term over 500 ms turns Permissive hold on, and lowering it again leaves it on.
    @Test func aLongTappingTermTurnsOnPermissiveHold() throws {
        var layout = try Fixtures.layout()
        layout.store(.number(500), for: try setting("tappingTerm"))
        #expect(layout.settings["permissiveHold"] == nil, "500 isn't over 500")
        layout.store(.number(501), for: try setting("tappingTerm"))
        #expect(layout.settings["permissiveHold"] == .bool(true))
        layout.store(.number(180), for: try setting("tappingTerm"))
        #expect(layout.settings["permissiveHold"] == .bool(true))
        layout.store(nil, for: try setting("permissiveHold"))
        layout.store(.number(300), for: try setting("tappingTerm"))
        #expect(layout.settings["permissiveHold"] == nil)
    }

    /// Chordal hold carries Exclude thumbs with it, both ways; Exclude thumbs alone changes nothing else.
    @Test func chordalHoldSetsExcludeThumbs() throws {
        var layout = try Fixtures.layout()
        layout.store(.bool(true), for: try setting("chordalHold"))
        #expect(layout.settings["chordalHoldExcludeThumbs"] == .bool(true))
        layout.store(.bool(false), for: try setting("chordalHoldExcludeThumbs"))
        #expect(layout.settings["chordalHold"] == .bool(true) && layout.settings["chordalHoldExcludeThumbs"] == nil)
        layout.store(.bool(true), for: try setting("chordalHoldExcludeThumbs"))
        layout.store(.bool(false), for: try setting("chordalHold"))
        #expect(layout.settings["chordalHold"] == nil && layout.settings["chordalHoldExcludeThumbs"] == nil, "stored sparsely")
    }

    /// Auto Shift needs a key group: turning it on with punctuation, numbers and letters off turns them on, and turning
    /// the last of them off turns it off. Tab isn't one of them.
    @Test func autoShiftAndItsKeyGroupsFollowEachOther() throws {
        var layout = try Fixtures.layout()
        let groups = ["autoshiftEnableSpecial", "autoshiftEnableNumeric", "autoshiftEnableAlpha"]
        layout.store(.bool(true), for: try setting("autoshift"))
        #expect(layout.settings["autoshift"] == .bool(true) && groups.allSatisfy { layout.settings[$0] == nil }, "on by default")
        for group in groups.dropLast() { layout.store(.bool(false), for: try setting(group)) }
        #expect(layout.settings["autoshift"] == .bool(true), "letters are still on")
        layout.store(.bool(false), for: try setting("autoshiftEnableTab"))
        #expect(layout.settings["autoshift"] == .bool(true))
        layout.store(.bool(false), for: try setting("autoshiftEnableAlpha"))
        #expect(layout.settings["autoshift"] == nil && groups.allSatisfy { layout.settings[$0] == .bool(false) })
        layout.store(.bool(true), for: try setting("autoshift"))
        #expect(groups.allSatisfy { layout.settings[$0] == nil }, "all three back on")
        #expect(layout.settings["autoshiftEnableTab"] == .bool(false), "Tab keeps its own value")
        layout.store(.bool(false), for: try setting("autoshiftEnableNumeric"))
        layout.store(.bool(true), for: try setting("autoshift"))
        #expect(layout.settings["autoshiftEnableNumeric"] == .bool(false), "a group is on, so nothing changes")
    }

    // MARK: What Sextant offers (ADR 0040, 0041)

    /// Hidden settings keep their imported values but stay out of the changed list; only UK and US International show
    /// among the locales.
    @Test func hiddenSettingsAreKeptButNotCounted() throws {
        let catalog = SettingsCatalog.voyager
        var layout = try Fixtures.layout()
        for (id, value) in [
            ("dancesTapAction", SettingValue.bool(false)), ("liveTraining", .bool(false)), ("stenography", .bool(true)),
            ("german", .bool(true)), ("audioClick", .bool(true)), ("uk", .bool(true)),
        ] {
            layout.settings[id] = value
        }
        #expect(layout.changedSettings().map(\.id) == ["uk"])
        #expect(Set(layout.keptSettings().map(\.id)) == ["dancesTapAction", "liveTraining", "stenography", "german", "audioClick"])
        let offered = catalog.allSettings.filter(catalog.offers)
        #expect(offered.count == 60)
        #expect(offered.filter { catalog.section(containing: $0.id)?.id == "international" }.map(\.id) == ["uk", "usint"])
        for id in ["enableNavigator", "geminipr", "audioDisable"] { #expect(!catalog.offers(try setting(id)), "\(id)") }
    }

    /// A layout shows an offered setting only for its Navigator and while the setting it depends on is on. A stored
    /// value it doesn't show is kept, not counted as changed, so every changed value has a row (an Oryx trackball layout
    /// can carry the trackpad's idle timeout; turning one-shot off keeps the timeout for when it is back on).
    @Test func valuesTheLayoutDoesntShowAreKept() throws {
        var layout = try Fixtures.layout("my-layout-KlgM7-full.json")
        let timeout = try setting("oneShotAutoMouseTimeout")
        layout.navigator = NavigatorConfig(
            kind: .trackball, side: .right, options: ["oneShotAutoMouse": .bool(true), "oneShotAutoMouseTimeout": .number(5)])
        let sensitivity = try setting("sensitivity")
        #expect(!layout.offers(timeout) && layout.offers(sensitivity))
        #expect(layout.changedSettings().map(\.id) == ["oneShotAutoMouse"])
        #expect(layout.keptSettings().map(\.id) == ["oneShotAutoMouseTimeout"])
        layout.navigator?.kind = .trackpad
        #expect(layout.offers(timeout) && !layout.offers(sensitivity))
        #expect(layout.changedSettings().map(\.id) == ["oneShotAutoMouse", "oneShotAutoMouseTimeout"])
        layout.store(nil, for: try setting("oneShotAutoMouse"))
        #expect(!layout.offers(timeout) && layout.changedSettings().isEmpty)
        #expect(layout.keptSettings().map(\.id) == ["oneShotAutoMouseTimeout"])
    }

    /// The picker offers a locale's codes only while its International toggle is on; other codes always.
    @Test func localeTogglesGateTheirKeycodes() throws {
        var layout = try Fixtures.layout()
        #expect(!layout.offersKeycode("UK_PND") && !layout.offersKeycode("US_EACU"))
        #expect(layout.offersKeycode("KC_A") && layout.offersKeycode("KC_INTERNATIONAL_1") && layout.offersKeycode("KC_LANGUAGE_1"))
        layout.store(.bool(true), for: try setting("uk"))
        #expect(layout.offersKeycode("UK_PND") && !layout.offersKeycode("US_EACU"))
        layout.store(.bool(true), for: try setting("usint"))
        #expect(layout.offersKeycode("US_EACU"))
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
