import Foundation
import Observation
import SextantDomain
import os

/// Counts key presses for the Heatmap (spec §8.5, ADR 0053). App-wide. Off until the user turns it on, and then it
/// counts only what a paired Live View session reports (``LiveSession/activity()``), only for a layout the library holds
/// (``OnKeyboard``), and never during secure input. It keeps hourly counts by layer id and key index, written to a
/// ``HeatmapStore`` every minute and at quit; nothing finer than the hour is stored, and nothing is logged. A write adds
/// at least ``minimumWrite`` presses (ADR 0066).
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

    /// A layout's stored counts as they were read, and the store's ``HeatmapRecorder/version`` then.
    public struct Snapshot: Sendable {
        public let heatmap: KeyHeatmap
        public let version: Int

        public init(heatmap: KeyHeatmap, version: Int) {
            self.heatmap = heatmap
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
    /// How long counts are kept, in days; older hours are deleted when it changes. The choice is saved.
    public var retentionDays: Int {
        didSet {
            guard retentionDays != oldValue else { return }
            persist(isOn, retentionDays)
            Task { await prune() }
        }
    }
    /// Bumped whenever stored counts change (a write, a prune, a clear), so windows read them again.
    public private(set) var version = 0
    /// Presses counted since launch.
    public private(set) var counted = 0
    /// Bumped by every press and layer move counted, and when held counts move into a later hour, so a window's heat
    /// follows typing between writes.
    public private(set) var changes = 0
    /// The hour now, moved on by the minute's write, so a window's range slides while nobody types.
    public private(set) var hour: Date
    /// A read, write, prune or clear that failed, until that kind of operation succeeds again.
    public private(set) var lastError: HeatmapStoreError?
    /// Today's presses as of the last read, for the layout being recorded on the day ``todayStart`` begins.
    private var today: Int?

    /// Counts not yet written, by layout and hour.
    @ObservationIgnored private var pending: [UUID: [Date: HeatmapHour]] = [:]
    /// Counts being written now: still unwritten for windows until the write lands or fails.
    @ObservationIgnored private var inFlight: [UUID: [Date: HeatmapHour]] = [:]
    @ObservationIgnored private var failing: Set<Operation> = []
    /// The latest writes, kept so a window still holding counts read before them can add them.
    @ObservationIgnored private var written: [(version: Int, layoutID: UUID, hours: [HeatmapHour])] = []
    /// The times of the last minute's presses, in memory only, for words per minute.
    @ObservationIgnored private var recentPresses: [Date] = []
    @ObservationIgnored private var lastLayer: Int?
    @ObservationIgnored private var todayLayout: UUID?
    private var todayStart: Date?
    @ObservationIgnored private var prunedDay: Date?
    /// Reads, writes, prunes and clears, one after another: a read then sees each write whole or not at all.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    @ObservationIgnored private let live: LiveSession
    @ObservationIgnored private let onKeyboard: OnKeyboard
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let store: any HeatmapStore
    @ObservationIgnored private let board: BoardDefinition
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let persist: @MainActor (Bool, Int) -> Void
    /// The fewest presses one write adds to a layout's counts.
    @ObservationIgnored let minimumWrite: Int
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    /// How often counts are written.
    static let flushInterval = Duration.seconds(60)
    /// Writes kept for windows that read before them; a window rereads within moments of each.
    static let keptWrites = 32
    /// The fewest presses a write adds, so no write's counts are a password typed outside secure input and little else:
    /// anyone reading the files a minute apart could tell them apart from the rest (ADR 0066). Fewer wait in memory
    /// for more, and are lost if Sextant quits first.
    public static let defaultMinimumWrite = 100

    /// - Parameters:
    ///   - library: says which layouts were moved to the Trash, whose counts go with them.
    ///   - isOn, retentionDays: the saved choices (Settings › Privacy); `persist` saves a change.
    ///   - clock: paces the writes; `now` and `calendar` date the hours and the day.
    ///   - minimumWrite: the fewest presses one write adds; tests that write a press or two pass 0.
    public init(
        live: LiveSession, onKeyboard: OnKeyboard, library: Library, store: any HeatmapStore,
        board: BoardDefinition = .voyager, clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current, isOn: Bool, retentionDays: Int,
        minimumWrite: Int = defaultMinimumWrite, persist: @escaping @MainActor (Bool, Int) -> Void = { _, _ in }
    ) {
        self.live = live
        self.onKeyboard = onKeyboard
        self.library = library
        self.store = store
        self.board = board
        self.clock = clock
        self.now = now
        self.calendar = calendar
        self.isOn = isOn
        self.retentionDays = retentionDays
        self.persist = persist
        self.minimumWrite = minimumWrite
        hour = HeatmapHour.start(of: now())
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

    /// Follows the keyboard's presses and recording's status, writes every minute, prunes old hours and drops a trashed
    /// layout's counts, for the app's lifetime.
    public func start() {
        guard tasks.isEmpty else { return }
        let feed = live.activity()
        let (clock, library) = (clock, library)
        tasks = [
            Task { [weak self] in
                for await event in feed { self?.record(event) }
            },
            Task { [weak self] in
                for await status in Observations({ [weak self] in self?.status }) { self?.follow(status) }
            },
            Task { [weak self, live] in
                // A link session can end with the keyboard still connected (a failed write), the status unchanged: the
                // next session reopens a second or more later, and its pairing reports a layer that may have been
                // reached meanwhile.
                for await canSend in Observations({ live.canSend }) where !canSend { self?.lastLayer = nil }
            },
            Task { [weak self] in
                while (try? await clock.sleep(for: Self.flushInterval)) != nil {
                    await self?.flush()
                }
            },
            Task { [weak self] in
                // Only Sextant's own Move to Trash: a package that fails to read for now leaves the library but keeps its
                // counts.
                var cleared: Set<UUID> = []
                for await trashed in Observations({ library.trashed }) {
                    for id in trashed.subtracting(cleared) { await self?.clear(id) }
                    cleared = trashed
                }
            },
        ]
        Task { await prune() }
    }

    // MARK: Reading

    /// A layout's stored counts from `start` (all when nil). Never overlaps a write, so ``unwritten(of:from:after:)`` with
    /// the snapshot's version adds exactly what it lacks.
    public func snapshot(of layoutID: UUID, from start: Date?) async -> Snapshot {
        await serially { [store] in
            do throws(HeatmapStoreError) {
                let heatmap = try await store.heatmap(of: layoutID, from: start)
                self.succeed(.read)
                return Snapshot(heatmap: heatmap, version: self.version)
            } catch {
                self.fail(.read, error)
                return Snapshot(heatmap: KeyHeatmap(), version: self.version)
            }
        }
    }

    /// Counts a snapshot taken at `version` lacks: written since, being written, or not written yet. Observing it follows
    /// each press and layer move.
    public func unwritten(of layoutID: UUID, from start: Date?, after version: Int) -> [HeatmapHour] {
        _ = changes
        let since = written.filter { $0.version > version && $0.layoutID == layoutID }.flatMap(\.hours)
        let hours = since + (inFlight[layoutID].map { Array($0.values) } ?? []) + (pending[layoutID].map { Array($0.values) } ?? [])
        return hours.filter { hour in start.map { hour.start >= $0 } ?? true }
    }

    /// Presses counted today, on this Mac's calendar, for the layout being recorded; nil until they have been read.
    public func pressesToday(at date: Date) -> Int? {
        guard let todayStart else { return nil }
        // A new day has none until its first press, which reads the day again.
        return calendar.startOfDay(for: date) == todayStart ? today : 0
    }

    /// Words per minute over the last minute (five key presses a word); 0 when idle. Never stored.
    public func wordsPerMinute(at date: Date) -> Int {
        recentPresses.filter { date.timeIntervalSince($0) < 60 }.count / 5
    }

    // MARK: Writing

    /// Writes the counts not yet written, holding back a layout's last ones while they are fewer than ``minimumWrite``
    /// presses. Called every minute, when recording is turned off, and at quit.
    public func flush() async {
        let date = now()
        if HeatmapHour.start(of: date) != hour { hour = HeatmapHour.start(of: date) }
        await serially {
            self.inFlight = [:]
            for (id, hours) in self.pending {
                let (ready, held) = Self.split(hours, minimum: self.minimumWrite)
                if !ready.isEmpty { self.inFlight[id] = ready }
                self.pending[id] = held.map { [$0.start: $0] }
                // Hours carried into later ones may now fall in a window's range: it adds them again.
                if hours.count != ready.count + (held == nil ? 0 : 1) { self.changes += 1 }
            }
            var failures = 0
            // An hour at a time, each saved whole or not at all, so a failure keeps only what wasn't saved.
            for (id, hours) in self.inFlight {
                for hour in hours.values.sorted(by: { $0.start < $1.start }) {
                    failures += await self.write(hour, to: id) ? 0 : 1
                }
            }
            if failures == 0 { self.succeed(.write) }
            self.written.removeFirst(max(self.written.count - Self.keptWrites, 0))
        }
        if prunedDay != calendar.startOfDay(for: date) { await prune() }
    }

    /// A layout's unwritten hours, oldest first, split into those to write now and those held back: an hour with fewer
    /// than `minimum` presses is carried into the next one, and what is still short of it at the end waits, under the
    /// last hour. So every hour a write adds to has at least `minimum` presses added.
    static func split(_ hours: [Date: HeatmapHour], minimum: Int) -> (ready: [Date: HeatmapHour], held: HeatmapHour?) {
        var ready: [Date: HeatmapHour] = [:]
        var carried: HeatmapHour?
        for var hour in hours.values.sorted(by: { $0.start < $1.start }) {
            if let carried { hour.add(carried) }
            if hour.total >= minimum, !hour.isEmpty {
                ready[hour.start] = hour
                carried = nil
            } else {
                carried = hour
            }
        }
        return (ready, carried)
    }

    /// Adds an hour to the store, then moves it from ``inFlight`` to ``written``, or back to ``pending`` (with whatever
    /// was counted meanwhile) when that failed. No suspension between, so windows never miss it.
    private func write(_ hour: HeatmapHour, to id: UUID) async -> Bool {
        defer { inFlight[id]?[hour.start] = nil }
        do throws(HeatmapStoreError) {
            try await store.add(hour, to: id)
        } catch {
            fail(.write, error)
            pending[id, default: [:]][hour.start, default: HeatmapHour(start: hour.start)].add(hour)
            return false
        }
        version += 1
        written.append((version, id, [hour]))
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
                self.succeed(.clear)
            } catch {
                self.fail(.clear, error)
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
                self.succeed(.prune)
            } catch {
                self.fail(.prune, error)
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
            changes += 1
            recentPresses = recentPresses.filter { date.timeIntervalSince($0) < 60 } + [date]
            if calendar.startOfDay(for: date) != todayStart { loadToday() } else { today = HeatmapHour.sum(today ?? 0, 1) }
        case let .layer(layer):
            // A pairing reports the layer it finds the keyboard on, which isn't a move.
            defer { lastLayer = layer }
            guard let last = lastLayer, last != layer, let layerID = running.layout.layers[safe: layer]?.id else { return }
            pending[id, default: [:]][hour, default: HeatmapHour(start: hour)].layerEntries[layerID, default: 0] += 1
            changes += 1
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
            var heatmap = snapshot.heatmap
            for hour in unwritten(of: id, from: start, after: snapshot.version) { heatmap.add(hour) }
            today = heatmap.total()
        }
    }

    /// Recording's status changed: reads today's count for a layout it now records, and forgets the last layer outside
    /// recording, since the next one reported may have been reached meanwhile (secure input, Live View off and on).
    private func follow(_ status: Status?) {
        guard case let .recording(id)? = status else {
            lastLayer = nil
            return
        }
        guard id != todayLayout || todayStart != calendar.startOfDay(for: now()) else { return }
        if id != todayLayout { lastLayer = nil }
        todayLayout = id
        loadToday()
    }

    private enum Operation { case read, write, prune, clear }

    private func fail(_ operation: Operation, _ error: HeatmapStoreError) {
        Self.log.error("Heatmap store: \(String(describing: error), privacy: .public)")
        failing.insert(operation)
        lastError = error
    }

    private func succeed(_ operation: Operation) {
        guard failing.remove(operation) != nil, failing.isEmpty else { return }
        lastError = nil
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
