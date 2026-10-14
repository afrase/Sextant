import Foundation
import Observation
import SextantDomain
import os

/// Counts key presses for the Heatmap (spec §8.5, ADR 0053). App-wide. Off until the user turns it on, and then it
/// counts only what a paired Live View session reports (``LiveSession/activity()``), only for a layout the library holds
/// (``OnKeyboard``), and never during secure input. It keeps hourly counts by layer id and key index, written to a
/// ``HeatmapStore`` every minute and at quit; nothing finer than the hour is stored, and nothing is logged.
@MainActor
@Observable
public final class HeatmapRecorder {
    /// What the recorder is doing now.
    public enum Status: Equatable, Sendable {
        /// The user hasn't turned recording on.
        case off
        /// On, but counting nothing until the reason passes.
        case waiting(Pause)
        /// Counting presses for this library layout.
        case recording(UUID)
    }

    /// Why recording that is on counts nothing.
    public enum Pause: Equatable, Sendable {
        case noKeyboard, flashMode, liveViewOff, heldByAnotherApp
        /// The keyboard runs a layout, or a version of one, the library doesn't hold.
        case otherLayout
        case secureInput
    }

    /// A layout's stored hours as they were read, and the store's ``HeatmapRecorder/version`` then.
    public struct Snapshot: Sendable {
        public let hours: [HeatmapHour]
        public let version: Int

        public init(hours: [HeatmapHour], version: Int) {
            self.hours = hours
            self.version = version
        }
    }

