import Foundation
import Testing

@testable import SextantDomain

/// A pretend Navigator: frames every 6.5 ms, ticks every 8 ms while the engine wants them, and everything it said.
private struct Pad {
    var engine: GestureEngine
    var time = 100.0
    var scan = 1000
    var intents: [PointerIntent] = []

    init(_ settings: TrackpadSettings = TrackpadSettings(isEnabled: true), natural: Bool = true) {
        engine = GestureEngine(
            configuration: GestureConfiguration(
                settings: settings, curves: .standardTrackpad, systemTrackingSpeed: 0.6875, systemNaturalScrolling: natural,
                systemDoubleClickInterval: 0.5))
    }

    mutating func frame(_ contacts: [TrackpadContact]) {
        time += 0.0065
        scan = (scan + 65) % 65536
        intents += engine.handle(TrackpadFrame(contacts: contacts, scanTime: scan, timestamp: time))
    }

    /// One finger along a straight line in `reports` reports (pad units), then a lift.
    mutating func stroke(from start: (Double, Double), to end: (Double, Double), reports: Int, id: Int = 0, lift: Bool = true) {
        for i in 0..<reports {
            let t = reports == 1 ? 1 : Double(i) / Double(reports - 1)
            frame([TrackpadContact(id: id, x: start.0 + (end.0 - start.0) * t, y: start.1 + (end.1 - start.1) * t)])
        }
        if lift { frame([]) }
    }

    mutating func tap(at point: (Double, Double) = (1000, 1000), reports: Int = 7) {
        stroke(from: point, to: point, reports: reports)
    }

    /// Two fingers 20 mm apart moving together, then a lift.
    mutating func twoFingers(from start: (Double, Double), to end: (Double, Double), reports: Int) {
        for i in 0..<reports {
            let t = Double(i) / Double(max(reports - 1, 1))
            let x = start.0 + (end.0 - start.0) * t
            let y = start.1 + (end.1 - start.1) * t
            frame([TrackpadContact(id: 0, x: x, y: y), TrackpadContact(id: 1, x: x + 1000, y: y)])
        }
        frame([])
    }

    /// Lets `seconds` pass, ticking every 8 ms while the engine asks.
    mutating func wait(_ seconds: Double) {
        let until = time + seconds
        while time < until {
            time += 0.008
            if engine.needsTicks { intents += engine.tick(at: time) }
        }
    }

    var buttons: [PointerIntent] { intents.filter { if case .button = $0 { true } else { false } } }
    var moves: [(dx: Double, dy: Double, dragging: Bool)] {
        intents.compactMap { if case let .move(dx, dy, dragging) = $0 { (dx, dy, dragging) } else { nil } }
    }
    var scrolls: [(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase)] {
        intents.compactMap { if case let .scroll(dx, dy, phase, momentum) = $0 { (dx, dy, phase, momentum) } else { nil } }
    }
}

private func click(_ button: PointerButton, _ count: Int) -> [PointerIntent] {
    [.button(button, isDown: true, clickCount: count), .button(button, isDown: false, clickCount: count)]
}

struct GestureEngineTests {
    // MARK: Taps

    @Test func aShortStillTouchLeftClicks() {
        var pad = Pad()
        pad.tap()
        #expect(pad.buttons == click(.left, 1))
        #expect(pad.moves.isEmpty)
    }

    @Test func tapsCountUpToATripleClick() {
        var pad = Pad()
        for _ in 0..<4 {
            pad.tap()
            pad.wait(0.1)
        }
        #expect(pad.buttons == click(.left, 1) + click(.left, 2) + click(.left, 3) + click(.left, 3))
    }

    @Test func tapsFurtherApartThanTheDoubleClickIntervalAreSingleClicks() {
        var pad = Pad()
        pad.tap()
        pad.wait(0.6)
        pad.tap()
        #expect(pad.buttons == click(.left, 1) + click(.left, 1))
    }

    @Test func aTouchThatMovesIsNotATap() {
        var pad = Pad()
        pad.stroke(from: (1000, 1000), to: (1100, 1000), reports: 7)  // about 2 mm
        #expect(pad.buttons.isEmpty)
    }

    @Test func aLongTouchIsNotATap() {
        var pad = Pad()
        pad.tap(reports: 40)  // 260 ms
        #expect(pad.buttons.isEmpty)
    }

