import Foundation
import Testing

@testable import SextantDomain

struct TrackpadSettingsTests {
    private func decode(_ json: String) throws -> TrackpadSettings {
        try JSONDecoder().decode(TrackpadSettings.self, from: Data(json.utf8))
    }

    @Test func theDefaultsAreTheTunedValues() {
        let settings = TrackpadSettings()
        #expect(!settings.isEnabled)
        #expect(settings.pointer.trackingSpeed == 1)
        #expect(settings.pointer.fastMoves == 1)
        #expect(settings.scrolling.momentumHalfLife == 230)
        #expect(settings.tapping.longestTap == 180)
        #expect(settings.tapping.doubleClickInterval == nil)
        #expect(settings.dragging.radius == 4)
        #expect(settings.dragging.window == 200)
        #expect(settings.dragging.regrip == nil)
    }

    @Test func anEmptyFileReadsAsTheDefaults() throws {
        #expect(try decode("{}") == TrackpadSettings())
        #expect(try decode(#"{"pointer": {}, "tapping": {"tapToClick": false}}"#).tapping.longestTap == 180)
    }

    @Test func followingTheMacSurvivesARoundTrip() throws {
        var settings = TrackpadSettings(isEnabled: true)
        settings.pointer.trackingSpeed = nil
        settings.tapping.doubleClickInterval = 0.4
        settings.dragging.regrip = 0.8
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(TrackpadSettings.self, from: data) == settings)
        #expect(try decode(#"{"pointer": {"trackingSpeed": null}}"#).pointer.trackingSpeed == nil)
        #expect(try decode(#"{"pointer": {"fastMoves": 0.5}}"#).pointer.trackingSpeed == 1)
    }

    @Test func aWronglyTypedValueCostsOnlyItself() throws {
        let settings = try decode(#"{"isEnabled": true, "scrolling": {"speed": "fast", "hasMomentum": false}, "pointer": 7}"#)
        #expect(settings.isEnabled)
        #expect(settings.scrolling.speed == 1)
        #expect(!settings.scrolling.hasMomentum)
        #expect(settings.pointer == TrackpadSettings.Pointer())
    }

    @Test func optionalsAreWrittenAsNulls() throws {
        let json = try #require(String(data: JSONEncoder().encode(TrackpadSettings()), encoding: .utf8))
        #expect(json.contains(#""regrip":null"#))
        #expect(json.contains(#""doubleClickInterval":null"#))
    }

    @Test func clampingHoldsEveryValueToItsRange() {
        var settings = TrackpadSettings()
        settings.pointer.trackingSpeed = 40
        settings.rotation = 720
        settings.pointer.fastMoves = -1
        settings.pointer.padScale = 0
        settings.scrolling.momentumHalfLife = 0
        settings.tapping.longestTap = 10_000
        settings.dragging.radius = -3
        settings.dragging.regrip = 99
        settings.pointer.fastMoveThreshold = 1
        settings.scrolling.speed = 100
        settings.tapping.tapMovement = 0
        settings.tapping.doubleClickInterval = 60
        settings.dragging.window = 0
        let clamped = settings.clamped
        #expect(clamped.pointer.trackingSpeed == 3)
        #expect(clamped.rotation == 180)
        #expect(clamped.pointer.fastMoves == 0)
        #expect(clamped.pointer.padScale == 0.5)
        #expect(clamped.scrolling.momentumHalfLife == 50)
        #expect(clamped.tapping.longestTap == 400)
        #expect(clamped.dragging.radius == 1)
        #expect(clamped.dragging.regrip == 2)
        #expect(clamped.pointer.fastMoveThreshold == 40)
        #expect(clamped.scrolling.speed == 4)
        #expect(clamped.tapping.tapMovement == 0.3)
        #expect(clamped.tapping.doubleClickInterval == 5)
        #expect(clamped.dragging.window == 100)
        #expect(TrackpadSettings().clamped == TrackpadSettings())
    }

    @Test func nonFiniteValuesClampToo() {
        var settings = TrackpadSettings()
        settings.pointer.padScale = .infinity
        settings.scrolling.speed = -.infinity
        #expect(settings.clamped.pointer.padScale == 4)
        #expect(settings.clamped.scrolling.speed == 0.25)
        settings.tapping.tapMovement = .nan
        #expect(settings.clamped.tapping.tapMovement == 0.3)
    }
}
