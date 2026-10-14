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
@MainActor
@Observable
public final class AppLayerSwitcher {
    /// One move App Layers made.
    public struct Switch: Identifiable, Hashable, Sendable {
        public let id: Int
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
    /// The last App Layers save that failed; nil once one lands.
    public var saveError: LibraryError?
    private var rulesByLayout: [UUID: AppLayerRules] = [:]
    /// Layouts whose `app-layers.json` couldn't be read: editing their rules would overwrite it.
    private var unreadable: [UUID: LibraryError] = [:]

    @ObservationIgnored private let watcher: any FrontmostAppWatcher
    @ObservationIgnored private let onKeyboard: OnKeyboard
    @ObservationIgnored private let live: LiveSession
    @ObservationIgnored private let store: any LayoutLibrary
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var loading: Set<UUID> = []
    @ObservationIgnored private var nextSwitchID = 0
    private static let log = Logger(subsystem: "com.sextant.app", category: "application")

    public init(
        watcher: any FrontmostAppWatcher, onKeyboard: OnKeyboard, live: LiveSession, store: any LayoutLibrary,
        clock: any Clock<Duration> = ContinuousClock(), now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.watcher = watcher
        self.onKeyboard = onKeyboard
        self.live = live
        self.store = store
        self.clock = clock
        self.now = now
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
                    // The app in front at launch only sets where switching starts from: nothing is sent at launch.
                    if isFirst {
                        isFirst = false
                        frontmost = app
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
    public func setRules(_ rules: AppLayerRules, for id: UUID) {
        guard unreadable[id] == nil, let current = rulesByLayout[id], rules != current else { return }
        rulesByLayout[id] = rules
        let (store, previous) = (store, saving)
        saving = Task { [weak self] in
            await previous?.value
            do throws(LibraryError) {
                try await store.saveAppLayerRules(rules, for: id)
                self?.saveError = nil
            } catch {
                self?.saveError = error
                Self.log.error("App Layers not saved: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: State

    /// Whether the layout's rules can move the keyboard now, and why not.
    public func state(for id: UUID) -> AppLayersState {
        guard rules(for: id).isActive else { return .off }
        switch live.connection {
        case .noKeyboard: return .paused(.noKeyboard)
        case .bootloader: return .paused(.flashMode)
        case .liveOff: return .paused(.liveOff)
        case .heldByAnotherApp: return .paused(.heldByAnotherApp)
        case .connected: if !live.canSend { return .paused(.connecting) }
        }
        guard let running = onKeyboard.running else { return .paused(.unknownLayout) }
        guard running.entry.id == id else { return .paused(.otherLayout(running.entry.title)) }
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

    public func runningApps() async -> [MacApp] { await watcher.runningApps() }

    public func app(at url: URL) async -> MacApp? { await watcher.app(at: url) }

    // MARK: Switching

    /// Only the last of a burst of activations is acted on, once it has stayed in front for ``settle``.
    private func activated(_ app: MacApp) {
        pending?.cancel()
        let clock = clock
        pending = Task { [weak self] in
            do { try await clock.sleep(for: Self.settle) } catch { return }
            guard let self else { return }
            let previous = frontmost
            frontmost = app
            move(for: app, leaving: previous)
        }
    }

    private func move(for app: MacApp, leaving previous: MacApp?) {
        guard let running = onKeyboard.running, state(for: running.entry.id) == .on,
            let layer = rules(for: running.entry.id).target(activated: app.bundleID, previous: previous?.bundleID, in: running.layout),
            live.activeLayer != layer
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
            id: nextSwitchID, app: app.name, left: byOwnRule ? nil : previous?.name,
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
    case noKeyboard
    case flashMode
    /// Live View is off (ADR 0057).
    case liveOff
    case heldByAnotherApp
    /// Live View hasn't paired with the keyboard yet.
    case connecting
    /// The keyboard runs a layout Sextant doesn't have.
    case unknownLayout
    /// The keyboard runs another library layout, titled so: its own rules apply.
    case otherLayout(String)

    public var text: String {
        switch self {
        case .noKeyboard: String(localized: "Paused: connect your keyboard.")
        case .flashMode: String(localized: "Paused: the keyboard is in flash mode.")
        case .liveOff: String(localized: "Paused: Live View is off. App Layers moves the keyboard only while Live View is on.")
        case .heldByAnotherApp: String(localized: "Paused: another app (Keymapp) is using the keyboard.")
        case .connecting: String(localized: "Paused: Live View is still connecting to the keyboard.")
        case .unknownLayout: String(localized: "Paused: the keyboard runs a layout that isn’t in your library.")
        case let .otherLayout(title): String(localized: "Paused: the keyboard runs “\(title)”, whose own rules apply.")
        }
    }
}
