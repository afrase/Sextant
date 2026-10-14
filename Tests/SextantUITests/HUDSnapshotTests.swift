import SextantDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import SextantUI

/// The overlay HUD's content (spec §8.4, ADR 0050) on the user's layout: ⏎ (key 24) holds Sym+Num and Space (key 51)
/// holds Brd+Sys. Drawn as views; the real panel never shows in tests.
@MainActor
@Suite(.disabled(if: skipsPixelSnapshots, "the references are rendered on the developer's macOS"))
struct HUDSnapshotTests {
    let enter = KeyRef(layer: 0, index: 24)
    let space = KeyRef(layer: 0, index: 51)

    func layout() throws -> KeyboardLayout { try KeyboardLayout(oryxJSON: #require(userLayoutData)) }

    func render(
        _ view: some View, scheme: ColorScheme = .light, named name: String, reduceTransparency: Bool = false, test: String = #function
    ) throws {
        // Glass can't be captured offscreen; the snapshot surface stands in for it (spec §13.3).
        let framed = view.padding(24).background(Tokens.benchBase.color).environment(\.isSnapshot, true)
            .environment(\._accessibilityReduceTransparency, reduceTransparency).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        assertSnapshot(of: image, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: name, testName: test)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func heldWithEnter(scheme: ColorScheme) throws {
        let hud = try HUDView(layout: layout(), layer: 1, holder: enter, pressed: [24, 13], width: 696)
        try render(hud, scheme: scheme, named: scheme == .dark ? "dark" : "light")
    }

    @Test func tintedWithTheLayerColor() throws {
        try render(HUDView(layout: layout(), layer: 1, holder: enter, pressed: [24], width: 696, tints: true), named: "light")
    }

    @Test func smallAndLarge() throws {
        try render(HUDView(layout: layout(), layer: 2, holder: space, pressed: [51], width: 522), named: "small-light")
        try render(HUDView(layout: layout(), layer: 2, holder: space, pressed: [51, 13], width: 870), scheme: .dark, named: "large-dark")
    }

    @Test func lockedReminder() throws {
        try render(HUDPill(layout: layout(), layer: 1), named: "light")
        try render(HUDPill(layout: layout(), layer: 2, tints: true), scheme: .dark, named: "tinted-dark")
    }

    /// An opaque dark panel in either appearance, with no tint.
    @Test func reduceTransparency() throws {
        let hud = try HUDView(layout: layout(), layer: 1, holder: enter, pressed: [24], width: 696, tints: true)
        try render(hud, named: "light", reduceTransparency: true)
    }
}
