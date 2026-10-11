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

    private func assertBoard(_ board: BoardView, scheme: ColorScheme, testName: String = #function) throws {
        let view = board.frame(width: 900, height: 420).background(Tokens.benchBase.color).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        assertSnapshot(
            of: image, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: scheme == .dark ? "dark" : "light", testName: testName
        )
    }
}
