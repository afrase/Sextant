import Foundation
import Testing

@testable import SextantDomain

/// Oryx gives every layer a new hash id in each revision (ADR 0054): an import as a revision keeps the ids of the layers
/// Oryx says it came from, through any number of revisions.
struct OryxLayerIdentityTests {
    func layer(_ id: String, previous: String? = nil, _ title: String) -> Layer {
        var layer = Layer.transparent(title: title)
        layer.id = id
        layer.oryxPreviousID = previous
        return layer
    }

    func layout(_ layers: [Layer]) -> KeyboardLayout { KeyboardLayout(title: "Mine", layers: layers) }

    @Test func eachRevisionKeepsTheFirstImportsIDs() {
        let first = layout([layer("D5ZXGN", "Main"), layer("BwNDxw", "Sym+Num"), layer("XYqajg", "Brd+Sys")])
        let second = layout([
            layer("l9zarb", previous: "D5ZXGN", "Main"), layer("3aoXlq", previous: "BwNDxw", "Sym+Num"),
            layer("VjWD9Y", previous: "XYqajg", "Brd+Sys"),
        ]).keepingLayerIDs(of: first)
        #expect(second.layers.map(\.id) == ["D5ZXGN", "BwNDxw", "XYqajg"])
        #expect(second.layers.map(\.oryxCurrentID) == ["l9zarb", "3aoXlq", "VjWD9Y"])

        // The next revision points at the second's Oryx ids; a layer added in Oryx keeps its own, and one moved keeps its.
        let third = layout([
            layer("n1", previous: "l9zarb", "Main"), layer("n2", previous: "VjWD9Y", "Brd+Sys"), layer("n3", "Mouse"),
            layer("n4", previous: "3aoXlq", "Sym+Num"),
        ]).keepingLayerIDs(of: second)
        #expect(third.layers.map(\.id) == ["D5ZXGN", "XYqajg", "n3", "BwNDxw"])
        #expect(third.layers.map(\.oryxID) == ["n1", "n2", nil, "n4"])
        #expect(third.layers.allSatisfy { $0.oryxPreviousID == nil }, "used, so the document is what is stored")

        // The same revision imported again changes nothing.
        let again = layout(third.layers.map { layer($0.oryxCurrentID, previous: $0.oryxPreviousID, $0.title) })
        #expect(again.keepingLayerIDs(of: third).layers.map(\.id) == third.layers.map(\.id))
    }

    /// Without `prevHashId` nothing is matched, not even by position: a layer added or moved in Oryx would take another's
    /// rules and counts.
    @Test func noPreviousIDKeepsOryxsID() {
        let before = layout([layer("a", "Main"), layer("b", "Sym")])
        let next = layout([layer("x", "Main"), layer("y", "Sym")]).keepingLayerIDs(of: before)
        #expect(next.layers.map(\.id) == ["x", "y"] && next.layers.allSatisfy { $0.oryxID == nil })
    }

    /// Each earlier layer is taken once, and ids stay unique.
    @Test func idsStayUnique() {
        let before = layout([layer("a", "Main"), layer("b", "Sym")])
        let next = layout([layer("x", previous: "a", "Main"), layer("y", previous: "a", "Copy"), layer("a", "New")])
            .keepingLayerIDs(of: before)
        #expect(next.layers[0].id == "a" && next.layers[1].id == "y")
        #expect(Set(next.layers.map(\.id)).count == 3, "\(next.layers.map(\.id))")
        #expect(next.layers[2].oryxCurrentID == "a")
    }

    /// Oryx's current id survives the `.sextant` format; `prevHashId` is read from Oryx and used at once, never written,
    /// so a fresh import's content hash is what it was.
    @Test func theIDsRoundTrip() throws {
        var mine = layout([layer("D5ZXGN", "Main")])
        mine.layers[0].oryxID = "l9zarb"
        #expect(try KeyboardLayout(oryxJSON: JSONEncoder().encode(mine)).layers == mine.layers)
        var plain = layout([layer("D5ZXGN", previous: "XYqajg", "Main")])
        let json = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!json.contains("oryxHashId") && !json.contains("prevHashId"), "a layout without them is written as before")
        plain.layers[0].oryxPreviousID = nil
        #expect(try KeyboardLayout(oryxJSON: JSONEncoder().encode(plain)).layers == plain.layers)
        let oryx = try KeyboardLayout(oryxJSON: Data(contentsOf: Self.examples.appending(path: "my-layout-KlgM7-full.json")))
        #expect(oryx.layers.map(\.oryxPreviousID) == ["D5ZXGN", "BwNDxw", "XYqajg"], "read from Oryx's export")
        #expect(oryx.keepingLayerIDs(of: oryx).layers.allSatisfy { $0.oryxPreviousID == nil })
    }

    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "docs/research/oryx-examples")
}
