import Foundation
import Testing

@testable import SextantUI

/// Where the overlay HUD goes and how Settings › Keyboard stores it (spec §8.4, ADR 0062): nine spots, a distance from
/// the screen's edges, the display, the opacity and the delay. Nothing here puts a window on screen.
@MainActor
struct OverlayPlacementTests {
    /// The visible frame of a 1512 pt wide display, above a 40 pt Dock and under the menu bar.
    let visible = CGRect(x: 0, y: 40, width: 1512, height: 900)
    let size = CGSize(width: 696, height: 300)

    @Test func theNineSpotsSitAgainstTheirEdges() {
        let expected: [OverlayPosition: CGPoint] = [
            .topLeft: CGPoint(x: 72, y: 568), .top: CGPoint(x: 408, y: 568), .topRight: CGPoint(x: 744, y: 568),
            .middleLeft: CGPoint(x: 72, y: 340), .center: CGPoint(x: 408, y: 340), .middleRight: CGPoint(x: 744, y: 340),
            .bottomLeft: CGPoint(x: 72, y: 112), .bottom: CGPoint(x: 408, y: 112), .bottomRight: CGPoint(x: 744, y: 112),
        ]
        for position in OverlayPosition.allCases {
            let frame = OverlayPanel.frame(size: size, position: position, margin: 72, on: visible)
            #expect(frame.origin == expected[position], "\(position)")
            #expect(frame.size == size)
        }
    }

    @Test func theDistanceIsFromTheAnchoredEdgesOnly() {
        func origin(_ position: OverlayPosition, _ margin: CGFloat) -> CGPoint {
            OverlayPanel.frame(size: size, position: position, margin: margin, on: visible).origin
        }
        #expect(origin(.topLeft, 0) == CGPoint(x: 0, y: 640))
        #expect(origin(.bottomRight, 0) == CGPoint(x: 816, y: 40))
        #expect(origin(.topLeft, 200) == CGPoint(x: 200, y: 440))
        #expect(origin(.bottomRight, 200) == CGPoint(x: 616, y: 240))
        #expect(origin(.top, 200) == CGPoint(x: 408, y: 440), "the centre column takes it from the top only")
        #expect(origin(.middleLeft, 200) == CGPoint(x: 200, y: 340), "the middle row takes it from the left only")
        #expect(origin(.center, 0) == origin(.center, 200))
    }

    @Test func theHUDStaysOnASmallScreen() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        let hud = CGSize(width: 700, height: 300)
        #expect(OverlayPanel.frame(size: hud, position: .topLeft, margin: 200, on: small).origin == CGPoint(x: 100, y: 0))
        #expect(OverlayPanel.frame(size: hud, position: .bottomRight, margin: 200, on: small).origin == CGPoint(x: 0, y: 200))
        for position in OverlayPosition.allCases {
            #expect(small.contains(OverlayPanel.frame(size: hud, position: position, margin: 200, on: small)), "\(position)")
        }
        // Too big for it: the left edge and the top, where the header is, stay on it.
        let big = OverlayPanel.frame(size: CGSize(width: 900, height: 600), position: .bottomRight, margin: 72, on: small)
        #expect(big.minX == small.minX && big.maxY == small.maxY)
    }

    /// A display left of the main one, and a HUD whose fitting size isn't whole.
    @Test func itLandsOnWholePointsOnAnyDisplay() {
        let left = CGRect(x: -1440, y: 25, width: 1440, height: 875)
        let frame = OverlayPanel.frame(size: CGSize(width: 501, height: 200.5), position: .center, margin: 72, on: left)
        #expect(frame.origin == CGPoint(x: -971, y: 362))
        #expect(OverlayPanel.frame(size: size, position: .topRight, margin: 72, on: left).origin == CGPoint(x: -768, y: 528))
    }

    @Test func theTopRowDropsIntoPlaceAndTheOthersRise() {
        let top: Set<OverlayPosition> = [.topLeft, .top, .topRight]
        for position in OverlayPosition.allCases {
            #expect(OverlayPanel.entranceOffset(for: position) == (top.contains(position) ? 8 : -8), "\(position)")
        }
    }

    @Test func positionsKeepTheirStoredValuesAndFormAGrid() throws {
        #expect(OverlayPosition(rawValue: "bottom") == .bottom && OverlayPosition(rawValue: "top") == .top, "saved before ADR 0062")
        let rawValues = ["topLeft", "top", "topRight", "middleLeft", "center", "middleRight", "bottomLeft", "bottom", "bottomRight"]
        #expect(OverlayPosition.allCases.map(\.rawValue) == rawValues, "row by row from the top left")
        #expect(OverlayPosition.top.title == "Top Center" && OverlayPosition.bottom.title == "Bottom Center")
        #expect(OverlayPosition.center.title == "Center" && OverlayPosition.bottomRight.title == "Bottom Right")
        #expect(Set(OverlayPosition.allCases.map(\.title)).count == 9)
        for row in 0..<3 {
            for column in 0..<3 {
                let position = try #require(OverlayPosition.at(row: row, column: column))
                #expect(position.row == row && position.column == column)
            }
        }
        #expect(OverlayPosition.at(row: -1, column: 1) == nil && OverlayPosition.at(row: 1, column: 3) == nil)
    }

    @Test func settingsReadTheNewKeysWithThePanesDefaultsAndClampThem() throws {
        let suiteName = "OverlayPlacementTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let unset = OverlaySettings(defaults)
        #expect(unset == OverlaySettings())
        #expect(unset.position == .bottom && unset.margin == 72 && unset.display == .pointer && unset.opacity == 1)
        #expect(unset.delay == .milliseconds(150))

        defaults.set("bottomRight", forKey: SettingsKey.overlayPosition)
        defaults.set(120, forKey: SettingsKey.overlayMargin)
        defaults.set("main", forKey: SettingsKey.overlayDisplay)
        defaults.set(55, forKey: SettingsKey.overlayOpacity)
        defaults.set(1000, forKey: SettingsKey.overlayDelay)
        var read = OverlaySettings(defaults)
        #expect(read.position == .bottomRight && read.margin == 120 && read.display == .main && read.opacity == 0.55)
        #expect(read.delay == .milliseconds(1000))

        defaults.set("middle", forKey: SettingsKey.overlayPosition)
        defaults.set(500, forKey: SettingsKey.overlayMargin)
        defaults.set("tv", forKey: SettingsKey.overlayDisplay)
        defaults.set(5, forKey: SettingsKey.overlayOpacity)
        defaults.set(-20, forKey: SettingsKey.overlayDelay)
        read = OverlaySettings(defaults)
        #expect(read.position == .bottom && read.margin == 200 && read.display == .pointer && read.opacity == 0.3)
        #expect(read.delay == .zero)

        defaults.set(-8, forKey: SettingsKey.overlayMargin)
        defaults.set(140, forKey: SettingsKey.overlayOpacity)
        defaults.set(1001, forKey: SettingsKey.overlayDelay)
        read = OverlaySettings(defaults)
        #expect(read.margin == 0 && read.opacity == 1 && read.delay == .milliseconds(1000))
    }
}
