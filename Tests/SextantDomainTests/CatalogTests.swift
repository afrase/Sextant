import Foundation
import SextantDomain
import Testing

struct CatalogTests {
    @Test func catalogIsUniqueAndBigEnough() {
        let entries = KeycodeCatalog.entries
        #expect(entries.count >= 300)
        #expect(Set(entries.map(\.code)).count == entries.count)
    }

    @Test func everyExampleCodeIsCatalogued() throws {
        var missing: Set<String> = []
        for file in Fixtures.allLayoutFiles {
            for layer in try Fixtures.layout(file).layers {
                for key in layer.keys {
                    for (_, a) in key.actions where a.macro == nil && KeycodeCatalog.entry(for: a.code) == nil {
                        missing.insert(a.code)
                    }
                }
            }
        }
        #expect(missing.isEmpty, "\(missing.sorted())")
    }

    @Test func searchRanksSensibly() {
        #expect(KeycodeCatalog.search("esc").first?.code == "KC_ESCAPE")
        #expect(KeycodeCatalog.search("⌘").first?.code == "KC_LEFT_GUI")
        #expect(KeycodeCatalog.search("pgdn").first?.code == "KC_PGDN")
        #expect(KeycodeCatalog.search("[").first?.code == "KC_LBRC")
        #expect(KeycodeCatalog.canonicalCode("KC_LSFT") == "KC_LEFT_SHIFT")
        #expect(KeycodeCatalog.canonicalCode("RGB_MOD") == "RGB_MODE_FORWARD")
    }

    @Test func settingsCatalogDecodes() throws {
        let catalog = SettingsCatalog.voyager
        #expect(catalog.sections.count == 14)
        #expect(catalog.allSettings.count == 101)
        #expect(catalog.setting(id: "tappingTerm")?.defaultValue == .number(200))
        #expect(catalog.search("chordal").count == 2)
    }

    /// Search matches titles, descriptions, ids and Sextant's synonyms; every word must match, in any case or accent.
    @Test func settingsSearchUsesSynonyms() throws {
        let catalog = SettingsCatalog.voyager
        #expect(catalog.search("chatter").map(\.id) == ["debounce"])
        #expect(catalog.search("ROLLOVER").map(\.id) == ["disableNKRO"])
        #expect(catalog.search("perKeyTapping").map(\.id) == ["perKeyTappingTerm"])
        #expect(catalog.search("bepo").map(\.id) == ["bepo"], "diacritics fold: Bépo")
        #expect(Set(catalog.search("home row mods").map(\.id)).isSuperset(of: ["tappingTerm", "chordalHold", "flowTap"]))
        #expect(catalog.search("sniper layers").map(\.id) == ["aimLayers"])
        #expect(catalog.search("").count == catalog.allSettings.count)
        #expect(catalog.allSettings.filter(catalog.offers).allSatisfy { !$0.synonyms.isEmpty }, "every offered setting has synonyms")
    }

    /// The one-shot auto-mouse idle timeout is a trackpad option: QMK's one-shot auto mouse on the trackball has none.
    @Test func theIdleTimeoutIsATrackpadOption() throws {
        let timeout = try #require(SettingsCatalog.voyager.setting(id: "oneShotAutoMouseTimeout"))
        #expect(timeout.navigatorKinds == ["trackpad"])
        var layout = try Fixtures.layout("my-layout-KlgM7-full.json")
        layout.navigator?.options["oneShotAutoMouseTimeout"] = .number(5)
        layout.setNavigator(.trackball)
        #expect(layout.navigator?.options["oneShotAutoMouseTimeout"] == nil, "a trackball drops it")
    }

    /// Animations read as how many are in; an empty layer list as None.
    @Test func listsFormatForPeople() throws {
        let animations = try #require(SettingsCatalog.voyager.setting(id: "disabledAnimations"))
        #expect(animations.options.count == 48)
        #expect(animations.format(.strings([])) == "48 of 48" && animations.format(.strings(["breathing", "nope"])) == "47 of 48")
        let aim = try #require(SettingsCatalog.voyager.setting(id: "aimLayers"))
        #expect(aim.format(.integers([])) == "None" && aim.format(.integers([1, 2])) == "1, 2")
    }
}
