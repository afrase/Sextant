import Foundation

/// Settings › Navigator: how Sextant drives the Navigator trackpad (ADR 0068). Every value is in a unit people know
/// (milliseconds, millimeters, a share); `nil` where macOS has its own setting means "follow System Settings".
///
/// Stored as JSON. A missing key, or one of the wrong type, decodes as its default, so a newer Sextant reads an older
/// file and the reverse, and one damaged value costs only itself.
public struct TrackpadSettings: Hashable, Sendable, Codable {
    /// "Use Sextant for the Navigator trackpad". Off until the user turns it on: that is the consent to set the pad's
    /// input mode whenever it connects or the Mac wakes (ADR 0068).
    public var isEnabled: Bool
    /// How far the pad is turned clockwise from upright, in degrees (-180...180). The Navigator mounts at whatever
    /// angle suits the hand; pointer moves and scrolls are turned back by this much, so "up" on screen is up for the
    /// user.
    public var rotation: Double
    public static let rotationRange = -180.0...180.0
    public var pointer: Pointer
    public var scrolling: Scrolling
    public var tapping: Tapping
    public var dragging: Dragging

    public init(
        isEnabled: Bool = false, rotation: Double = 0, pointer: Pointer = .init(), scrolling: Scrolling = .init(),
        tapping: Tapping = .init(),
        dragging: Dragging = .init()
    ) {
        self.isEnabled = isEnabled
        self.rotation = rotation
        self.pointer = pointer
        self.scrolling = scrolling
        self.tapping = tapping
        self.dragging = dragging
    }

    public struct Pointer: Hashable, Sendable, Codable {
        /// A tracking speed on System Settings' scale (0...3), picking Apple's trackpad curve; nil follows the Mac's.
        /// The default, 1.0, is one step above the Mac's default (0.6875): the Navigator is a quarter of a MacBook
        /// trackpad's width, and 1.0 is the curve closest to the one the user tuned on the hardware (research 06).
        public var trackingSpeed: Double?
        /// The share of Apple's extra acceleration kept above `fastMoveThreshold`: 1 is Apple's curve, 0 stops
        /// accelerating there. Long throws overshoot less with less.
        public var fastMoves: Double
        /// Finger speed in mm/s above which `fastMoves` applies.
        public var fastMoveThreshold: Double
        /// Treat the pad as this many times its real size (advanced): more distance per stroke, same curve shape.
        public var padScale: Double
        /// Drops the last two reports before a finger lifts, which are the fingertip rolling off (advanced; about 13 ms
        /// of latency).
        public var filtersLiftOff: Bool

        public static let trackingSpeedRange = 0.0...3.0
        public static let fastMovesRange = 0.0...1.0
        public static let fastMoveThresholdRange = 40.0...300.0
        public static let padScaleRange = 0.5...4.0

        public init(
            trackingSpeed: Double? = 1, fastMoves: Double = 1, fastMoveThreshold: Double = 100, padScale: Double = 1,
            filtersLiftOff: Bool = true
        ) {
            self.trackingSpeed = trackingSpeed
            self.fastMoves = fastMoves
            self.fastMoveThreshold = fastMoveThreshold
            self.padScale = padScale
            self.filtersLiftOff = filtersLiftOff
        }
    }

    public struct Scrolling: Hashable, Sendable, Codable {
        /// A multiplier on the scroll curve (9 to 28 points per mm of finger travel).
        public var speed: Double
        /// Content follows the fingers when the system's natural scrolling is on; these flip one axis from that.
        public var invertsHorizontal: Bool
        public var invertsVertical: Bool
        public var hasMomentum: Bool
        /// How long momentum takes to lose half its speed, in milliseconds.
        public var momentumHalfLife: Double

        public static let speedRange = 0.25...4.0
        public static let momentumHalfLifeRange = 50.0...1000.0

        public init(
            speed: Double = 1, invertsHorizontal: Bool = false, invertsVertical: Bool = false, hasMomentum: Bool = true,
            momentumHalfLife: Double = 230
        ) {
            self.speed = speed
            self.invertsHorizontal = invertsHorizontal
            self.invertsVertical = invertsVertical
            self.hasMomentum = hasMomentum
            self.momentumHalfLife = momentumHalfLife
        }
    }

