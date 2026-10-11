import AppKit
import SextantDomain
import Testing

@testable import SextantUI

@MainActor
struct BoardSizingTests {
    /// Spec §3.3: about 52 pt caps at 1440×900 with both columns (centre 912 wide; bands and toolbar take 240 of the height).
    @Test func capSizeAtTheDefaultWindow() {
        let units = BoardDefinition.voyager.geometry().bounds.size
        let cap = BoardView.capSize(for: CGSize(width: 1440 - 228 - 300, height: 900 - 52 - 188), boardUnits: units, range: 36...76)
        #expect(abs(cap - 52) < 2, "\(cap)")
        #expect(BoardView.capSize(for: CGSize(width: 300, height: 200), boardUnits: units, range: 36...76) == 36, "clamped low")
        #expect(BoardView.capSize(for: CGSize(width: 4000, height: 3000), boardUnits: units, range: 36...76) == 76, "clamped high")
    }

    @Test func everySymbolNameExists() {
        let catalog = KeycodeCatalog.entries.compactMap(\.symbol)
        let ui =
            Array(CapLegendView.arrows.values) + [
                "square.stack.3d.up.fill", "rectangle.and.hand.point.up.left", "circle.circle", "keyboard",
            ]
        let missing = Set(catalog + ui).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "\(missing.sorted())")
    }
}