    @Test func tapToClickOffNeverClicks() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.tapping.tapToClick = false
        var pad = Pad(settings)
        pad.tap()
        #expect(pad.buttons.isEmpty)
    }

    @Test func aTwoFingerTapRightClicks() {
        var pad = Pad()
        pad.twoFingers(from: (800, 1000), to: (800, 1000), reports: 15)
        #expect(pad.buttons == click(.right, 1))
        #expect(pad.scrolls.isEmpty)
    }

    @Test func twoFingerRightClickOffMakesNoClick() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.tapping.twoFingerRightClick = false
        var pad = Pad(settings)
        pad.twoFingers(from: (800, 1000), to: (800, 1000), reports: 15)
        #expect(pad.buttons.isEmpty)
    }

    // MARK: Pointer

    @Test func oneFingerMovesThePointerAfterItSettles() {
        var pad = Pad()
        pad.stroke(from: (500, 1000), to: (1500, 1000), reports: 40)
        let total = pad.moves.reduce(0) { $0 + $1.dx }
        #expect(total > 0)
        #expect(pad.moves.allSatisfy { abs($0.dy) < 1e-9 && !$0.dragging })
        // The settle and the lift-off filter drop the first and last reports, so less than the whole stroke arrives.
        #expect(pad.moves.count < 39)
    }

    @Test func aSecondContactBlipDoesNotStopThePointer() {
        var pad = Pad()
        for i in 0..<30 {
            let x = 500 + Double(i) * 20
            var contacts = [TrackpadContact(id: 0, x: x, y: 1000)]
            if i == 15 || i == 16 { contacts.append(TrackpadContact(id: 1, x: x + 900, y: 1000)) }
            pad.frame(contacts)
        }
        let after = pad.moves.count
        for i in 30..<40 { pad.frame([TrackpadContact(id: 0, x: 500 + Double(i) * 20, y: 1000)]) }
        #expect(pad.moves.count > after)
        #expect(pad.scrolls.isEmpty)
    }

    @Test func aSplitFingerCountsAsOne() {
        var pad = Pad()
        for i in 0..<30 {
            let x = 500 + Double(i) * 20
            pad.frame([TrackpadContact(id: 0, x: x, y: 1000), TrackpadContact(id: 1, x: x + 30, y: 1000)])
        }
        #expect(!pad.moves.isEmpty)
        #expect(pad.scrolls.isEmpty)
    }

    @Test func fasterFingersGetMorePointsPerMillimeter() {
        let engine = Pad().engine
        let speeds = [5.0, 20, 50, 100, 180, 300]
        let gains = speeds.map { engine.pointsPerMillimeter(atFingerSpeed: $0) }
        #expect(gains == gains.sorted())
        // Apple's curve at tracking speed 1.0, the default: the curve closest to the one tuned on the hardware.
        let expected = [4.5, 7.4, 13.4, 23.5, 40.0, 54.7]
        for (gain, want) in zip(gains, expected) { #expect(abs(gain - want) < 0.1, "\(gain) vs \(want)") }
    }

    @Test func fastMovesOnlyChangesSpeedsAboveItsThreshold() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.pointer.fastMoves = 0.5
        let softened = Pad(settings).engine
        let apple = Pad().engine
        #expect(softened.pointsPerMillimeter(atFingerSpeed: 80) == apple.pointsPerMillimeter(atFingerSpeed: 80))
        #expect(softened.pointsPerMillimeter(atFingerSpeed: 200) < apple.pointsPerMillimeter(atFingerSpeed: 200))
        #expect(softened.pointsPerMillimeter(atFingerSpeed: 200) > apple.pointsPerMillimeter(atFingerSpeed: 100))
    }

    @Test func followingTheMacUsesItsTrackingSpeed() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.pointer.trackingSpeed = nil
        let engine = Pad(settings).engine
        #expect(engine.configuration.curve.parameters.index == 0.6875)
    }

    @Test func aSingleFastReportIsClamped() {
        var pad = Pad()
        pad.stroke(from: (500, 1000), to: (700, 1000), reports: 30, lift: false)
        let steady = pad.moves.last?.dx ?? 0
        pad.frame([TrackpadContact(id: 0, x: 1700, y: 1000)])  // a 20 mm jump in one report
        pad.frame([TrackpadContact(id: 0, x: 1707, y: 1000)])
        pad.frame([TrackpadContact(id: 0, x: 1714, y: 1000)])
        #expect(pad.moves.allSatisfy { $0.dx < 40 * max(steady, 1) })
        #expect(pad.moves.reduce(0) { $0 + $1.dx } < 200)
    }

    @Test func rotationTurnsMovesAndScrolls() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.rotation = 90  // the pad is turned a quarter clockwise: its "right" is the user's "down"
        var pad = Pad(settings)
        pad.stroke(from: (500, 1000), to: (1500, 1000), reports: 40)
        #expect(pad.moves.reduce(0) { $0 + $1.dy } > 100)
        #expect(pad.moves.allSatisfy { abs($0.dx) < 1e-6 })
        var scroller = Pad(settings)
        scroller.twoFingers(from: (400, 600), to: (1400, 600), reports: 25)
        let changed = scroller.scrolls.filter { $0.phase == .changed }
        #expect(changed.reduce(0) { $0 + $1.dy } > 0)
        #expect(changed.allSatisfy { abs($0.dx) < 1e-6 })
    }

    @Test func rotationLeavesTapsAndDragsAlone() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.rotation = -135
        var pad = Pad(settings)
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1010, 1000), to: (1600, 1000), reports: 30)
        #expect(pad.buttons.count == 4)  // click, then drag down and up
        #expect(pad.moves.contains { $0.dragging })
    }

    // MARK: Dragging

    @Test func tapThenTouchWhereYouTappedDrags() {
        var pad = Pad()
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1010, 1000), to: (1600, 1000), reports: 30)
        #expect(
            pad.buttons == click(.left, 1) + [.button(.left, isDown: true, clickCount: 1), .button(.left, isDown: false, clickCount: 1)])
        #expect(pad.moves.contains { $0.dragging })
        #expect(!pad.engine.isDragging)
    }

    @Test func tapThenTouchElsewhereOnlyMoves() {
        var pad = Pad()
        pad.tap(at: (1600, 1000))
        pad.wait(0.05)
        pad.stroke(from: (400, 1000), to: (1000, 1000), reports: 30)  // a reposition: 23 mm away
        #expect(pad.buttons == click(.left, 1))
        #expect(pad.moves.allSatisfy { !$0.dragging })
    }

    @Test func tapThenTouchTooLateOnlyMoves() {
        var pad = Pad()
        pad.tap(at: (1000, 1000))
        pad.wait(0.3)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30)
        #expect(pad.buttons == click(.left, 1))
    }

    @Test func aSloppyTapDoesNotArmADrag() {
        var pad = Pad()
        pad.stroke(from: (1000, 1000), to: (1035, 1000), reports: 7)  // clicks (0.7 mm) but moved past the settle
        pad.wait(0.05)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30)
        #expect(pad.buttons == click(.left, 1))
    }

    @Test func tapThenDragOffNeverDrags() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.dragging.tapThenDrag = false
        var pad = Pad(settings)
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30)
        #expect(pad.buttons == click(.left, 1))
    }

    @Test func withRegripADragSurvivesALiftAndATouchCarriesOn() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.dragging.regrip = 0.6
        var pad = Pad(settings)
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30)
        #expect(pad.engine.isDragging)
        pad.wait(0.2)
        pad.stroke(from: (600, 1000), to: (1400, 1000), reports: 30, lift: false)
        #expect(pad.engine.isDragging)
        #expect(pad.buttons.count == 3)  // the tap's click, then the drag's down
        pad.frame([])
        pad.wait(0.7)
        #expect(!pad.engine.isDragging)
        #expect(pad.buttons.last == .button(.left, isDown: false, clickCount: 1))
    }

    @Test func withRegripATapDropsTheDrag() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.dragging.regrip = 0.6
        var pad = Pad(settings)
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30)
        pad.wait(0.1)
        pad.tap(at: (900, 900))
        #expect(!pad.engine.isDragging)
        #expect(pad.buttons.last == .button(.left, isDown: false, clickCount: 1))
    }

    @Test func turningRegripOffReleasesAWaitingDrag() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.dragging.regrip = 2
        var pad = Pad(settings)
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30)
        #expect(pad.engine.isDragging)
        settings.dragging.regrip = nil
        pad.engine.configuration = Pad(settings).engine.configuration
        pad.wait(0.02)
        #expect(!pad.engine.isDragging)
    }

    // MARK: Scrolling

    @Test func twoFingersScrollWithPhasesThenMomentum() {
        var pad = Pad()
        pad.twoFingers(from: (800, 1400), to: (800, 400), reports: 25)  // up 20 mm, fast
        pad.wait(2)
        let phases = pad.scrolls.map(\.phase)
        #expect(phases.first == .began)
        #expect(phases.contains(.changed))
        #expect(pad.scrolls.contains { $0.phase == .ended })
        let glide = pad.scrolls.filter { $0.momentum != .none }
        #expect(glide.first?.momentum == .began)
        #expect(glide.last?.momentum == .ended)
        #expect(!pad.engine.needsTicks)
        #expect(pad.buttons.isEmpty)
        #expect(pad.moves.isEmpty)
    }

    @Test func naturalScrollingFollowsTheFingers() {
        var natural = Pad()
        natural.twoFingers(from: (800, 400), to: (800, 1400), reports: 25)  // fingers move down
        var traditional = Pad(natural: false)
        traditional.twoFingers(from: (800, 400), to: (800, 1400), reports: 25)
        #expect(natural.scrolls.filter { $0.phase == .changed }.reduce(0) { $0 + $1.dy } > 0)
        #expect(traditional.scrolls.filter { $0.phase == .changed }.reduce(0) { $0 + $1.dy } < 0)
    }

    @Test func invertingAnAxisFlipsOnlyThatAxis() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.scrolling.invertsVertical = true
        var pad = Pad(settings)
        pad.twoFingers(from: (800, 400), to: (800, 1400), reports: 25)
        #expect(pad.scrolls.filter { $0.phase == .changed }.reduce(0) { $0 + $1.dy } < 0)
    }

    @Test func aMostlyVerticalScrollLocksToVertical() {
        var pad = Pad()
        pad.twoFingers(from: (800, 400), to: (900, 1400), reports: 30)
        let late = pad.scrolls.filter { $0.phase == .changed }.suffix(10)
        #expect(late.allSatisfy { $0.dx == 0 })
    }

    @Test func touchingStopsMomentum() {
        var pad = Pad()
        pad.twoFingers(from: (800, 1400), to: (800, 400), reports: 25)
        pad.wait(0.05)
        #expect(pad.engine.needsTicks)
        pad.frame([TrackpadContact(id: 0, x: 1000, y: 1000)])
        #expect(pad.scrolls.last?.momentum == .ended)
    }

    @Test func momentumOffStopsAtTheLift() {
        var settings = TrackpadSettings(isEnabled: true)
        settings.scrolling.hasMomentum = false
        var pad = Pad(settings)
        pad.twoFingers(from: (800, 1400), to: (800, 400), reports: 25)
        pad.wait(1)
        #expect(pad.scrolls.allSatisfy { $0.momentum == .none })
    }

    // MARK: Review findings (2026-11-14)

    /// A drag that turns into a two-finger scroll ends its scroll before the button comes up, and launches no momentum.
    @Test func aDragThatBecomesAScrollEndsTheScroll() {
        var pad = Pad()
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30, lift: false)
        #expect(pad.engine.isDragging)
        for i in 0..<20 {
            let y = 1000 + Double(i) * 30
            pad.frame([TrackpadContact(id: 0, x: 1600, y: y), TrackpadContact(id: 1, x: 600, y: y)])
        }
        pad.frame([])
        pad.wait(1)
        let phases = pad.scrolls.map(\.phase)
        #expect(phases.first == .began)
        #expect(phases.contains(.ended))
        #expect(pad.scrolls.allSatisfy { $0.momentum == .none })
        #expect(!pad.engine.isDragging)
        #expect(pad.engine.reset().isEmpty)
    }

    /// Short second-contact blips don't add up: the pointer keeps moving after many of them.
    @Test func manySecondContactBlipsDontFreezeThePointer() {
        var pad = Pad()
        for i in 0..<120 {
            let x = 400 + Double(i) * 12
            var contacts = [TrackpadContact(id: 0, x: x, y: 1000)]
            if i % 20 < 3, i >= 20 { contacts.append(TrackpadContact(id: 1, x: 300, y: 1800)) }
            pad.frame(contacts)
        }
        let before = pad.moves.count
        for i in 120..<140 { pad.frame([TrackpadContact(id: 0, x: 400 + Double(i) * 12, y: 1000)]) }
        #expect(pad.moves.count >= before + 15)
        #expect(pad.scrolls.isEmpty)
    }

    /// One finger left resting after a scroll means the scroll stopped: no momentum from its old speed.
    @Test func restingAfterAScrollLaunchesNoMomentum() {
        var pad = Pad()
        for i in 0..<20 {
            let y = 1500 - Double(i) * 50
            pad.frame([TrackpadContact(id: 0, x: 800, y: y), TrackpadContact(id: 1, x: 1800, y: y)])
        }
        for _ in 0..<150 { pad.frame([TrackpadContact(id: 0, x: 800, y: 550)]) }
        pad.frame([])
        pad.wait(1)
        #expect(pad.scrolls.contains { $0.phase == .ended })
        #expect(pad.scrolls.allSatisfy { $0.momentum == .none })
    }

    /// A report time-stamped a fraction of a millisecond after the last can't fling the page.
    @Test func aGlitchedScanTimeCantFlingTheScroll() {
        var slow = Pad()
        for i in 0..<20 {
            let y = 1500 - Double(i) * 6
            slow.frame([TrackpadContact(id: 0, x: 800, y: y), TrackpadContact(id: 1, x: 1800, y: y)])
        }
        slow.time += 0.0001
        slow.scan += 1
        slow.intents += slow.engine.handle(
            TrackpadFrame(
                contacts: [TrackpadContact(id: 0, x: 800, y: 1365), TrackpadContact(id: 1, x: 1800, y: 1365)],
                scanTime: slow.scan, timestamp: slow.time))
        slow.frame([])
        slow.wait(1)
        let glide = slow.scrolls.filter { $0.momentum != .none }.map { abs($0.dy) }
        #expect((glide.max() ?? 0) < 10)
    }

    @Test func noMomentumStepWithoutTimePassing() {
        var pad = Pad()
        pad.twoFingers(from: (800, 1400), to: (800, 400), reports: 25)
        let lift = pad.time
        pad.intents += pad.engine.tick(at: lift)
        pad.intents += pad.engine.tick(at: lift)
        #expect(pad.scrolls.allSatisfy { $0.momentum == .none })
    }

    // MARK: Robustness

    @Test func aTouchWithoutALiftReportEndsAfterASilence() {
        var pad = Pad()
        pad.stroke(from: (1000, 1000), to: (1000, 1000), reports: 7, lift: false)
        #expect(pad.engine.needsTicks)
        pad.wait(0.2)
        #expect(pad.buttons == click(.left, 1))
        #expect(!pad.engine.needsTicks)
    }

    @Test func resetLetsGoOfAHeldDrag() {
        var pad = Pad()
        pad.tap(at: (1000, 1000))
        pad.wait(0.05)
        pad.stroke(from: (1000, 1000), to: (1600, 1000), reports: 30, lift: false)
        #expect(pad.engine.isDragging)
        let out = pad.engine.reset()
        #expect(out.contains(.button(.left, isDown: false, clickCount: 1)))
        #expect(!pad.engine.isDragging)
    }

    @Test func aWrappingScanClockStillTimesReports() {
        var pad = Pad()
        pad.scan = 65500
        pad.stroke(from: (500, 1000), to: (1500, 1000), reports: 40)
        #expect(!pad.moves.isEmpty)
        #expect(pad.moves.allSatisfy { $0.dx.isFinite && $0.dx < 200 })
    }

    // MARK: The user's capture

    /// Research 06's 30 s capture: taps, a right-click, scrolls and pointer moves, nothing infinite.
    @Test func replayingTheCapturedTouches() throws {
        var pad = Pad()
        for frame in try CapturedTouches.frames() {
            pad.time = frame.timestamp
            pad.intents += pad.engine.handle(frame)
            if pad.engine.needsTicks { pad.intents += pad.engine.tick(at: frame.timestamp) }
        }
        pad.wait(2)
        var lefts = 0
        var rights = 0
        for case let .button(button, true, _) in pad.buttons {
            if button == .left { lefts += 1 } else { rights += 1 }
        }
        #expect(lefts >= 15)
        #expect(rights == 1)
        #expect(pad.scrolls.contains { $0.phase == .began })
        #expect(pad.moves.count > 500)
        #expect(pad.moves.allSatisfy { $0.dx.isFinite && $0.dy.isFinite })
        #expect(pad.scrolls.allSatisfy { $0.dx.isFinite && $0.dy.isFinite })
        #expect(!pad.engine.isDragging)
        // Every button that went down came up.
        var down = 0
        for case let .button(_, isDown, _) in pad.buttons { down += isDown ? 1 : -1 }
        #expect(down == 0)
    }
}

/// `docs/research/navigator/ptp-capture-2026-11-14.txt`: the user's own touches (research 06, spike 2).
enum CapturedTouches {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/research/navigator/ptp-capture-2026-11-14.txt")

    static func frames() throws -> [TrackpadFrame] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: " ")
            guard fields.count >= 2, let time = Double(fields[0]), let scan = Int(fields[1]) else { return nil }
            let contacts = fields.dropFirst(2).compactMap { field -> TrackpadContact? in
                let parts = field.split(separator: ":").compactMap { Double($0) }
                return parts.count == 3 ? TrackpadContact(id: Int(parts[0]), x: parts[1], y: parts[2]) : nil
            }
            return TrackpadFrame(contacts: contacts, scanTime: scan, timestamp: time)
        }
    }
}
