import Foundation
import Observation
import SextantDomain
import os

/// Tells the user when a newer Sextant is out (ADR 0063): it asks the release feed once a day while checking
/// automatically is on (the default), and whenever the user asks. It only tells: nothing is downloaded or installed.
/// App-wide; the composition root builds and starts it.
@MainActor
@Observable
public final class UpdateChecker {
    /// What the last check said, for the Software Update window and Settings.
    public enum Status: Equatable, Sendable {
        /// Nothing checked since launch.
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case failed(UpdateCheckError)
        /// This build has no version to compare (`swift run`), so it can't tell; the newest release is shown.
        case unknownVersion(AppRelease)
    }

    /// What is kept between launches.
    public struct Saved: Codable, Equatable, Sendable {
        public var checksAutomatically: Bool
        /// The last check that got an answer.
        public var lastChecked: Date?
        /// A version the user skipped: not offered by itself again, though a check still finds it.
        public var dismissed: AppVersion?
        /// The newer release the last answer named, so a relaunch still offers it before the next check.
        public var found: AppRelease?

        public init(checksAutomatically: Bool = true, lastChecked: Date? = nil, dismissed: AppVersion? = nil, found: AppRelease? = nil) {
            self.checksAutomatically = checksAutomatically
            self.lastChecked = lastChecked
            self.dismissed = dismissed
            self.found = found
        }
    }

    /// How often it checks by itself.
    public static let interval = Duration.seconds(24 * 60 * 60)
    /// How often the daily loop looks whether a check is due: a Mac asleep or offline at the due time checks soon after.
    static let poll = Duration.seconds(60 * 60)
    /// After launch, before the first check, so launching never waits on the network.
    static let launchDelay = Duration.seconds(10)

    public private(set) var status = Status.idle
    public private(set) var saved: Saved
    /// The running build's version; nil when it has none.
    public let current: AppVersion?
    /// Times the daily loop has looked whether a check is due; tests wait on it.
    @ObservationIgnored private(set) var looks = 0

    public var checksAutomatically: Bool {
        get { saved.checksAutomatically }
        set {
            guard newValue != saved.checksAutomatically else { return }
            saved.checksAutomatically = newValue
            persist(saved)
            if newValue, isDue { Task { await self.check() } }
        }
    }

    /// The newer release found, whatever later checks that failed said.
    public var available: AppRelease? {
        guard let found = saved.found, let current, current < found.version else { return nil }
        return found
    }

    /// A newer release to tell the user about without being asked: found, and not skipped.
    public var notice: AppRelease? {
        guard let available, available.version != saved.dismissed else { return nil }
        return available
    }

    @ObservationIgnored private let feed: any ReleaseFeed
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let persist: @MainActor (Saved) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The check under way; a check asked for meanwhile waits for it instead of starting another.
    @ObservationIgnored private var running: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    /// - Parameters:
    ///   - current: the running build's version (its bundle's short version); nil when it has none.
    ///   - saved: the choices and the last answer, kept between launches; `persist` saves a change.
    ///   - clock: paces the daily loop; `now` dates the checks.
    public init(
        current: AppVersion?, feed: any ReleaseFeed, saved: Saved, clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() }, persist: @escaping @MainActor (Saved) -> Void = { _ in }
    ) {
        self.current = current
        self.feed = feed
        self.saved = saved
        self.clock = clock
        self.now = now
        self.persist = persist
        if let available { status = .available(available) }
    }

    /// Checks by itself from now on: a little after launch, then whenever a day has passed since the last answer,
    /// while checking automatically is on. A build without a version never checks by itself.
    public func start() {
        guard task == nil else { return }
        let clock = clock
        task = Task { [weak self] in
            guard (try? await clock.sleep(for: Self.launchDelay)) != nil else { return }
            while !Task.isCancelled {
                // Held only while it looks, so the loop never keeps the checker alive.
                await self?.checkIfDue()
                guard self != nil, (try? await clock.sleep(for: Self.poll)) != nil else { return }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Checks now (Check for Updates…), whether or not checking automatically is on. A check already under way answers
    /// this one too.
    public func check() async {
        if let running { return await running.value }
        let task = Task { await self.ask() }
        running = task
        await task.value
        running = nil
    }

    /// Stops offering the release found until a newer one is out.
    public func dismiss() {
        guard let notice else { return }
        saved.dismissed = notice.version
        persist(saved)
    }

    /// A day since the last answer, or none yet, or a clock set back past it.
    var isDue: Bool {
        guard saved.checksAutomatically, current != nil else { return false }
        guard let last = saved.lastChecked else { return true }
        let elapsed = now().timeIntervalSince(last)
        return elapsed < 0 || elapsed >= TimeInterval(Self.interval.components.seconds)
    }

    private func checkIfDue() async {
        looks += 1
        if isDue { await check() }
    }

    private func ask() async {
        status = .checking
        do throws(UpdateCheckError) {
            let latest = try await feed.latest()
            saved.lastChecked = now()
            guard let current else {
                persist(saved)
                return status = .unknownVersion(latest)
            }
            // A release whose zip isn't attached yet (its build still running) isn't out.
            let isNewer = current < latest.version && latest.download != nil
            saved.found = isNewer ? latest : nil
            persist(saved)
            status = isNewer ? .available(latest) : .upToDate
            Self.log.info("Latest release \(latest.version, privacy: .public), running \(current, privacy: .public)")
        } catch {
            // What was found stays found: the notice doesn't vanish while offline.
            Self.log.error("Checking for updates failed: \(String(describing: error), privacy: .public)")
            status = .failed(error)
        }
    }
}
