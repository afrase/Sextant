import Foundation
import Observation
import SextantDomain
import os

/// App Layers (spec §8.6, ADR 0054): moves the keyboard's layer when the frontmost app changes, by the rules of the layout
/// the keyboard runs as it was flashed. App-wide.
///
/// It sends only through Move Keyboard to Layer (`04 01 n`, never `04 00 n`), so only over a paired Live View session,
/// only to a layer of the flashed layout, and only while that layout's switch is on with a rule enabled: the user's
/// consent to a write without a click each time. It acts on app switches alone, never at launch, when Live View starts or
/// when a rule changes. Nothing is queued while it can't send. The switches it made are kept in memory, app names only.
/// Sextant coming forward isn't a switch, and neither is going back from it to the app it came from: looking at its rules,
/// opening its menu bar panel or moving the keyboard from it leaves the keyboard alone.
@MainActor
@Observable
public final class AppLayerSwitcher {
    /// One move App Layers made.
    public struct Switch: Identifiable, Hashable, Sendable {
        public let id: Int
        /// The library layout whose rule made the move: the one the keyboard ran.
        public let layoutID: UUID
        /// The app that came forward.
        public let app: String
        /// The app left behind, when its Return to Main rule made the move.
        public let left: String?
        public let layerName: String
        public let date: Date
    }

    /// The frontmost app's rule, as it holds now.
    public struct Applied: Hashable, Sendable {
        public let app: String
        public let layerName: String
    }

    /// The switches kept, newest first.
    public static let historyLimit = 20
    /// How long an app stays frontmost before App Layers acts: a burst of activations (windows closing, a Space changing)
    /// moves the keyboard once, for the app that ends up in front.
    static let settle = Duration.milliseconds(150)

    /// The frontmost app, once it has settled.
    public private(set) var frontmost: MacApp?
    /// The switches made since launch, newest first; never stored.
    public private(set) var history: [Switch] = []

    /// The switches the layout's own rules made, newest first. Another layout's switches name that layout's layers, and were made while the keyboard ran it.
    public func history(for id: UUID) -> [Switch] { history.filter { $0.layoutID == id } }
    /// Each layout's last App Layers save that failed, until one for it lands.
    private var saveErrors: [UUID: LibraryError] = [:]
    private var rulesByLayout: [UUID: AppLayerRules] = [:]
    /// Layouts whose `app-layers.json` couldn't be read: editing their rules would overwrite it.
    private var unreadable: [UUID: LibraryError] = [:]

    @ObservationIgnored private let watcher: any FrontmostAppWatcher
    @ObservationIgnored private let onKeyboard: OnKeyboard
    @ObservationIgnored private let live: LiveSession
    @ObservationIgnored private let store: any LayoutLibrary
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let ownBundleID: String?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var loading: Set<UUID> = []
    @ObservationIgnored private var nextSwitchID = 0
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    /// - Parameter ownBundleID: Sextant's own bundle id; its activations are ignored.
    public init(
        watcher: any FrontmostAppWatcher, onKeyboard: OnKeyboard, live: LiveSession, store: any LayoutLibrary,
        ownBundleID: String? = nil, clock: any Clock<Duration> = ContinuousClock(), now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.watcher = watcher
        self.onKeyboard = onKeyboard
        self.live = live
        self.store = store
        self.clock = clock
        self.now = now
        self.ownBundleID = ownBundleID
    }

    /// Follows the frontmost app, and loads the rules of the layout the keyboard runs, for the app's lifetime.
    public func start() {
        guard tasks.isEmpty else { return }
        let (watcher, onKeyboard) = (watcher, onKeyboard)
        tasks = [
            Task { [weak self] in
                var isFirst = true
                for await app in watcher.activations() {
                    guard let self else { return }
                    let isOwn = app.bundleID == ownBundleID
                    // The app in front at launch only sets where switching starts from: nothing is sent at launch. Sextant
                    // there still uses up the launch app, so the first switch away from it acts.
                    if isFirst {
                        isFirst = false
                        if !isOwn { frontmost = app }
                    } else if isOwn {
                        // Not a switch, but it ends a burst: an app still settling never ended up in front.
                        cancelPending()
                    } else {
                        activated(app)
                    }
                }
            },
            Task { [weak self] in
                for await id in Observations({ onKeyboard.running?.entry.id }) {
                    guard let self else { return }
                    if let id { await load(id) }
                }
            },
        ]
    }

