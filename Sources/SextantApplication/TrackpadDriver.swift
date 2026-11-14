import Foundation
import Observation
import SextantDomain
import os

/// Drives the Navigator trackpad (ADR 0068): with the user's switch on and both permissions granted, it puts the pad in
/// touchpad mode whenever one connects or the Mac wakes, turns its touches into pointer events, and puts it back in
/// mouse mode when the switch goes off, a permission goes away, or Sextant quits. App-wide.
///
/// It never switches a pad to touchpad mode unless it can post events: in that mode nothing else moves the pointer.
@MainActor
@Observable
public final class TrackpadDriver {
    public enum Status: Hashable, Sendable {
        /// The user hasn't turned the driver on.
        case off
        /// On, but macOS won't let Sextant read the trackpad.
        case needsInputMonitoring
        /// On, but macOS won't let Sextant move the pointer.
        case needsAccessibility
        /// On and allowed, with no Navigator trackpad connected.
        case waitingForTrackpad
        /// Driving at least one trackpad.
        case running
        /// Writing the input mode failed; the pad may still be in mouse mode.
        case failed(TrackpadError)
    }

    public private(set) var settings: TrackpadSettings
    public private(set) var status: Status = .off {
        didSet {
            guard status != oldValue else { return }
            logger.info("Navigator trackpad: \(String(describing: self.status), privacy: .public)")
        }
    }
    /// The Mac's pointer settings as last read, for Settings to show what "follow the Mac" means.
    public private(set) var systemPreferences = SystemPointerPreferences.standard

    private let link: any TrackpadLink
    private let output: any PointerOutput
    private let system: any SystemPointerSettings
    private let runner: TrackpadRunner
    private let save: @MainActor (TrackpadSettings) -> Void
    private let clearPermissions: @Sendable () async -> Void
    /// Each permission as last checked, for Settings to show; both false until the driver is first turned on.
    public private(set) var hasInputMonitoring = false
    public private(set) var hasAccessibility = false
    private var updates: Task<Void, Never>?
    private var queue: Task<Void, Never>?
    private var isRunning = false
    private let logger = Logger(subsystem: "com.sextant.app", category: "application")

    /// - Parameters:
    ///   - clock: paces momentum and timeouts (about every 8 ms while a gesture needs it).
    ///   - now: the time in seconds on a monotonic clock, stamped on every frame and tick.
    ///   - save: stores changed settings.
    public init(
        link: any TrackpadLink, output: any PointerOutput, system: any SystemPointerSettings, clock: any Clock<Duration>,
        now: @escaping @Sendable () -> Double, settings: TrackpadSettings, save: @escaping @MainActor (TrackpadSettings) -> Void,
        clearPermissions: @escaping @Sendable () async -> Void = {}
    ) {
        self.clearPermissions = clearPermissions
        self.link = link
        self.output = output
        self.system = system
        self.settings = settings.clamped
        self.save = save
        runner = TrackpadRunner(
            link: link, output: output, clock: clock, now: now,
            configuration: Self.configuration(settings.clamped, SystemPointerPreferences.standard))
    }

    /// At launch: resumes driving if the user left it on, without asking for any permission.
    public func start() async { await serially { await $0.activate(prompting: false) } }

    /// The user's switch. Turning it on asks for Input Monitoring and Accessibility as needed.
    public func setEnabled(_ isEnabled: Bool) async {
        if isEnabled != settings.isEnabled {
            settings.isEnabled = isEnabled
            save(settings)
        }
        await serially { await $0.activate(prompting: isEnabled) }
    }

    /// Changes any other setting at once (sliders stay responsive); the engine uses it from the next report.
    public func update(_ change: (inout TrackpadSettings) -> Void) {
        var changed = settings
        change(&changed)
        changed.isEnabled = settings.isEnabled
        changed = changed.clamped
        guard changed != settings else { return }
        settings = changed
        save(settings)
        Task { await serially { await $0.runner.configure(Self.configuration($0.settings, $0.systemPreferences)) } }
    }

    /// Every setting back to its default. The switch stays as it is, and so does the pad's rotation: that's how the
    /// pad is mounted, not a preference.
    public func resetToDefaults() {
        update { $0 = TrackpadSettings(rotation: $0.rotation) }
    }

    /// Re-reads the permissions and the Mac's pointer settings: when Sextant comes forward and Settings opens. Starts
    /// driving once both permissions are there, and stops (back to mouse mode) if one went away.
    public func refresh() async { await serially { await $0.activate(prompting: false) } }

