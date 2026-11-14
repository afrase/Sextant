import Foundation
import Observation
import SextantDomain
import os

/// Keeps Sextant up to date from inside the app (ADR 0070). The updater checks once a day while checking automatically
/// is on (the default) and whenever the user asks, and its own windows show the notes, download, install and relaunch.
/// This use case mirrors its state for the menus, Settings and the menu bar panel. App-wide; the composition root
/// builds and starts it.
@MainActor
@Observable
public final class SoftwareUpdates {
    /// Whether this build can update itself; a build that can't shows why instead of Check for Updates….
    public let isSupported: Bool
    /// The running build's version; nil when it has none (`swift run`).
    public let current: AppVersion?
    /// Whether Check for Updates… may start a check now.
    public private(set) var canCheck = false
    /// An update a scheduled check found and didn't show, until the user sees it.
    public private(set) var notice: AppVersion?
    public private(set) var lastChecked: Date?

    public var checksAutomatically: Bool {
        didSet {
            guard checksAutomatically != oldValue, !mirroring else { return }
            updater.checksAutomatically = checksAutomatically
            // The updater installs automatically only while it checks automatically.
            let installs = updater.installsAutomatically
            mirror { installsAutomatically = installs }
        }
    }

    public var installsAutomatically: Bool {
        didSet {
            guard installsAutomatically != oldValue, !mirroring else { return }
            updater.installsAutomatically = installsAutomatically
        }
    }

    @ObservationIgnored private let updater: any SoftwareUpdater
    @ObservationIgnored private var started = false
    /// Set while a change the updater reported is copied in, so it isn't written back.
    @ObservationIgnored private var mirroring = false
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    public init(updater: any SoftwareUpdater) {
        self.updater = updater
        isSupported = updater.isSupported
        current = updater.version
        checksAutomatically = updater.checksAutomatically
        installsAutomatically = updater.installsAutomatically
        lastChecked = updater.lastChecked
    }

    /// Starts the updater's schedule. A build that can't update itself never starts it.
    public func start() {
        guard isSupported, !started else { return }
        started = true
        updater.start { [weak self] in self?.handle($0) }
    }

    /// Check for Updates…, Check Now, and the reminder's Details…: the updater's window answers.
    public func check() {
        guard isSupported, canCheck else { return }
        updater.checkForUpdates()
    }

    private func handle(_ event: SoftwareUpdateEvent) {
        switch event {
        case let .canCheck(can): canCheck = can
        case let .found(version):
            Self.log.info("Update \(version, privacy: .public) found in the background")
            notice = version
        case .seen, .finished: notice = nil
        case let .checked(date): lastChecked = date
        case let .checksAutomatically(on): mirror { checksAutomatically = on }
        case let .installsAutomatically(on): mirror { installsAutomatically = on }
        }
    }

    private func mirror(_ change: () -> Void) {
        mirroring = true
        change()
        mirroring = false
    }
}