    /// Recording is on (Settings › Privacy); the choice is saved.
    public var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            persist(isOn, retentionDays)
            lastLayer = nil
            if !isOn { Task { await flush() } }
        }
    }
    /// How long counts are kept, in days; older hours are deleted. The choice is saved.
    public var retentionDays: Int {
        didSet {
            guard retentionDays != oldValue else { return }
            persist(isOn, retentionDays)
            Task { await prune() }
        }
    }
    /// Bumped whenever stored counts change (a write, a prune, a clear), so windows read them again.
    public private(set) var version = 0
    /// Presses counted since launch, so a window's heat follows typing between writes.
    public private(set) var counted = 0
    /// Presses counted today, on this Mac's calendar, for the layout being recorded; nil before one has been.
    public private(set) var today: Int?
    /// The last write or read that failed; nil once one succeeds.
    public private(set) var lastError: HeatmapStoreError?

    /// Counts not yet written, by layout and hour.
    @ObservationIgnored private var pending: [UUID: [Date: HeatmapHour]] = [:]
    /// The latest writes, kept so a window still holding counts read before them can add them.
    @ObservationIgnored private var written: [(version: Int, layoutID: UUID, hours: [HeatmapHour])] = []
    /// The times of the last minute's presses, in memory only, for words per minute.
    @ObservationIgnored private var recentPresses: [Date] = []
    @ObservationIgnored private var lastLayer: Int?
    @ObservationIgnored private var todayLayout: UUID?
    @ObservationIgnored private var todayStart: Date?
    @ObservationIgnored private var prunedDay: Date?
    /// Reads, writes, prunes and clears, one after another: a read then sees each write whole or not at all.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    @ObservationIgnored private let live: LiveSession
    @ObservationIgnored private let onKeyboard: OnKeyboard
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let layouts: any LayoutLibrary
    @ObservationIgnored private let store: any HeatmapStore
    @ObservationIgnored private let board: BoardDefinition
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let persist: @MainActor (Bool, Int) -> Void
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    /// How often counts are written.
    static let flushInterval = Duration.seconds(60)
    /// Writes kept for windows that read before them; a window rereads within moments of each.
    static let keptWrites = 32

    /// - Parameters:
    ///   - layouts: the library's store, which says whether a layout that left the library is gone (trashed) or only
    ///     unreadable for now.
    ///   - isOn, retentionDays: the saved choices (Settings › Privacy); `persist` saves a change.
    ///   - clock: paces the writes; `now` and `calendar` date the hours and the day.
    public init(
        live: LiveSession, onKeyboard: OnKeyboard, library: Library, layouts: any LayoutLibrary, store: any HeatmapStore,
        board: BoardDefinition = .voyager, clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current, isOn: Bool, retentionDays: Int,
        persist: @escaping @MainActor (Bool, Int) -> Void = { _, _ in }
    ) {
        self.live = live
        self.onKeyboard = onKeyboard
        self.library = library
        self.layouts = layouts
        self.store = store
        self.board = board
        self.clock = clock
        self.now = now
        self.calendar = calendar
        self.isOn = isOn
        self.retentionDays = retentionDays
        self.persist = persist
    }

    public var status: Status {
        guard isOn else { return .off }
        switch live.connection {
        case .noKeyboard: return .waiting(.noKeyboard)
        case .bootloader: return .waiting(.flashMode)
        case .liveOff: return .waiting(.liveViewOff)
        case .heldByAnotherApp: return .waiting(.heldByAnotherApp)
        case .connected: break
        }
        guard let running = onKeyboard.running else { return .waiting(.otherLayout) }
        return live.isSecureInputOn ? .waiting(.secureInput) : .recording(running.entry.id)
    }

    /// Follows the keyboard's presses, writes every minute, prunes old hours and drops a trashed layout's counts, for the
    /// app's lifetime.
    public func start() {
        guard tasks.isEmpty else { return }
        let feed = live.activity()
        let (clock, library) = (clock, library)
        tasks = [
            Task { [weak self] in
                for await event in feed { self?.record(event) }
            },
            Task { [weak self] in
                while (try? await clock.sleep(for: Self.flushInterval)) != nil {
                    await self?.flush()
                }
            },
            Task { [weak self] in
                var known: Set<UUID>?
                for await (loaded, ids) in Observations({ (library.hasLoaded, Set(library.entries.map(\.id))) }) where loaded {
                    for id in (known ?? []).subtracting(ids) { await self?.forget(id) }
                    known = ids
                }
            },
        ]
        Task { await prune() }
    }

    // MARK: Reading

    /// A layout's stored hours from `start` (all when nil). Never overlaps a write, so ``unwritten(of:from:after:)`` with
    /// the snapshot's version adds exactly what it lacks.
    public func snapshot(of layoutID: UUID, from start: Date?) async -> Snapshot {
        await serially { [store] in
            do throws(HeatmapStoreError) {
                let hours = try await store.hours(of: layoutID, from: start)
                self.lastError = nil
                return Snapshot(hours: hours, version: self.version)
            } catch {
                self.fail(error)
                return Snapshot(hours: [], version: self.version)
            }
        }
    }

    /// Counts a snapshot taken at `version` lacks: written since, or not written yet. Observing it follows each press.
    public func unwritten(of layoutID: UUID, from start: Date?, after version: Int) -> [HeatmapHour] {
        _ = counted
        let since = written.filter { $0.version > version && $0.layoutID == layoutID }.flatMap(\.hours)
        let hours = since + (pending[layoutID].map { Array($0.values) } ?? [])
        return hours.filter { hour in start.map { hour.start >= $0 } ?? true }
    }

    /// Words per minute over the last minute (five key presses a word); 0 when idle. Never stored.
    public func wordsPerMinute(at date: Date) -> Int {
        recentPresses.filter { date.timeIntervalSince($0) < 60 }.count / 5
    }

    // MARK: Writing

    /// Writes the counts not yet written. Called every minute, when recording is turned off, and at quit.
    public func flush() async {
        await serially {
            let batch = self.pending
            self.pending = [:]
            for (id, hours) in batch {
                guard await !self.write(Array(hours.values), to: id) else { continue }
                // Kept for the next write, with whatever was counted meanwhile.
                for (start, hour) in hours { self.pending[id, default: [:]][start, default: HeatmapHour(start: start)].add(hour) }
            }
            self.written.removeFirst(max(self.written.count - Self.keptWrites, 0))
        }
        let day = calendar.startOfDay(for: now())
        if prunedDay != day { await prune() }
    }

    /// Adds hours to the store; false when that failed.
    private func write(_ hours: [HeatmapHour], to id: UUID) async -> Bool {
        do throws(HeatmapStoreError) {
            try await store.add(hours, to: id)
        } catch {
            fail(error)
            return false
        }
        lastError = nil
        version += 1
        written.append((version, id, hours))
        return true
    }

    /// Deletes a layout's counts, or every layout's when nil (Clear Heatmap Data…).
    public func clear(_ layoutID: UUID?) async {
        await serially {
            if let layoutID {
                self.pending[layoutID] = nil
                self.written.removeAll { $0.layoutID == layoutID }
            } else {
                self.pending = [:]
                self.written = []
            }
            do throws(HeatmapStoreError) {
                try await self.store.clear(layoutID)
                self.lastError = nil
            } catch {
                self.fail(error)
            }
            self.version += 1
            if layoutID == nil || layoutID == self.todayLayout { self.today = self.today.map { _ in 0 } }
        }
    }

    /// Deletes the hours older than the retention allows.
    func prune() async {
        let date = now()
        prunedDay = calendar.startOfDay(for: date)
        let cutoff = HeatmapHour.start(of: date).addingTimeInterval(-Double(retentionDays) * 24 * HeatmapHour.duration)
        await serially {
            for id in self.pending.keys { self.pending[id] = self.pending[id]?.filter { $0.key >= cutoff } }
            do throws(HeatmapStoreError) {
                try await self.store.prune(before: cutoff)
                self.lastError = nil
            } catch {
                self.fail(error)
            }
            self.version += 1
        }
    }

    // MARK: Counting

    private func record(_ event: LiveActivity) {
        // The feed is silent during secure input, asked at every event (ADR 0050), so nothing typed then arrives.
        guard isOn, let running = onKeyboard.running else { return }
        let id = running.entry.id
        if id != todayLayout {
            todayLayout = id
            lastLayer = nil
            loadToday()
        }
        let date = now()
        let hour = HeatmapHour.start(of: date)
        switch event {
        case let .keyDown(index, layer):
            guard (0..<board.keyCount).contains(index), let layerID = running.layout.layers[safe: layer]?.id else { return }
            pending[id, default: [:]][hour, default: HeatmapHour(start: hour)].presses[layerID, default: [:]][index, default: 0] += 1
            counted += 1
            recentPresses = recentPresses.filter { date.timeIntervalSince($0) < 60 } + [date]
            if calendar.startOfDay(for: date) != todayStart { loadToday() } else { today = (today ?? 0) + 1 }
        case let .layer(layer):
            // A pairing reports the layer it finds the keyboard on, which isn't a move.
            defer { lastLayer = layer }
            guard let last = lastLayer, last != layer, let layerID = running.layout.layers[safe: layer]?.id else { return }
            pending[id, default: [:]][hour, default: HeatmapHour(start: hour)].layerEntries[layerID, default: 0] += 1
        case .keyUp, .lighting, .refused: return
        }
    }

    /// Reads today's count for the layout being recorded: what is stored plus what isn't yet.
    private func loadToday() {
        guard let id = todayLayout else { return }
        let start = calendar.startOfDay(for: now())
        todayStart = start
        Task {
            let snapshot = await snapshot(of: id, from: start)
            guard todayLayout == id, todayStart == start else { return }
            let hours = snapshot.hours + unwritten(of: id, from: start, after: snapshot.version)
            today = hours.reduce(0) { $0 + $1.presses.values.reduce(0) { $0 + $1.values.reduce(0, +) } }
        }
    }

    /// A layout left the library: its counts go only if its package is gone (trashed), not if it is unreadable for now.
    private func forget(_ id: UUID) async {
        guard await layouts.location(of: id) == nil else { return }
        await clear(id)
    }

    private func fail(_ error: HeatmapStoreError) {
        Self.log.error("Heatmap store: \(String(describing: error), privacy: .public)")
        lastError = error
    }

    /// Runs `body` after every operation queued before it.
    private func serially<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            return await body()
        }
        queue = Task { _ = await task.value }
        return await task.value
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
