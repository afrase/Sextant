import SextantDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import SextantUI

/// Reference images of the board, rendered offscreen with `ImageRenderer` (no window, no TCC). References live
/// in `__Snapshots__/BoardSnapshotTests`; a missing one is recorded and the test fails once.
@MainActor
struct BoardSnapshotTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func symNumWithTheLayerKeySelected(scheme: ColorScheme) async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(layer: 1)
        session.select(key: 24)
        try assertBoard(BoardView(session: session), scheme: scheme)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func brdSysWithIssuesAndPresses(scheme: ColorScheme) async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(layer: 2)
        let pressed = PressedKeys()
        pressed.update([13, 51])
        let issues: [KeyRef: LayoutIssue.Severity] = [KeyRef(layer: 2, index: 31): .error, KeyRef(layer: 2, index: 44): .warning]
        try assertBoard(BoardView(session: session, issues: issues, pressed: pressed), scheme: scheme)
    }

    /// The decoration hook (ADR 0037b): a diff badge and ring over the LED dot, a combo number and ring beside an
    /// issue, a key at 40%, and the coolest and hottest heat fills with counts, whose legend ink follows the fill.
    @Test(arguments: [ColorScheme.light, .dark])
    func decoratedCaps(scheme: ColorScheme) throws {
        var layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        layout.layers[0].keys[19].glowColor = HexColor(red: 0.16, green: 1, blue: 1)
        func cap(_ index: Int, issue: LayoutIssue.Severity? = nil, _ decorate: (inout CapDecoration) -> Void) -> KeyCap {
            var model = KeyCapModel(layout: layout, layer: 0, index: index, issue: issue)
            decorate(&model.decoration)
            return KeyCap(model: model, u: 64)
        }
        func heat(_ light: String, _ dark: String) -> Token? {
            HexColor(hex: light).flatMap { l in HexColor(hex: dark).map { Token(light: l, dark: $0) } }
        }
        let caps = HStack(spacing: 14) {
            cap(19) {
                $0.badge = CapDecoration.Mark(symbol: "plus.circle.fill", color: Tokens.success, accessibilityText: "Added")
                $0.ring = Tokens.success
            }
            cap(20, issue: .warning) {
                let violet = Tokens.pair(0x7048E8, 0x7048E8)  // spec §10.1 combo palette
                $0.number = CapDecoration.Mark(symbol: "3.circle.fill", color: violet, accessibilityText: "Combo 3")
                $0.ring = violet
            }
            cap(21) { $0.opacity = 0.4 }
            cap(22) {
                $0.fill = heat("#EAF1FB", "#18202D")
                $0.count = CapDecoration.Count(text: "312", accessibilityText: "312 presses")
            }
            cap(24) {
                $0.fill = heat("#123E8C", "#A8CCFF")
                $0.count = CapDecoration.Count(text: "22k", accessibilityText: "22,044 presses")
            }
        }
        try assertImage(caps.padding(16), scheme: scheme, precision: 0.999)
    }

    private func assertBoard(_ board: BoardView, scheme: ColorScheme, testName: String = #function) throws {
        try assertImage(board.frame(width: 900, height: 420), scheme: scheme, testName: testName)
    }

    private func assertImage(
        _ content: some View, scheme: ColorScheme, precision: Float = 0.99, testName: String = #function
    ) throws {
        let view = content.background(Tokens.benchBase.color).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        assertSnapshot(
            of: image, as: .image(precision: precision, perceptualPrecision: 0.98), named: scheme == .dark ? "dark" : "light",
            testName: testName
        )
    }
}