    // MARK: Rules

    /// The layout's rules as last loaded or set; empty until ``load(_:)`` has read them.
    public func rules(for id: UUID) -> AppLayerRules { rulesByLayout[id] ?? AppLayerRules() }

    /// Why the layout's rules can't be read or changed; nil when they can.
    public func loadError(for id: UUID) -> LibraryError? { unreadable[id] }

    /// Reads the layout's rules once.
    public func load(_ id: UUID) async {
        guard rulesByLayout[id] == nil, !loading.contains(id) else { return }
        loading.insert(id)
        defer { loading.remove(id) }
        do {
            let rules = try await store.appLayerRules(of: id)
            if rulesByLayout[id] == nil { rulesByLayout[id] = rules }
            unreadable[id] = nil
        } catch {
            unreadable[id] = error
            Self.log.error("App Layers unreadable: \(String(describing: error), privacy: .public)")
        }
    }

    /// Replaces the layout's rules and saves them, in order. A change sends nothing by itself: the next app switch acts on
    /// it. Only once ``load(_:)`` has read them, so a change made from the empty set shown before can't replace the file.
    /// A save that fails keeps the change for this run and shows in ``saveError(for:)``: until one lands, the file still
    /// holds the rules from before, which the next launch reads.
    public func setRules(_ rules: AppLayerRules, for id: UUID) {
        guard unreadable[id] == nil, let current = rulesByLayout[id], rules != current else { return }
        rulesByLayout[id] = rules
        save(id)
    }

    /// Why the layout's last rule change isn't saved; nil once a save lands.
    public func saveError(for id: UUID) -> LibraryError? { saveErrors[id] }

    /// Saves the layout's rules as they are now again, after a failed save.
    public func retrySave(for id: UUID) {
        guard saveErrors[id] != nil else { return }
        save(id)
    }