    /// The user asked (Check Again, Open Accessibility…): asks macOS for whichever permission is missing, so Sextant is
    /// listed in System Settings even when the switch was already on at launch, which only checks.
    public func requestPermissions() async {
        guard settings.isEnabled else { return }
        await serially { await $0.activate(prompting: true) }
    }

    /// Reset Permissions: clears what macOS remembers about Sextant's two permissions, then asks afresh. For a grant
    /// that shows as on in System Settings but no longer applies, as happens when the app was replaced by a new build.
    public func resetPermissions() async {
        guard settings.isEnabled else { return }
        await serially { driver in
            await driver.deactivate()
            await driver.clearPermissions()
            await driver.activate(prompting: true)
        }
    }

    /// The Mac woke: the pad lost power and is in mouse mode again.
    public func systemDidWake() async {
        await serially { driver in
            guard driver.isRunning else { return }
            driver.systemPreferences = await driver.system.current()
            await driver.runner.configure(Self.configuration(driver.settings, driver.systemPreferences))
            await driver.runner.reassert()
        }
    }

    /// Quitting: lets go of anything held and puts every pad back in mouse mode.
    public func shutDown() async {
        await serially { driver in
            await driver.deactivate()
            driver.status = .off
        }
    }

    /// Runs `body` after every earlier operation has finished, so a quick off-and-on, or a quit during a start, never
    /// interleaves two operations at their awaits.
    private func serially(_ body: @escaping @MainActor (TrackpadDriver) async -> Void) async {
        let previous = queue
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            await body(self)
        }
        queue = task
        await task.value
    }

    // MARK: Running

    private func activate(prompting: Bool) async {
        guard settings.isEnabled else {
            await deactivate()
            status = .off
            return
        }
        // Turning it on asks for both at once: the first ask for Input Monitoring only lists Sextant in System Settings,
        // and Accessibility must be asked for once to be listed too.
        let canRead = prompting ? await link.requestInputAccess() : await link.hasInputAccess()
        let canPost = prompting ? await output.requestAccess() : await output.hasAccess()
        hasInputMonitoring = canRead
        hasAccessibility = canPost
        guard canRead else {
            await deactivate()
            status = .needsInputMonitoring
            return
        }
        guard canPost else {
            await deactivate()
            status = .needsAccessibility
            return
        }
        systemPreferences = await system.current()
        await runner.configure(Self.configuration(settings, systemPreferences))
        // The switch may have gone off while the permissions were checked; the queued off will run next anyway.
        guard settings.isEnabled, !isRunning else { return }
        isRunning = true
        status = .waitingForTrackpad
        let stream = await runner.start()
        updates = Task { [weak self] in
            for await update in stream { self?.apply(update) }
        }
    }

    private func deactivate() async {
        guard isRunning else { return }
        isRunning = false
        updates?.cancel()
        updates = nil
        await runner.stop()
    }

    private func apply(_ update: TrackpadRunner.Update) {
        guard isRunning else { return }
        if let failure = update.failure {
            logger.error("Navigator trackpad: \(failure.localizedDescription, privacy: .public)")
            status = .failed(failure)
        } else {
            status = update.pads > 0 ? .running : .waitingForTrackpad
        }
    }

    private static func configuration(_ settings: TrackpadSettings, _ system: SystemPointerPreferences) -> GestureConfiguration {
        GestureConfiguration(
            settings: settings, curves: system.curves, systemTrackingSpeed: system.trackingSpeed,
            systemNaturalScrolling: system.naturalScrolling, systemDoubleClickInterval: system.doubleClickInterval)
    }
}

