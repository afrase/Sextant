import Foundation

/// A mouse button the engine presses.
public enum PointerButton: Hashable, Sendable { case left, right }

/// Where a scroll gesture is: fingers down and moving, then lifted.
public enum ScrollPhase: Hashable, Sendable { case none, began, changed, ended }

/// The glide after a scroll's fingers lift.
public enum MomentumPhase: Hashable, Sendable { case none, began, continued, ended }

/// What the engine asks the Mac to do. Distances are in points.
public enum PointerIntent: Hashable, Sendable {
    /// Move the pointer; `dragging` while the engine holds the left button for a drag.
    case move(dx: Double, dy: Double, dragging: Bool)
    case button(PointerButton, isDown: Bool, clickCount: Int)
    /// Scroll by a continuous (pixel) amount. Positive `dy` shows content above, positive `dx` content to the left, as a
    /// scroll wheel turned up or left does.
    case scroll(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase)
}

/// The engine's inputs that aren't touches: the settings and what the Mac says, resolved into the values in use.
public struct GestureConfiguration: Hashable, Sendable {
    /// The settings, clamped. A configuration is built whole, so the curve always matches them.
    public let settings: TrackpadSettings
    public let curve: PointerCurve
    /// Content follows the fingers (System Settings' natural scrolling).
    public let naturalScrolling: Bool
    /// Seconds between clicks of a double-click.
    public let doubleClickInterval: Double

    /// - Parameters:
    ///   - curves: the Mac's trackpad curve set, or the standard one.
    ///   - systemTrackingSpeed, systemNaturalScrolling, systemDoubleClickInterval: System Settings' values, used where
    ///     the settings follow the Mac.
    public init(
        settings: TrackpadSettings, curves: PointerCurveSet, systemTrackingSpeed: Double, systemNaturalScrolling: Bool,
        systemDoubleClickInterval: Double
    ) {
        let settings = settings.clamped
        self.settings = settings
        curve = curves.curve(at: settings.pointer.trackingSpeed ?? systemTrackingSpeed)
        naturalScrolling = systemNaturalScrolling
        let systemInterval = systemDoubleClickInterval.isFinite && systemDoubleClickInterval > 0 ? systemDoubleClickInterval : 0.5
        doubleClickInterval = settings.tapping.doubleClickInterval ?? systemInterval
    }
}

/// Turns the Navigator trackpad's touches into pointer moves, clicks, drags and scrolls (ADR 0068, research 06). A pure
/// state machine: feed it every frame in order (`handle`) and, while `needsTicks`, the time about every 8 ms (`tick`).
///
/// - One finger moves the pointer along Apple's trackpad curve. The first moments of a touch and the reports just
///   before a lift are dropped, and the speed the curve sees is smoothed with single-report spikes clamped.
/// - Two fingers that stay down together about 40 ms scroll, with momentum after they lift; a shorter second contact
///   is noise and ignored.
/// - A short touch that barely moves is a tap: one finger left-clicks, two right-click.
/// - A touch landing where a clean tap just was, soon after it, drags until the finger lifts, or until the re-grip
///   time runs out when that's on.
public struct GestureEngine: Sendable {
    public var configuration: GestureConfiguration {
        didSet { if configuration.settings.dragging.regrip == nil, regripDeadline != nil { pendingRelease = true } }
    }

    public init(configuration: GestureConfiguration) { self.configuration = configuration }

    /// The engine holds the left button for a drag.
    public var isDragging: Bool { dragging }

    /// Something is under way that `tick` moves on: a touch (to notice one that stops reporting), momentum, or a
    /// drag waiting for its re-grip.
    public var needsTicks: Bool { inTouch || momentum != nil || regripDeadline != nil || pendingRelease }

    // MARK: Tuning the user doesn't set (research 06)