    private func save(_ id: UUID) {
        guard let rules = rulesByLayout[id] else { return }
        let (store, previous) = (store, saving)
        saving = Task { [weak self] in
            await previous?.value
            do throws(LibraryError) {
                try await store.saveAppLayerRules(rules, for: id)
                self?.saveErrors[id] = nil
            } catch {
                self?.saveErrors[id] = error
                Self.log.error("App Layers not saved: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: State

    /// Whether the layout's rules can move the keyboard now, and why not.
    public func state(for id: UUID) -> AppLayersState {
        guard rules(for: id).isActive else { return .off }
        // The same refusals as every other layer move (ADR 0048), so the two can't drift apart.
        do throws(LayerMoveRefusal) {
            try onKeyboard.moveKeyboard(toLayer: 0, dryRun: true)
        } catch {
            return .paused(.refused(error))
        }
        guard let running = onKeyboard.running else { return .paused(.refused(.unknownLayout)) }
        guard running.entry.id == id else {
            return .paused(.otherLayout(running.entry.title, hasRules: rules(for: running.entry.id).isActive))
        }
        return .on
    }

    /// The frontmost app's own rule while the keyboard is on its layer: "Xcode is frontmost → keyboard on Sym+Num".
    public func applied(for id: UUID) -> Applied? {
        guard state(for: id) == .on, let app = frontmost, let layout = onKeyboard.running?.layout,
            let layer = rules(for: id).target(activated: app.bundleID, previous: nil, in: layout), live.activeLayer == layer
        else { return nil }
        return Applied(app: app.name, layerName: layout.layers[layer].title)
    }

    // MARK: Apps

    /// The running apps for Add App…, as they launch and quit, without Sextant: its own rule would never apply.
    public func runningApps() -> AsyncStream<[MacApp]> {
        let (own, updates) = (ownBundleID, watcher.runningApps())
        return AsyncStream { continuation in
            let task = Task {
                for await apps in updates { continuation.yield(apps.filter { $0.bundleID != own }) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func app(at url: URL) async -> MacApp? { await watcher.app(at: url).flatMap { $0.bundleID == ownBundleID ? nil : $0 } }

    // MARK: Switching

    /// Only the last of a burst of activations is acted on, once it has stayed in front for ``settle``. Coming back to the
    /// app that last settled (from Sextant, or at the end of a burst) isn't a switch and sends nothing, so a layer chosen
    /// in Sextant meanwhile, or a rule changed there, holds until the user really changes apps.
    private func activated(_ app: MacApp) {
        cancelPending()
        guard app != frontmost else { return }
        let clock = clock
        pending = Task { [weak self] in
            do { try await clock.sleep(for: Self.settle) } catch { return }
            guard let self else { return }
            await keysUp()
            guard !Task.isCancelled else { return }
            let previous = frontmost
            frontmost = app
            move(for: app, leaving: previous)
        }
    }

    /// Drops the move of an app that hasn't settled, or is waiting for the keys to come up.
    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    /// Waits until no key is held. A move under a held layer key turns its layer off (layer_move), so the key's release
    /// would drop the keyboard to the base layer, whatever the rule says; a move under a held modifier would change what
    /// the chord types.
    private func keysUp() async {
        let live = live
        guard !live.pressedKeys.isEmpty else { return }
        for await isUp in Observations({ live.pressedKeys.isEmpty }) where isUp { return }
    }

    /// Sends even when the keyboard reports the layer already: that report is the highest active layer, so it can be a
    /// held layer key's or one the firmware failed to update (research note O2), and a move is harmless when it is there.
    private func move(for app: MacApp, leaving previous: MacApp?) {
        guard let running = onKeyboard.running, state(for: running.entry.id) == .on,
            let layer = rules(for: running.entry.id).target(activated: app.bundleID, previous: previous?.bundleID, in: running.layout)
        else { return }
        do {
            try onKeyboard.moveKeyboard(toLayer: layer)
        } catch {
            // Paused since the check (a reconnect, say): the next switch tries again.
            return
        }
        let byOwnRule = rules(for: running.entry.id).target(activated: app.bundleID, previous: nil, in: running.layout) == layer
        nextSwitchID += 1
        let entry = Switch(
            id: nextSwitchID, layoutID: running.entry.id, app: app.name, left: byOwnRule ? nil : previous?.name,
            layerName: running.layout.layers[layer].title, date: now())
        history = Array(([entry] + history).prefix(Self.historyLimit))
    }
}

/// Whether a layout's App Layers can move the keyboard now (ADR 0054).
public enum AppLayersState: Hashable, Sendable {
    /// The switch is off, or no rule is enabled: nothing is sent.
    case off
    /// On, but nothing is sent until this clears; app switches meanwhile aren't replayed.
    case paused(AppLayersPause)
    /// The next app switch moves the keyboard when a rule says so.
    case on
}

/// Why App Layers sends nothing now.
public enum AppLayersPause: Hashable, Sendable {
    /// No layer move can be sent now (ADR 0048).
    case refused(LayerMoveRefusal)
    /// The keyboard runs another library layout, titled so; `hasRules` when that layout's own App Layers are on.
    case otherLayout(String, hasRules: Bool)

    public var text: String {
        switch self {
        case let .refused(refusal):
            switch refusal {
            case .noKeyboard: String(localized: "Paused: connect your keyboard.")
            case .flashMode: String(localized: "Paused: the keyboard is in flash mode.")
            case .liveOff: String(localized: "Paused: Live View is off. App Layers moves the keyboard only while Live View is on.")
            case .heldByAnotherApp: String(localized: "Paused: another app (Keymapp) is using the keyboard.")
            case .connecting: String(localized: "Paused: Live View is still connecting to the keyboard.")
            case .unknownLayout: String(localized: "Paused: the keyboard runs a layout that isn’t in your library.")
            case .noSuchLayer: String(localized: "Paused: \(refusal.localizedDescription)")
            }
        case let .otherLayout(title, true): String(localized: "Paused: the keyboard runs “\(title)”, whose own rules apply.")
        case let .otherLayout(title, false):
            String(localized: "Paused: the keyboard runs “\(title)”, which has no App Layers turned on.")
        }
    }
}
