import Foundation
import Testing

@testable import SextantDomain

/// The keys pasteboard format and its trust boundary (ADR 0047).
struct CopiedKeysTests {
    /// Every key of every layer survives the JSON flavor unchanged.
    func roundTrips(_ layout: KeyboardLayout) throws {
        for layer in layout.layers.indices {
            let copied = try #require(CopiedKeys(layout: layout, layer: layer, indices: Array(0..<layout.keyCount)))
            let data = try #require(copied.encoded())
            let decoded = try CopiedKeys(data: data)
            #expect(decoded == copied, "layer \(layer)")
            #expect(decoded.entries.map(\.key) == layout.layers[layer].keys)
            #expect(decoded.fitsPositions(of: layout))
        }
    }

    @Test(arguments: ["my-layout-KlgM7-40xJ7M.json", "my-layout-KlgM7-full.json"])
    func roundTripsTheUsersLayout(_ file: String) throws {
        try roundTrips(Fixtures.layout(file))
    }

    /// Dense samples: JRGQm's 66 macros and labels, XlrR4's Option-held macros.
    @Test(.enabled(if: Fixtures.reference != nil, "needs SEXTANT_REFERENCE"), arguments: ["voyager-JRGQm.json", "voyager-XlrR4.json"])
    func roundTripsDenseLayouts(_ file: String) throws {
        try roundTrips(Fixtures.layout(file))
    }

    /// The Macros page puts no limit on a name, so a copy keeps a long one.
    @Test func roundTripsALongMacroName() throws {
        var layout = try Fixtures.layout()
        let macro = Macro(name: String(repeating: "N", count: 80), steps: [MacroStep(code: "KC_A")])
        layout.updateKey(layer: 0, index: 5) { $0 = Key(tap: KeyAction(code: "KC_TRANSPARENT", macro: macro)) }
        let copied = try #require(CopiedKeys(layout: layout, layer: 0, indices: [5]))
        #expect(try CopiedKeys(data: #require(copied.encoded())) == copied)
    }

    @Test func copiesTheGivenKeysInIndexOrder() throws {
        let layout = try Fixtures.layout()
        let copied = try #require(CopiedKeys(layout: layout, layer: 0, indices: [24, 3, 3, 99]))
        #expect(copied.entries.map(\.index) == [3, 24], "each once, off-board indices left out")
        #expect(copied.board == "voyager" && copied.keyCount == 52)
        #expect(CopiedKeys(layout: layout, layer: 9, indices: [3]) == nil)
        #expect(CopiedKeys(layout: layout, layer: 0, indices: []) == nil)
        #expect(copied.qmkExpressions == [3, 24].map { Legends.qmkExpression(for: layout.layers[0].keys[$0]) }.joined(separator: ", "))
    }

    @Test func layerKeysForMissingLayersPasteAsNothing() {
        let key = Key(tap: .code("KC_A"), hold: .momentary(5))
        let copied = CopiedKeys(
            board: "voyager", keyCount: 52, entries: [.init(index: 0, key: key), .init(index: 1, key: Key(tap: .toggle(2)))])
        let fitted = copied.entries(forLayerCount: 3)
        #expect(fitted[0].key.hold == KeyAction.none && fitted[0].key.tap == .code("KC_A"))
        #expect(fitted[1].key.tap == .toggle(2), "a layer this layout has keeps its number")
    }

    // MARK: Hostile payloads

    private func payload(version: Int = 1, format: String = "com.sextant.keys", keyCount: Int = 52, keys: String) -> Data {
        Data(#"{"format":"\#(format)","version":\#(version),"board":"voyager","keyCount":\#(keyCount),"keys":[\#(keys)]}"#.utf8)
    }

    private func refuses(_ data: Data, _ expected: CopiedKeysError) {
        #expect(throws: expected) { try CopiedKeys(data: data) }
    }

    @Test func refusesWhatIsntKeys() {
        refuses(Data("not json".utf8), .malformed)
        refuses(Data(#"{"keys":[]}"#.utf8), .malformed)
        refuses(payload(format: "com.example.other", keys: #"{"index":0,"key":{"tap":{"code":"KC_A"}}}"#), .malformed)
        refuses(payload(version: 2, keys: #"{"index":0,"key":{"tap":{"code":"KC_A"}}}"#), .unsupportedVersion(2))
        refuses(payload(keys: #"{"index":0,"key":"KC_A"}"#), .malformed)
        refuses(Data(count: CopiedKeys.maxBytes + 1), .tooLarge)
    }

    @Test func refusesBadCountsAndIndices() {
        let key = #"{"tap":{"code":"KC_A"}}"#
        refuses(payload(keys: ""), .badKeyCount)
        refuses(payload(keyCount: 0, keys: #"{"index":0,"key":\#(key)}"#), .badKeyCount)
        refuses(payload(keyCount: 100_000, keys: #"{"index":0,"key":\#(key)}"#), .badKeyCount)
        refuses(payload(keyCount: 1, keys: #"{"index":0,"key":\#(key)},{"index":1,"key":\#(key)}"#), .badKeyCount)
        refuses(payload(keys: #"{"index":52,"key":\#(key)}"#), .badIndex(52))
        refuses(payload(keys: #"{"index":-1,"key":\#(key)}"#), .badIndex(-1))
        refuses(payload(keys: #"{"index":4,"key":\#(key)},{"index":4,"key":\#(key)}"#), .badIndex(4))
    }

    @Test func refusesCodesThatArentIdentifiersAndLayersQMKLacks() {
        refuses(payload(keys: #"{"index":3,"key":{"tap":{"code":"KC_A); evil();//"}}}"#), .badAction(index: 3))
        refuses(payload(keys: #"{"index":3,"key":{"tap":{"code":""}}}"#), .badAction(index: 3))
        refuses(payload(keys: #"{"index":3,"key":{"tap":{"code":"\#(String(repeating: "A", count: 65))"}}}"#), .badAction(index: 3))
        refuses(payload(keys: #"{"index":3,"key":{"hold":{"code":"MO","layer":32}}}"#), .badAction(index: 3))
        refuses(payload(keys: #"{"index":3,"key":{"hold":{"code":"MO","layer":-1}}}"#), .badAction(index: 3))
        let step = #"{"code":"KC_A\"; x"}"#
        refuses(payload(keys: #"{"index":3,"key":{"tap":{"code":"KC_TRANSPARENT","macro":{"keys":[\#(step)]}}}}"#), .badAction(index: 3))
    }

    @Test func clampsTextMacrosAndTerms() throws {
        let steps = Array(repeating: #"{"code":"KC_A","delay":99999}"#, count: 30).joined(separator: ",")
        let key = """
            {"customLabel":"Twelve chars","tappingTerm":5000,\
            "tap":{"code":"KC_TRANSPARENT","description":"\(String(repeating: "d", count: 40))",\
            "macro":{"name":"\(String(repeating: "n", count: 80))","keys":[\(steps)]}}}
            """
        let copied = try CopiedKeys(data: payload(keys: #"{"index":7,"key":\#(key)}"#))
        let pasted = try #require(copied.entries.first?.key)
        #expect(pasted.customLabel == "Twelve cha", "10 characters, as the label field allows")
        #expect(pasted.tappingTerm == nil, "outside the generator's range")
        #expect(pasted.tap?.description?.count == 30)
        let macro = try #require(pasted.tap?.macro)
        #expect(macro.steps.count == 30 && macro.steps.allSatisfy { $0.delay == Macro.maxDelay }, "every step, each wait at most 5 s")
        #expect(macro.name?.count == 80, "names keep their length: the Macros page allows any, and the size cap bounds them")
    }
}
