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
}
