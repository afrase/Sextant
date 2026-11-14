import CoreGraphics
import Foundation
import SextantDomain
import Testing

@testable import SextantPointer

/// Events are built, never posted: no Accessibility prompt in tests (AGENTS.md).
extension PointerEventBuilder {
    /// With the pointer at (100, 100), no button held, and every display unbounded.
    fileprivate mutating func events(_ intent: PointerIntent, buttonHeld: Bool = false) -> [CGEvent] {
        events(for: intent, cursor: CGPoint(x: 100, y: 100), buttonHeld: buttonHeld, clamp: { point, _ in point })
    }
}

struct PointerOutputTests {
    @Test func movesCarryFractionsOver() {
        var output = PointerEventBuilder(source: nil)
        #expect(output.events(.move(dx: 0.4, dy: 0, dragging: false)).isEmpty)
        let events = output.events(.move(dx: 0.7, dy: 0, dragging: false))
        #expect(events.count == 1)
        #expect(events.first?.getIntegerValueField(.mouseEventDeltaX) == 1)
        #expect(events.first?.type == .mouseMoved)
    }

    @Test func aDragMovesAsADraggedEvent() {
        var output = PointerEventBuilder(source: nil)
        let events = output.events(.move(dx: 3, dy: -2, dragging: true))
        #expect(events.first?.type == .leftMouseDragged)
        #expect(events.first?.getIntegerValueField(.mouseEventDeltaY) == -2)
    }

    @Test func aHeldClickKeyTurnsMovesIntoDrags() {
        var output = PointerEventBuilder(source: nil)
        #expect(output.events(.move(dx: 3, dy: 0, dragging: false), buttonHeld: true).first?.type == .leftMouseDragged)
    }

    @Test func clicksCarryTheirCount() {
        var output = PointerEventBuilder(source: nil)
        let down = output.events(.button(.left, isDown: true, clickCount: 2)).first
        #expect(down?.type == .leftMouseDown)
        #expect(down?.getIntegerValueField(.mouseEventClickState) == 2)
        let right = output.events(.button(.right, isDown: false, clickCount: 1)).first
        #expect(right?.type == .rightMouseUp)
    }

    @Test func scrollsAreContinuousWithPhases() {
        var output = PointerEventBuilder(source: nil)
        let began = output.events(.scroll(dx: 0, dy: 0, phase: .began, momentum: .none)).first
        #expect(began?.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
        #expect(began?.getIntegerValueField(.scrollWheelEventScrollPhase) == 1)
        let changed = output.events(.scroll(dx: -2.5, dy: 7.6, phase: .changed, momentum: .none)).first
        #expect(changed?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 7)
        #expect(changed?.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == -2)
        #expect(changed?.getIntegerValueField(.scrollWheelEventScrollPhase) == 2)
        let glide = output.events(.scroll(dx: 0, dy: 0.5, phase: .none, momentum: .continued)).first
        #expect(glide?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 1)  // 0.6 left over + 0.5
        #expect(glide?.getIntegerValueField(.scrollWheelEventMomentumPhase) == 2)
    }

    @Test func phasesMapToQuartzValues() {
        #expect([ScrollPhase.none, .began, .changed, .ended].map(PointerEventBuilder.value(of:)) == [0, 1, 2, 4])
        #expect([MomentumPhase.none, .began, .continued, .ended].map(PointerEventBuilder.value(of:)) == [0, 1, 2, 3])
    }

    @Test func thePointerStaysOnADisplay() {
        let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 500, height: 400)]
        #expect(DisplayBounds.clamp(CGPoint(x: 1200, y: 100), from: CGPoint(x: 990, y: 100), to: displays) == CGPoint(x: 1200, y: 100))
        #expect(DisplayBounds.clamp(CGPoint(x: 1200, y: 600), from: CGPoint(x: 1200, y: 390), to: displays) == CGPoint(x: 1200, y: 399))
        #expect(DisplayBounds.clamp(CGPoint(x: -5, y: 900), from: CGPoint(x: 5, y: 795), to: displays) == CGPoint(x: 0, y: 799))
    }

    @Test func registryCurvesReadAsFixedPoint() {
        let set = SystemPointerReader.curves(from: [
            ["HIDAccelIndex": 0, "HIDAccelGainLinear": 65536],
            [
                "HIDAccelIndex": 65536, "HIDAccelGainLinear": 65536,
                "HIDAccelGainParabolic": 32768,
            ],
            ["HIDAccelIndex": "junk"],
        ])
        #expect(set?.curves.count == 2)
        #expect(set?.curves.last?.gains[1] == 0.5)
        #expect(SystemPointerReader.curves(from: []) == nil)
    }

    @Test func missingSystemSettingsAreMacOSDefaults() async throws {
        let suite = "com.sextant.tests.pointer.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1.5, forKey: "com.apple.trackpad.scaling")
        let reader = SystemPointerReader(defaults: { UserDefaults(suiteName: suite) ?? .standard })
        let preferences = await reader.current()
        #expect(preferences.trackingSpeed == 1.5)
        #expect(preferences.doubleClickInterval > 0)
    }
}
