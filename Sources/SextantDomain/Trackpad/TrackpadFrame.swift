import Foundation

/// One finger on the Navigator trackpad, in the pad's logical units (research 06).
public struct TrackpadContact: Hashable, Sendable {
    /// The firmware's contact id: stable while the finger stays down, and kept by a finger whose neighbour lifts.
    public var id: Int
    public var x: Double
    public var y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

/// One Precision Touchpad report: the fingers touching (tip and confidence both set) and when.
///
/// The pad reports about every 6.5 ms while touched and nothing while untouched; a finger lifting is one report without it,
/// so a frame with no contacts ends a touch.
public struct TrackpadFrame: Hashable, Sendable {
    public var contacts: [TrackpadContact]
    /// The sensor's clock in 100 µs units, wrapping at 65536: the time between two frames of one touch.
    public var scanTime: Int
    /// When the Mac received it, in seconds on a monotonic clock: the time between touches.
    public var timestamp: Double

    public init(contacts: [TrackpadContact], scanTime: Int, timestamp: Double) {
        self.contacts = contacts
        self.scanTime = scanTime
        self.timestamp = timestamp
    }
}

/// The Navigator trackpad's size: 0...2048 logical units across a pad about 40 mm wide (zsa/qmk_modules
/// `navigator_trackpad`; the firmware reports a larger physical size so Windows moves the pointer faster).
enum TrackpadGeometry {
    static let logicalMaximum = 2048.0
    static let widthInMillimeters = 40.0
    static let unitsPerMillimeter = logicalMaximum / widthInMillimeters
}
