import Foundation
import SextantDomain

/// What the updater tells ``SoftwareUpdates`` as it works (ADR 0070).
public enum SoftwareUpdateEvent: Equatable, Sendable {
    /// Whether a check may start now; false while one runs or an update is being installed.
    case canCheck(Bool)
    /// A scheduled check found this update and the updater didn't show it (Sextant hadn't just launched): Sextant reminds
    /// the user gently (the menu bar panel, the Sextant menu) instead of opening a window over their work.
    case found(AppVersion)
    /// The user saw the update (the updater's window is up), so the reminder can go.
    case seen
    /// The update session ended: installed, skipped, postponed or failed.
    case finished
    /// A check got an answer (found an update or not) at this time.
    case checked(Date)
    /// The choices changed in the updater's own window (or with each other: no checks means no automatic installs).
    case checksAutomatically(Bool)
    case installsAutomatically(Bool)
}

/// The in-app updater (ADR 0070): finds a newer release, shows its notes, downloads and verifies it, installs it and
/// relaunches. Its own windows do the talking; the use case only starts it, mirrors its state and forwards choices.
/// Main actor only: the updater drives AppKit windows.
@MainActor
public protocol SoftwareUpdater: AnyObject {
    /// Whether this build can update itself: a bundled release build with a feed and a signing key. `swift run` and a
    /// bundle without them can't, and then nothing below does anything.
    var isSupported: Bool { get }
    var checksAutomatically: Bool { get set }
    /// Downloads an update by itself and installs it when Sextant quits.
    var installsAutomatically: Bool { get set }
    var lastChecked: Date? { get }
    /// The running build's version, as the user reads it.
    var version: AppVersion? { get }
    /// Starts checking on its schedule and reporting through `report`. Called once.
    func start(report: @escaping @MainActor (SoftwareUpdateEvent) -> Void)
    /// Checks now and shows the answer in the updater's window, or brings back an update already found.
    func checkForUpdates()
}