    public struct Tapping: Hashable, Sendable, Codable {
        public var tapToClick: Bool
        /// Two fingers tapping together right-click.
        public var twoFingerRightClick: Bool
        /// The longest touch that counts as a one-finger tap, in milliseconds (two fingers get 40 ms more).
        public var longestTap: Double
        /// The most a finger may move during a tap, in millimeters (two fingers get twice as much).
        public var tapMovement: Double
        /// The longest gap between clicks of a double-click, in seconds; nil follows the Mac's double-click speed.
        public var doubleClickInterval: Double?

        public static let longestTapRange = 80.0...400.0
        public static let tapMovementRange = 0.3...4.0
        public static let doubleClickIntervalRange = 0.15...5.0

        public init(
            tapToClick: Bool = true, twoFingerRightClick: Bool = true, longestTap: Double = 180, tapMovement: Double = 1.2,
            doubleClickInterval: Double? = nil
        ) {
            self.tapToClick = tapToClick
            self.twoFingerRightClick = twoFingerRightClick
            self.longestTap = longestTap
            self.tapMovement = tapMovement
            self.doubleClickInterval = doubleClickInterval
        }
    }

    public struct Dragging: Hashable, Sendable, Codable {
        /// Tap, then touch again where you tapped and move: the button stays down until the finger lifts.
        public var tapThenDrag: Bool
        /// How soon after the tap the second touch must land, in milliseconds.
        public var window: Double
        /// How close to the tap the second touch must land on the pad, in millimeters. A finger lifted to reposition
        /// lands elsewhere, so it never drags.
        public var radius: Double
        /// After lifting mid-drag, how long the button stays down for a re-touch to carry on, in seconds; nil is off.
        public var regrip: Double?

        public static let windowRange = 100.0...500.0
        public static let radiusRange = 1.0...15.0
        public static let regripRange = 0.1...2.0
        public static let defaultRegrip = 0.6

        public init(tapThenDrag: Bool = true, window: Double = 200, radius: Double = 4, regrip: Double? = nil) {
            self.tapThenDrag = tapThenDrag
            self.window = window
            self.radius = radius
            self.regrip = regrip
        }
    }

    /// Every value held to its range, so a hand-edited or damaged file can't make the engine misbehave.
    public var clamped: Self {
        var copy = self
        copy.rotation = rotation.clamped(to: Self.rotationRange)
        copy.pointer.trackingSpeed = pointer.trackingSpeed.map { $0.clamped(to: Pointer.trackingSpeedRange) }
        copy.pointer.fastMoves = pointer.fastMoves.clamped(to: Pointer.fastMovesRange)
        copy.pointer.fastMoveThreshold = pointer.fastMoveThreshold.clamped(to: Pointer.fastMoveThresholdRange)
        copy.pointer.padScale = pointer.padScale.clamped(to: Pointer.padScaleRange)
        copy.scrolling.speed = scrolling.speed.clamped(to: Scrolling.speedRange)
        copy.scrolling.momentumHalfLife = scrolling.momentumHalfLife.clamped(to: Scrolling.momentumHalfLifeRange)
        copy.tapping.longestTap = tapping.longestTap.clamped(to: Tapping.longestTapRange)
        copy.tapping.tapMovement = tapping.tapMovement.clamped(to: Tapping.tapMovementRange)
        copy.tapping.doubleClickInterval = tapping.doubleClickInterval.map { $0.clamped(to: Tapping.doubleClickIntervalRange) }
        copy.dragging.window = dragging.window.clamped(to: Dragging.windowRange)
        copy.dragging.radius = dragging.radius.clamped(to: Dragging.radiusRange)
        copy.dragging.regrip = dragging.regrip.map { $0.clamped(to: Dragging.regripRange) }
        return copy
    }
}

// MARK: - Decoding with defaults

extension TrackpadSettings {
    private enum CodingKeys: String, CodingKey { case isEnabled, rotation, pointer, scrolling, tapping, dragging }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TrackpadSettings()
        isEnabled = c.lenient(Bool.self, .isEnabled) ?? d.isEnabled
        rotation = c.lenient(Double.self, .rotation) ?? d.rotation
        pointer = c.lenient(Pointer.self, .pointer) ?? d.pointer
        scrolling = c.lenient(Scrolling.self, .scrolling) ?? d.scrolling
        tapping = c.lenient(Tapping.self, .tapping) ?? d.tapping
        dragging = c.lenient(Dragging.self, .dragging) ?? d.dragging
    }
}