/// The driver's off-main half: reads the session, feeds the engine, posts what it says and ticks it while it asks, so
/// 150 reports a second never wait on the main thread.
///
/// Each `start` begins a new run. Whatever an earlier run left suspended (a mode write, a post) sees it isn't current
/// when it resumes and undoes its part: a touchpad-mode write that lands after a stop is followed by a mouse-mode write.
actor TrackpadRunner {
    /// The pads in touchpad mode now, and the last switch that failed (until one succeeds or that pad goes), in one
    /// value so the driver never reads a stale half.
    struct Update: Sendable {
        var pads: Int
        var failure: TrackpadError?
    }

    private let link: any TrackpadLink
    private let output: any PointerOutput
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Double
    private var engine: GestureEngine
    private var run = 0
    private var isActive = false
    private var pads: Set<TrackpadID> = []
    private var failed: [TrackpadID: TrackpadError] = [:]
    private var session: Task<Void, Never>?
    private var ticker: (id: Int, task: Task<Void, Never>)?
    private var tickers = 0
    private var continuation: AsyncStream<Update>.Continuation?

    static let tickInterval = Duration.milliseconds(8)
    private let logger = Logger(subsystem: "com.sextant.app", category: "application")

    init(
        link: any TrackpadLink, output: any PointerOutput, clock: any Clock<Duration>, now: @escaping @Sendable () -> Double,
        configuration: GestureConfiguration
    ) {
        self.link = link
        self.output = output
        self.clock = clock
        self.now = now
        engine = GestureEngine(configuration: configuration)
    }

    func configure(_ configuration: GestureConfiguration) {
        engine.configuration = configuration
        scheduleTicks()
    }

    /// Opens the session; the stream reports the pads until `stop`.
    func start() -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream.makeStream(of: Update.self)
        run += 1
        isActive = true
        self.continuation = continuation
        let current = run
        let events = link.session()
        session = Task {
            for await event in events {
                guard !Task.isCancelled else { break }
                await self.handle(event, run: current)
            }
        }
        return stream
    }

    /// Ends the run: events still arriving are ignored, the ticks stop, anything held is let go, mouse mode is written
    /// to every pad while the session is still open, and then the session closes (and the link restores any pad an
    /// in-flight switch reached).
    func stop() async {
        guard isActive else { return }
        isActive = false
        run += 1
        if let ticker {
            ticker.task.cancel()
            self.ticker = nil
        }
        await post(engine.reset())
        let switched = pads
        pads = []
        failed = [:]
        for pad in switched { try? await link.setInputMode(.mouse, on: pad) }
        logger.info("Navigator trackpad: stopped, \(switched.count, privacy: .public) back in mouse mode")
        let session = self.session
        self.session = nil
        session?.cancel()
        await session?.value
        continuation?.finish()
        continuation = nil
    }

    /// Writes touchpad mode again to every pad (after a wake).
    func reassert() async {
        guard isActive else { return }
        let current = run
        await post(engine.reset())
        for pad in pads where run == current { await switchToTouchpad(pad, run: current) }
        report()
    }

    private func handle(_ event: TrackpadEvent, run current: Int) async {
        guard current == run else { return }
        switch event {
        case let .attached(pad):
            await switchToTouchpad(pad, run: current)
            report()
        case let .frame(frame, pad):
            // A pad still in mouse mode moves the pointer itself; only pads this run switched are driven.
            guard pads.contains(pad) else { return }
            var stamped = frame
            stamped.timestamp = now()
            await post(engine.handle(stamped))
            scheduleTicks()
        case let .detached(pad):
            failed[pad] = nil
            if pads.remove(pad) != nil { await post(engine.reset()) }
            report()
        case let .failed(error):
            failed[TrackpadID(0)] = error
            report()
        }
    }

    /// A pad counts as driven only once the switch succeeded. A write that lands after the run ended is undone.
    private func switchToTouchpad(_ pad: TrackpadID, run current: Int) async {
        do {
            try await link.setInputMode(.touchpad, on: pad)
            logger.info("Navigator trackpad \(pad.rawValue, privacy: .public): touchpad mode")
            guard current == run else {
                try? await link.setInputMode(.mouse, on: pad)
                return
            }
            pads.insert(pad)
            failed[pad] = nil
        } catch {
            logger.error(
                "Navigator trackpad \(pad.rawValue, privacy: .public): switch failed, \(error.localizedDescription, privacy: .public)")
            guard current == run else { return }
            pads.remove(pad)
            failed[pad] = error
        }
    }

    private func report() {
        continuation?.yield(Update(pads: pads.count, failure: failed.values.first))
    }

    private func post(_ intents: [PointerIntent]) async {
        guard !intents.isEmpty else { return }
        await output.post(intents)
    }

    private func scheduleTicks() {
        guard isActive, engine.needsTicks, ticker == nil else { return }
        tickers += 1
        let id = tickers
        let task = Task {
            while !Task.isCancelled {
                do { try await clock.sleep(for: Self.tickInterval) } catch { break }
                guard await self.tick(id) else { break }
            }
        }
        ticker = (id, task)
    }

    /// One tick; false when the engine needs no more, or this ticker was replaced or stopped.
    private func tick(_ id: Int) async -> Bool {
        guard isActive, ticker?.id == id else { return false }
        await post(engine.tick(at: now()))
        guard ticker?.id == id else { return false }
        guard isActive, engine.needsTicks else {
            ticker = nil
            return false
        }
        return true
    }
}
