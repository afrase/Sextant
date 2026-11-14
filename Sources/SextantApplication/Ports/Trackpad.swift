import Foundation
import SextantDomain

/// A Navigator trackpad's HID interface, by its registry id.
public struct TrackpadID: Hashable, Sendable {
    public var rawValue: UInt64
    public init(_ rawValue: UInt64) { self.rawValue = rawValue }
}

/// The trackpad's input mode, feature report 4 (research 06).
public enum TrackpadInputMode: Hashable, Sendable {
    /// The firmware's fallback mouse: relative moves and its own tap-to-click. What every Mac sees without Sextant.
    case mouse
    /// Precision Touchpad: two-finger contacts, and nothing moves the pointer unless Sextant does.
    case touchpad
}

/// What a trackpad session reports.
public enum TrackpadEvent: Hashable, Sendable {
    case attached(TrackpadID)
    case frame(TrackpadFrame, from: TrackpadID)
    case detached(TrackpadID)
    /// The session couldn't open the interface (Input Monitoring withdrawn, or another app seized it); it ends here.
    case failed(TrackpadError)
}

public enum TrackpadError: Error, Hashable, Sendable, LocalizedError {
    /// macOS refuses to let Sextant read the trackpad: Input Monitoring is off for Sextant.
    case inputMonitoringDenied
    case notAttached
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .inputMonitoringDenied:
            String(
                localized: "Sextant can’t read the trackpad. Turn on Sextant in System Settings › Privacy & Security › Input Monitoring.")
        case .notAttached: String(localized: "The Navigator trackpad isn’t connected.")
        case let .io(detail): String(localized: "Sextant couldn’t talk to the Navigator trackpad. \(detail)")
        }
    }
}

/// The Navigator trackpad's digitizer interface (ADR 0068). Reading it needs Input Monitoring; a session opens the
/// interface, so nothing asks for that permission until the user turns the driver on.
public protocol TrackpadLink: Sendable {
    /// Whether Input Monitoring is granted; never prompts.
    func hasInputAccess() async -> Bool
    /// Asks for Input Monitoring (the system prompt, the first time); true when granted.
    func requestInputAccess() async -> Bool
    /// Each trackpad attached now, then frames from them and attach and detach events. Ends when the consuming task is
    /// cancelled, closing the interfaces; closing writes mouse mode back to every pad the session switched, so a pad is
    /// never left in touchpad mode with nothing reading it.
    func session() -> AsyncStream<TrackpadEvent>
    /// Writes the input mode (feature report 4) to one trackpad of the open session: the only thing the link ever
    /// writes. Throws `.notAttached` once the session is closed.
    func setInputMode(_ mode: TrackpadInputMode, on pad: TrackpadID) async throws(TrackpadError)
}

/// Posts pointer events to the Mac. Needs Accessibility.
public protocol PointerOutput: Sendable {
    /// Whether Sextant may post events; never prompts.
    func hasAccess() async -> Bool
    /// Asks for Accessibility (the system prompt, the first time); true when granted.
    func requestAccess() async -> Bool
    /// Posts each intent in order. A move posts as a drag while the engine drags or a mouse button is held down
    /// elsewhere (a keyboard's click key).
    func post(_ intents: [PointerIntent]) async
}

/// The Mac's own pointer settings, read fresh each time.
public struct SystemPointerPreferences: Hashable, Sendable {
    /// The Mac's trackpad curve set (the standard one when it has no trackpad).
    public var curves: PointerCurveSet
    /// System Settings › Trackpad › Tracking speed (0...3).
    public var trackingSpeed: Double
    /// System Settings › Trackpad › Natural scrolling.
    public var naturalScrolling: Bool
    /// System Settings › Accessibility › Pointer Control › Double-click speed, in seconds.
    public var doubleClickInterval: Double

    public init(curves: PointerCurveSet, trackingSpeed: Double, naturalScrolling: Bool, doubleClickInterval: Double) {
        self.curves = curves
        self.trackingSpeed = trackingSpeed
        self.naturalScrolling = naturalScrolling
        self.doubleClickInterval = doubleClickInterval
    }

    /// macOS's defaults, with the standard curves.
    public static let standard = Self(
        curves: .standardTrackpad, trackingSpeed: 0.6875, naturalScrolling: true, doubleClickInterval: 0.5)
}

public protocol SystemPointerSettings: Sendable {
    func current() async -> SystemPointerPreferences
}