extension TrackpadSettings.Pointer {
    private enum CodingKeys: String, CodingKey { case trackingSpeed, fastMoves, fastMoveThreshold, padScale, filtersLiftOff }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        // An explicit null is "follow the Mac"; a missing key is the default.
        trackingSpeed =
            c.contains(.trackingSpeed) && (try? c.decodeNil(forKey: .trackingSpeed)) == true
            ? nil : c.lenient(Double.self, .trackingSpeed) ?? d.trackingSpeed
        fastMoves = c.lenient(Double.self, .fastMoves) ?? d.fastMoves
        fastMoveThreshold = c.lenient(Double.self, .fastMoveThreshold) ?? d.fastMoveThreshold
        padScale = c.lenient(Double.self, .padScale) ?? d.padScale
        filtersLiftOff = c.lenient(Bool.self, .filtersLiftOff) ?? d.filtersLiftOff
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trackingSpeed, forKey: .trackingSpeed)  // null when following the Mac, never left out
        try c.encode(fastMoves, forKey: .fastMoves)
        try c.encode(fastMoveThreshold, forKey: .fastMoveThreshold)
        try c.encode(padScale, forKey: .padScale)
        try c.encode(filtersLiftOff, forKey: .filtersLiftOff)
    }
}

extension TrackpadSettings.Scrolling {
    private enum CodingKeys: String, CodingKey { case speed, invertsHorizontal, invertsVertical, hasMomentum, momentumHalfLife }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        speed = c.lenient(Double.self, .speed) ?? d.speed
        invertsHorizontal = c.lenient(Bool.self, .invertsHorizontal) ?? d.invertsHorizontal
        invertsVertical = c.lenient(Bool.self, .invertsVertical) ?? d.invertsVertical
        hasMomentum = c.lenient(Bool.self, .hasMomentum) ?? d.hasMomentum
        momentumHalfLife = c.lenient(Double.self, .momentumHalfLife) ?? d.momentumHalfLife
    }
}

extension TrackpadSettings.Tapping {
    private enum CodingKeys: String, CodingKey { case tapToClick, twoFingerRightClick, longestTap, tapMovement, doubleClickInterval }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        tapToClick = c.lenient(Bool.self, .tapToClick) ?? d.tapToClick
        twoFingerRightClick = c.lenient(Bool.self, .twoFingerRightClick) ?? d.twoFingerRightClick
        longestTap = c.lenient(Double.self, .longestTap) ?? d.longestTap
        tapMovement = c.lenient(Double.self, .tapMovement) ?? d.tapMovement
        doubleClickInterval = c.lenient(Double.self, .doubleClickInterval)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tapToClick, forKey: .tapToClick)
        try c.encode(twoFingerRightClick, forKey: .twoFingerRightClick)
        try c.encode(longestTap, forKey: .longestTap)
        try c.encode(tapMovement, forKey: .tapMovement)
        try c.encode(doubleClickInterval, forKey: .doubleClickInterval)  // null when following the Mac
    }
}

extension TrackpadSettings.Dragging {
    private enum CodingKeys: String, CodingKey { case tapThenDrag, window, radius, regrip }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        tapThenDrag = c.lenient(Bool.self, .tapThenDrag) ?? d.tapThenDrag
        window = c.lenient(Double.self, .window) ?? d.window
        radius = c.lenient(Double.self, .radius) ?? d.radius
        regrip = c.lenient(Double.self, .regrip)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tapThenDrag, forKey: .tapThenDrag)
        try c.encode(window, forKey: .window)
        try c.encode(radius, forKey: .radius)
        try c.encode(regrip, forKey: .regrip)  // null when off
    }
}

extension KeyedDecodingContainer {
    /// The value at `key`, or nil when it's missing, null or of the wrong type.
    fileprivate func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? { (try? decodeIfPresent(type, forKey: key)).flatMap { $0 } }
}

extension Double {
    /// Held to `range`; NaN, which compares false with everything, becomes the lower bound.
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        isNaN ? range.lowerBound : Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