    /// Two contacts closer than this (about 1.2 mm) are one finger the sensor split.
    static let splitContactDistance = 60.0
    /// A touch moves the pointer only after this much travel (pad units) or time.
    static let settleTravel = 25.0
    static let settleTime = 0.12
    /// Two contacts must be down together this long before the touch is two-finger, and at least `rightClickTime` for
    /// a two-finger tap.
    static let twoFingerTime = 0.04
    static let rightClickTime = 0.025
    /// Travel (pad units) a drag needs before the button goes down, so a double-tap still clicks twice.
    static let dragStartTravel = 40.0
    /// Speed smoothing, and the spike clamp: a report faster than this many times the smoothed speed (or the floor, in
    /// mm/s) is held to it.
    static let speedSmoothing = 0.025
    static let spikeFactor = 3.0
    static let spikeFloor = 80.0
    /// Reports held back to drop the fingertip's roll at lift-off.
    static let liftOffReports = 2
    /// Scroll start (pad units, both fingers' mean) and the travel after which it locks to a clearly dominant axis.
    static let scrollStartTravel = 50.0
    static let axisLockTravel = 300.0
    /// Momentum starts above, is capped at, and stops below these speeds (points per second).
    static let momentumStartSpeed = 150.0
    static let momentumCap = 6000.0
    static let momentumStopSpeed = 12.0
    /// How much each report moves the scroll speed toward its own (an exponential average).
    static let velocitySmoothing = 0.35
    /// Points a double-click's taps may be apart, measured as pointer movement between them.
    static let doubleClickSlop = 6.0
    /// A touch that stops reporting this long without a lift is over.
    static let staleTouch = 0.1
    /// A report gap outside these bounds counts as one report interval: the pad reports every 6.5 ms, so a gap under
    /// 2 ms is a glitch that would make one report look enormously fast.
    static let reportInterval = 0.0065
    static let shortestGap = 0.002
    static let longestGap = 0.05

    // MARK: State

    private var inTouch = false
    private var touchStart = 0.0
    private var lastFrameTime = 0.0
    private var lastScan: Int?
    private var firstContact: TrackpadContact?
    private var previous: [Int: TrackpadContact] = [:]
    private var travel = 0.0
    /// How long two contacts have been down together without a break, the longest such run in this touch, and whether
    /// the touch became two-finger (a run longer than `twoFingerTime`). Short runs are noise and don't add up.
    private var twoFingerRun = 0.0
    private var longestTwoFingerRun = 0.0
    private var isTwoFingerTouch = false
    private var pointerLive = false
    private var speed = 0.0
    private var held: [(dx: Double, dy: Double)] = []

    private var lastTapEnd = -Double.infinity
    private var lastTapClicks = 0
    private var lastTapContact: TrackpadContact?
    private var lastTapClean = false
    private var movedSinceTap = 0.0

    private var dragArmed = false
    private var dragging = false
    private var dragContinued = false
    private var regripDeadline: Double?
    private var pendingRelease = false

    private enum Axis { case free, horizontal, vertical }
    private var scrolling = false
    private var scrollAxis = Axis.free
    private var scrollTravel = (x: 0.0, y: 0.0)
    private var scrollVelocity = (x: 0.0, y: 0.0)
    private var momentum: (velocity: (x: Double, y: Double), lastTick: Double, started: Bool)?

    // MARK: Input

    public mutating func handle(_ frame: TrackpadFrame) -> [PointerIntent] {
        var out: [PointerIntent] = []
        let dt = interval(to: frame)
        lastFrameTime = frame.timestamp
        let contacts = Self.mergingSplitContacts(frame.contacts)

        if !inTouch {
            guard !contacts.isEmpty else { return out }
            begin(at: frame.timestamp, first: contacts[0], into: &out)
        }

        let now = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var mx = 0.0
        var my = 0.0
        var shared = 0.0
        for (id, contact) in now {
            guard let before = previous[id] else { continue }
            mx += contact.x - before.x
            my += contact.y - before.y
            shared += 1
        }
        if shared > 0 {
            mx /= shared
            my /= shared
            travel += hypot(mx, my)
            // A pad mounted at an angle: turn the motion back so the user's "up" is up. Distances don't change, so taps,
            // the drag radius and the settle are unaffected.
            let angle = configuration.settings.rotation * .pi / 180
            if angle != 0 {
                (mx, my) = (mx * cos(angle) - my * sin(angle), mx * sin(angle) + my * cos(angle))
            }
        }
        previous = now

        if now.isEmpty {
            end(at: frame.timestamp, into: &out)
            return out
        }

        let twoNow = now.count >= 2 && shared >= 2
        if twoNow {
            twoFingerRun += dt
            longestTwoFingerRun = max(longestTwoFingerRun, twoFingerRun)
            if twoFingerRun > Self.twoFingerTime { isTwoFingerTouch = true }
        } else {
            twoFingerRun = 0
        }
        if isTwoFingerTouch {
            if twoNow {
                scroll(mx: mx, my: my, dt: dt, into: &out)
            } else {
                // One finger left resting: the scroll isn't moving, so momentum mustn't launch from its old speed.
                scrollVelocity.x *= 1 - Self.velocitySmoothing
                scrollVelocity.y *= 1 - Self.velocitySmoothing
            }
            return out
        }
        if now.count >= 2 { return out }

        movePointer(mx: mx, my: my, dt: dt, at: frame.timestamp, into: &out)
        return out
    }

