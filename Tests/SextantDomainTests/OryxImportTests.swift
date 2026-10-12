import Foundation
import SextantDomain
import Testing

struct OryxReferenceTests {
    @Test(arguments: [
        (
            "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0",
            OryxReference(geometry: "voyager", layoutID: "KlgM7", revisionID: "40xJ7M", layer: 0)
        ),
        (
            "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/2/14/tap",
            OryxReference(geometry: "voyager", layoutID: "KlgM7", revisionID: "40xJ7M", layer: 2)
        ),
        ("https://configure.zsa.io/voyager/layouts/KlgM7/latest/1", OryxReference(geometry: "voyager", layoutID: "KlgM7", layer: 1)),
        ("https://configure.zsa.io/voyager/layouts/KlgM7", OryxReference(geometry: "voyager", layoutID: "KlgM7")),
        ("https://Configure.ZSA.io/voyager/layouts/KlgM7", OryxReference(geometry: "voyager", layoutID: "KlgM7")),
        (
            "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/-1",
            OryxReference(geometry: "voyager", layoutID: "KlgM7", revisionID: "40xJ7M")
        ),
        ("configure.zsa.io/moonlander/layouts/abc12/xyz34", OryxReference(geometry: "moonlander", layoutID: "abc12", revisionID: "xyz34")),
        ("  KlgM7/40xJ7M\n", OryxReference(layoutID: "KlgM7", revisionID: "40xJ7M")),
        ("KlgM7/latest", OryxReference(layoutID: "KlgM7")),
        ("KlgM7", OryxReference(layoutID: "KlgM7")),
    ])
    func parses(_ input: String, _ expected: OryxReference) {
        #expect(OryxReference(input) == expected)
    }

    @Test(arguments: [
        "", "   ", "hello world", "ab", "KlgM7/40xJ7M/0", "KlgM7/", "/KlgM7", "Klg-M7", "KlgM7/40x.J7M",
        "https://example.com/voyager/layouts/KlgM7/40xJ7M", "https://evilzsa.io/voyager/layouts/KlgM7",
        "https://configure.zsa.io/voyager/layouts/", "https://configure.zsa.io/voyager/layouts/KlgM7/40x$J7M",
        "https://configure.zsa.io/voyager/search",
    ])
    func refusesJunk(_ input: String) {
        #expect(OryxReference(input) == nil)
    }
}

struct ImportSummaryTests {
    /// The spec's own example (§8.1) is the user's layout.
    @Test func countsTheUserLayout() throws {
        let summary = ImportSummary(try Fixtures.layout())
        #expect(summary.layers == 3)
        #expect(summary.assignedKeys == 130)
        #expect(summary.dualFunctionKeys == 6)
        #expect(summary.customLabels == 4)
        #expect(summary.colorKeys == 3)
        #expect(summary.macros == 0)
        #expect(summary.unknownCodes == 0)
        #expect(summary.combos == 0)
        #expect(summary.navigator == nil)
    }

    @Test func countsTheNavigator() throws {
        let full = ImportSummary(try Fixtures.layout("my-layout-KlgM7-full.json"))
        #expect(full.navigator?.kind == .trackpad && full.navigator?.side == .right)
    }

    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"))
    func countsMacrosAndCombos() throws {
        let jr = ImportSummary(try Fixtures.layout("voyager-JRGQm.json"))
        #expect(jr.layers == 12)
        #expect(jr.macros == 66)
        #expect(jr.combos == 32)
    }

    @Test func countsKeysWithUnknownCodes() throws {
        var layout = try Fixtures.layout()
        layout.updateKey(layer: 0, index: 1) { $0 = Key("KC_FUTURE_KEY") }
        layout.updateKey(layer: 1, index: 2) { $0 = Key("KC_FUTURE_KEY") }
        #expect(ImportSummary(layout).unknownCodes == 2)
    }
}
