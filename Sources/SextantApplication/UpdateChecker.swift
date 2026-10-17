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
    public struct Saved: Equatable, Sendable {
        public var checksAutomatically: Bool
        /// The last check that got an answer.
        public var lastChecked: Date?
        /// A version the user dismissed: not offered by itself again, though a check still finds it.
        public var dismissed: AppVersion?

        public init(checksAutomatically: Bool = true, lastChecked: Date? = nil, dismissed: AppVersion? = nil) {
            self.checksAutomatically = checksAutomatically
            self.lastChecked = lastChecked
            self.dismissed = dismissed
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

    public var checksAutomatically: Bool {
        get { saved.checksAutomatically }
        set {
            guard newValue != saved.checksAutomatically else { return }
            saved.checksAutomatically = newValue
            persist(saved)
            if newValue, isDue { Task { await self.check(automatic: true) } }
        }
    }

    /// A newer release to tell the user about without being asked: found, and not dismissed.
    public var notice: AppRelease? {
        guard case let .available(release) = status, release.version != saved.dismissed else { return nil }
        return release
    }

    @ObservationIgnored private let feed: any ReleaseFeed
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let persist: @MainActor (Saved) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    /// - Parameters:
    ///   - current: the running build's version (its bundle's short version); nil when it has none.
    ///   - saved: the choices and dates kept between launches; `persist` saves a change.
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
    }

    /// Checks by itself from now on: a little after launch, then whenever a day has passed since the last answer,
    /// while checking automatically is on. A build without a version never checks by itself.
    public func start() {
        guard task == nil else { return }
        let clock = clock
        task = Task { [weak self] in
            guard (try? await clock.sleep(for: Self.launchDelay)) != nil else { return }
            while !Task.isCancelled {
                guard let self else { return }
                if isDue { await check(automatic: true) }
                guard (try? await clock.sleep(for: Self.poll)) != nil else { return }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Checks now (Check for Updates…), whether or not checking automatically is on.
    public func check() async { await check(automatic: false) }

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

    private func check(automatic: Bool) async {
        if case .checking = status { return }
        let before = status
        status = .checking
        do throws(UpdateCheckError) {
            let latest = try await feed.latest()
            saved.lastChecked = now()
            persist(saved)
            guard let current else { return status = .unknownVersion(latest) }
            status = current < latest.version ? .available(latest) : .upToDate
            Self.log.info("Latest release \(latest.version, privacy: .public), running \(current, privacy: .public)")
        } catch {
            Self.log.error("Checking for updates failed: \(String(describing: error), privacy: .public)")
            // A check by itself that fails keeps what was known; one the user asked for says why.
            if automatic, before != .idle { status = before } else { status = .failed(error) }
        }
    }
}
