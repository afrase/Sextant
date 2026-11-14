import Foundation
import SextantApplication
import SextantDomain
import Sparkle
import os

/// The in-app updater, on Sparkle 2 (ADR 0070). Sparkle reads the signed appcast the release workflow publishes on the
/// repo's `appcast` branch, verifies the zip's EdDSA signature against the key in Info.plist, installs it and relaunches.
/// Its standard windows do the talking; a scheduled check that finds an update reports it for a gentle reminder
/// instead of opening a window over the user's work, unless Sextant has just launched.
@MainActor
public final class SparkleUpdater: SoftwareUpdater {
    public let isSupported: Bool
    public let version: AppVersion?
    private let bridge = SparkleBridge()
    /// Nil when the build can't update itself. It keeps the user driver.
    private let updater: SPUUpdater?
    /// Whether a check may start, and the two choices, which Sparkle's update window can also change.
    private var observations: [NSKeyValueObservation] = []
    private static let log = Logger(subsystem: "com.sextant.app", category: "updates")

    /// - Parameters:
    ///   - bundle: the app; Sparkle reads its Info.plist (feed, key, schedule) and replaces it.
    ///   - defaults: where the update choices live (Sparkle's `SU…` keys), tidied up from ADR 0063's keys once.
    public init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        UpdateDefaults.migrate(defaults)
        version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
        isSupported = SparkleConfiguration.canUpdate(info: bundle.infoDictionary ?? [:], bundlePath: bundle.bundlePath)
        updater =
            isSupported
            ? SPUUpdater(
                hostBundle: bundle, applicationBundle: bundle, userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: bridge),
                delegate: bridge)
            : nil
    }

    public var checksAutomatically: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    public var installsAutomatically: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set { updater?.automaticallyDownloadsUpdates = newValue }
    }

    public var lastChecked: Date? { updater?.lastUpdateCheckDate }

    public func start(report: @escaping @MainActor (SoftwareUpdateEvent) -> Void) {
        guard let updater, observations.isEmpty else { return }
        bridge.report = report
        bridge.updater = updater
        // KVO-compliant, and changed on the main thread (Sparkle's updater is main-thread only). Its alert's "Automatically
        // download and install updates in the future" sets the second choice; turning checks off also turns it off.
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
                MainActor.assumeIsolated { report(.canCheck(updater.canCheckForUpdates)) }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { updater, _ in
                MainActor.assumeIsolated { report(.checksAutomatically(updater.automaticallyChecksForUpdates)) }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { updater, _ in
                MainActor.assumeIsolated { report(.installsAutomatically(updater.automaticallyDownloadsUpdates)) }
            },
        ]
        do {
            try updater.start()
        } catch {
            // A broken feed URL or key in Info.plist: Check for Updates… stays off, rather than failing at each check.
            Self.log.error("Sparkle didn't start: \(error.localizedDescription, privacy: .public)")
            observations = []
            report(.canCheck(false))
        }
    }

    public func checkForUpdates() {
        updater?.checkForUpdates()
    }
}

/// Sparkle's delegates, in an object of their own so the updater can be built with them in its initializer.
@MainActor
final class SparkleBridge: NSObject, SPUUpdaterDelegate {
    var report: (@MainActor (SoftwareUpdateEvent) -> Void)?
    weak var updater: SPUUpdater?

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let date = updater.lastUpdateCheckDate { report?(.checked(date)) }
    }
}

// Sparkle calls the user driver's delegate on the main thread, though the protocol doesn't say so.
extension SparkleBridge: @preconcurrency SPUStandardUserDriverDelegate {
    /// Sextant often runs from the menu bar for days: a scheduled update waits in the menu bar panel and the Sextant menu
    /// rather than opening a window over whatever the user is doing.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself only when it would be in immediate focus: Sextant has just launched, or
    /// the Mac has been idle a while. Otherwise Sextant reminds the user, whether or not it is in front.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState)
    {
        // Sparkle dates the check when it starts, but finishes the cycle only once the user acts on the update.
        if let date = updater?.lastUpdateCheckDate { report?(.checked(date)) }
        guard !handleShowingUpdate, !state.userInitiated, let version = AppVersion(update.displayVersionString) else { return }
        report?(.found(version))
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        report?(.seen)
    }

    func standardUserDriverWillFinishUpdateSession() {
        report?(.finished)
    }
}

/// Whether a bundle has what Sparkle needs to update it.
enum SparkleConfiguration {
    /// A real `.app` (not `swift run`), with a version, an `https` feed and an EdDSA public key in its Info.plist.
    static func canUpdate(info: [String: Any], bundlePath: String) -> Bool {
        guard bundlePath.hasSuffix(".app"),
            let version = info["CFBundleShortVersionString"] as? String, AppVersion(version) != nil,
            let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), feed.scheme == "https",
            let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32
        else { return false }
        return true
    }
}

/// The update choices in UserDefaults.
enum UpdateDefaults {
    /// Sparkle's own key for checking automatically; it overrides Info.plist's default.
    static let checksAutomatically = "SUEnableAutomaticChecks"
    /// ADR 0063's keys, from before Sparkle.
    static let legacyChecksAutomatically = "checksForUpdates"
    static let legacy = ["checksForUpdates", "updatesLastChecked", "updatesDismissedVersion", "updatesFoundRelease"]

    /// Carries a user's "don't check automatically" over to Sparkle, then removes the old keys.
    static func migrate(_ defaults: UserDefaults) {
        if defaults.object(forKey: legacyChecksAutomatically) as? Bool == false {
            defaults.set(false, forKey: checksAutomatically)
        }
        for key in legacy { defaults.removeObject(forKey: key) }
    }
}