    /// Moves time on: momentum, the re-grip timeout, and a touch whose lift report never came.
    public mutating func tick(at time: Double) -> [PointerIntent] {
        var out: [PointerIntent] = []
        if pendingRelease {
            pendingRelease = false
            regripDeadline = nil
            if dragging { releaseDrag(into: &out) }
        }
        if inTouch, time - lastFrameTime > Self.staleTouch {
            previous = [:]
            end(at: lastFrameTime, into: &out)
        }
        if let deadline = regripDeadline, time >= deadline, !inTouch {
            regripDeadline = nil
            releaseDrag(into: &out)
        }
        stepMomentum(at: time, into: &out)
        return out
    }

    /// Lets go of everything: the button, a scroll, momentum. For when the pad goes away or the driver stops.
    public mutating func reset() -> [PointerIntent] {
        var out: [PointerIntent] = []
        if dragging { releaseDrag(into: &out) }
        if scrolling { out.append(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)) }
        stopMomentum(into: &out)
        self = Self(configuration: configuration)
        return out
    }

    // MARK: Touches

    private mutating func begin(at time: Double, first: TrackpadContact, into out: inout [PointerIntent]) {
        stopMomentum(into: &out)
        inTouch = true
        touchStart = time
        firstContact = first
        previous = [:]
        travel = 0
        twoFingerRun = 0
        longestTwoFingerRun = 0
        isTwoFingerTouch = false
        pointerLive = false
        speed = 0
        held = []
        scrolling = false
        scrollAxis = .free
        scrollTravel = (0, 0)
        scrollVelocity = (0, 0)
        dragContinued = false
        if regripDeadline != nil {
            regripDeadline = nil
            dragContinued = true
        }
        let drag = configuration.settings.dragging
        var near = false
        if let tap = lastTapContact {
            near = hypot(tap.x - first.x, tap.y - first.y) / TrackpadGeometry.unitsPerMillimeter <= drag.radius
        }
        dragArmed = drag.tapThenDrag && !dragging && near && lastTapClean && time - lastTapEnd < drag.window / 1000
    }

    private mutating func end(at time: Double, into out: inout [PointerIntent]) {
        inTouch = false
        held = []
        let duration = time - touchStart
        let wasScrolling = scrolling
        if scrolling {
            scrolling = false
            out.append(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none))
            if !dragging { startMomentum(at: time) }
        }
        if dragging {
            let tap = dragContinued && duration < configuration.settings.tapping.longestTap / 1000 && travel < tapTravel(fingers: 1)
            if let regrip = configuration.settings.dragging.regrip, !tap {
                regripDeadline = time + regrip
            } else {
                releaseDrag(into: &out)
            }
            return
        }
        guard !wasScrolling else { return }
        classifyTap(duration: duration, at: time, into: &out)
    }

    private mutating func classifyTap(duration: Double, at time: Double, into out: inout [PointerIntent]) {
        let tapping = configuration.settings.tapping
        let fingers = longestTwoFingerRun >= Self.rightClickTime ? 2 : 1
        let longest = (tapping.longestTap + (fingers == 2 ? 40 : 0)) / 1000
        guard tapping.tapToClick, duration < longest, travel < tapTravel(fingers: fingers) else { return }
        if fingers == 2 {
            guard tapping.twoFingerRightClick else { return }
            out.append(.button(.right, isDown: true, clickCount: 1))
            out.append(.button(.right, isDown: false, clickCount: 1))
            lastTapClicks = 0
            lastTapClean = false
        } else {
            var clicks = 1
            if time - lastTapEnd < configuration.doubleClickInterval, movedSinceTap < Self.doubleClickSlop {
                clicks = min(lastTapClicks + 1, 3)
            }
            out.append(.button(.left, isDown: true, clickCount: clicks))
            out.append(.button(.left, isDown: false, clickCount: clicks))
            lastTapClicks = clicks
            // Only a first, still tap arms a drag; a sloppy tap clicks but can't start one.
            lastTapClean = clicks == 1 && travel <= Self.settleTravel
        }
        lastTapEnd = time
        lastTapContact = firstContact
        movedSinceTap = 0
    }

    private func tapTravel(fingers: Int) -> Double {
        configuration.settings.tapping.tapMovement * TrackpadGeometry.unitsPerMillimeter * Double(fingers)
    }

    private mutating func releaseDrag(into out: inout [PointerIntent]) {
        dragging = false
        lastTapClicks = 0
        lastTapClean = false
        out.append(.button(.left, isDown: false, clickCount: 1))
    }

    // MARK: Pointer

    private mutating func movePointer(mx: Double, my: Double, dt: Double, at time: Double, into out: inout [PointerIntent]) {
        let pointer = configuration.settings.pointer
        var fx = mx
        var fy = my
        let reportSpeed = hypot(mx, my) / TrackpadGeometry.unitsPerMillimeter / dt
        let limit = max(Self.spikeFactor * speed, Self.spikeFloor)
        if reportSpeed > limit {
            fx *= limit / reportSpeed
            fy *= limit / reportSpeed
        }
        speed += (1 - exp(-dt / Self.speedSmoothing)) * (min(reportSpeed, limit) - speed)
        let perMillimeter = pointsPerMillimeter(atFingerSpeed: speed)
        let dx = fx / TrackpadGeometry.unitsPerMillimeter * perMillimeter
        let dy = fy / TrackpadGeometry.unitsPerMillimeter * perMillimeter

        if !pointerLive {
            // Settling: what moves now is the finger landing, and a tap's wobble. Dropped, not replayed.
            guard travel > Self.settleTravel || time - touchStart > Self.settleTime else { return }
            pointerLive = true
            return
        }
        if dragArmed, !dragging, travel > Self.dragStartTravel {
            dragging = true
            out.append(.button(.left, isDown: true, clickCount: 1))
        }
        guard pointer.filtersLiftOff else {
            emitMove(dx, dy, into: &out)
            return
        }
        held.append((dx, dy))
        if held.count > Self.liftOffReports {
            let move = held.removeFirst()
            emitMove(move.dx, move.dy, into: &out)
        }
    }

    private mutating func emitMove(_ dx: Double, _ dy: Double, into out: inout [PointerIntent]) {
        guard dx != 0 || dy != 0 else { return }
        movedSinceTap += hypot(dx, dy)
        out.append(.move(dx: dx, dy: dy, dragging: dragging))
    }

    /// Points per millimeter of finger travel at a finger speed in mm/s: Apple's curve, with the extra gain above the
    /// fast-move threshold scaled by `fastMoves`.
    public func pointsPerMillimeter(atFingerSpeed fingerSpeed: Double) -> Double {
        let pointer = configuration.settings.pointer
        let inchesPerMillimeter = pointer.padScale / 25.4
        func apple(_ millimetersPerSecond: Double) -> Double {
            96 * inchesPerMillimeter * configuration.curve.multiplier(inchesPerSecond: millimetersPerSecond * inchesPerMillimeter)
        }
        guard fingerSpeed > pointer.fastMoveThreshold else { return apple(fingerSpeed) }
        let atThreshold = apple(pointer.fastMoveThreshold)
        return atThreshold + (apple(fingerSpeed) - atThreshold) * pointer.fastMoves
    }

    // MARK: Scrolling

    private mutating func scroll(mx: Double, my: Double, dt: Double, into out: inout [PointerIntent]) {
        let scrolling = configuration.settings.scrolling
        let millimeters = hypot(mx, my) / TrackpadGeometry.unitsPerMillimeter
        let gain = scrollPointsPerMillimeter(atFingerSpeed: millimeters / dt)
        let natural = configuration.naturalScrolling ? 1.0 : -1.0
        var sx = natural * (scrolling.invertsHorizontal ? -1 : 1) * mx / TrackpadGeometry.unitsPerMillimeter * gain
        var sy = natural * (scrolling.invertsVertical ? -1 : 1) * my / TrackpadGeometry.unitsPerMillimeter * gain
        scrollTravel.x += abs(mx)
        scrollTravel.y += abs(my)
        if !self.scrolling {
            guard scrollTravel.x + scrollTravel.y > Self.scrollStartTravel else { return }
            self.scrolling = true
            out.append(.scroll(dx: 0, dy: 0, phase: .began, momentum: .none))
        }
        if scrollAxis == .free, scrollTravel.x + scrollTravel.y > Self.axisLockTravel {
            if scrollTravel.y > 2 * scrollTravel.x {
                scrollAxis = .vertical
            } else if scrollTravel.x > 2 * scrollTravel.y {
                scrollAxis = .horizontal
            }
        }
        if scrollAxis == .vertical { sx = 0 }
        if scrollAxis == .horizontal { sy = 0 }
        scrollVelocity.x += Self.velocitySmoothing * (sx / dt - scrollVelocity.x)
        scrollVelocity.y += Self.velocitySmoothing * (sy / dt - scrollVelocity.y)
        out.append(.scroll(dx: sx, dy: sy, phase: .changed, momentum: .none))
    }

    /// Points of scroll per millimeter of finger travel: 9 when slow, rising to 28 by 250 mm/s, times the speed setting.
    public func scrollPointsPerMillimeter(atFingerSpeed fingerSpeed: Double) -> Double {
        let t = min(max((fingerSpeed - 20) / (250 - 20), 0), 1)
        return configuration.settings.scrolling.speed * (9 + (28 - 9) * t * t)
    }

    private mutating func startMomentum(at time: Double) {
        guard configuration.settings.scrolling.hasMomentum else { return }
        var velocity = scrollVelocity
        let speed = hypot(velocity.x, velocity.y)
        guard speed > Self.momentumStartSpeed else { return }
        if speed > Self.momentumCap {
            velocity.x *= Self.momentumCap / speed
            velocity.y *= Self.momentumCap / speed
        }
        momentum = (velocity, time, false)
    }

    private mutating func stepMomentum(at time: Double, into out: inout [PointerIntent]) {
        guard var glide = momentum else { return }
        let dt = min(max(time - glide.lastTick, 0), Self.longestGap)
        guard dt > 0 else { return }
        let halfLife = configuration.settings.scrolling.momentumHalfLife / 1000
        let keep = exp(-dt * log(2) / halfLife)
        glide.velocity.x *= keep
        glide.velocity.y *= keep
        glide.lastTick = time
        if hypot(glide.velocity.x, glide.velocity.y) < Self.momentumStopSpeed {
            momentum = nil
            if glide.started { out.append(.scroll(dx: 0, dy: 0, phase: .none, momentum: .ended)) }
            return
        }
        out.append(
            .scroll(
                dx: glide.velocity.x * dt, dy: glide.velocity.y * dt, phase: .none, momentum: glide.started ? .continued : .began))
        glide.started = true
        momentum = glide
    }

    private mutating func stopMomentum(into out: inout [PointerIntent]) {
        guard let glide = momentum else { return }
        momentum = nil
        if glide.started { out.append(.scroll(dx: 0, dy: 0, phase: .none, momentum: .ended)) }
    }

    // MARK: Helpers

    private mutating func interval(to frame: TrackpadFrame) -> Double {
        defer { lastScan = frame.scanTime }
        guard let last = lastScan, inTouch else { return Self.reportInterval }
        let dt = Double((frame.scanTime - last + 65536) % 65536) / 10000
        return dt >= Self.shortestGap && dt <= Self.longestGap ? dt : Self.reportInterval
    }

    /// Drops a second contact closer than about 1.2 mm to the first: one finger the sensor split in two.
    static func mergingSplitContacts(_ contacts: [TrackpadContact]) -> [TrackpadContact] {
        guard contacts.count == 2, hypot(contacts[0].x - contacts[1].x, contacts[0].y - contacts[1].y) < splitContactDistance else {
            return contacts
        }
        return [contacts[0]]
    }
}
