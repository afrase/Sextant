import AsyncAlgorithms
import Foundation
import Observation
import SextantDomain

/// The keyboard as it is right now (spec §8.2): which device is plugged in, what its firmware reports, the
/// active layer, the keys held down, and Follow mode.
///
/// Presence comes from a ``DeviceWatcher``; a keyboard in normal mode also gets a ``KeyboardLink`` session,
/// reopened with backoff when it ends. Live events are folded into state and published at most 60 times a
/// second. They stay in memory and are never logged.
@MainActor
@Observable
public final class LiveSession {
    public enum Connection: Hashable, Sendable {
        case noKeyboard
        case connected(KeyboardDevice)
        case bootloader(BootloaderDevice)
        /// Another app (Keymapp) holds the live interface; Sextant keeps retrying.
        case heldByAnotherApp(KeyboardDevice)
        /// Live access is off (ADR 0012); presence and the USB serial still work.
        case hardwareAccessOff(KeyboardDevice)
    }

    public private(set) var connection = Connection.noKeyboard
    /// The keyboard's serial (``FirmwareIdentity``): its USB serial, or what the live link reports.
    public private(set) var firmwareSerial: String?
    public private(set) var protocolVersion: UInt8?
    /// The keyboard's highest active layer.
    public private(set) var activeLayer: Int?
    /// Follow mode: the displayed layer tracks ``activeLayer``. On when a keyboard connects; off when a
    /// layer is chosen by hand (``stopFollowing()``); ``follow()`` resumes it.
    public private(set) var isFollowing = false
    /// macOS secure input is on (a password field has focus): presses are hidden.
    public private(set) var isSecureInputOn = false
    private var pressed: Set<Int> = []

    /// Indices of the keys held down; empty while secure input is on.
    public var pressedKeys: Set<Int> { isSecureInputOn ? [] : pressed }
    /// The layer to display, while following.
    public var followedLayer: Int? { isFollowing ? activeLayer : nil }

    @ObservationIgnored private let watcher: any DeviceWatcher
    @ObservationIgnored private let link: any KeyboardLink
    @ObservationIgnored private let board: BoardDefinition
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let secureInputProbe: @Sendable () -> Bool
    @ObservationIgnored private var devices: [ConnectedDevice] = []
    @ObservationIgnored private var keyboard: KeyboardDevice?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var linkTask: Task<Void, Never>?
    @ObservationIgnored private var secureInputTask: Task<Void, Never>?

    /// - Parameter secureInputProbe: `IsSecureEventInputEnabled`, polled once a second while a keyboard is connected.
    public init(
        watcher: any DeviceWatcher, link: any KeyboardLink, board: BoardDefinition = .voyager,
        clock: any Clock<Duration> = ContinuousClock(), secureInputProbe: @escaping @Sendable () -> Bool
    ) {
        self.watcher = watcher
        self.link = link
        self.board = board
        self.clock = clock
        self.secureInputProbe = secureInputProbe
    }

    /// Starts watching for the keyboard. Runs until ``stop()``.
    public func start() {
        guard tasks.isEmpty else { return }
        tasks = [
            Task {
                for await event in watcher.events(for: board) {
                    // A stopped stream still hands over events it already holds: one must not reconnect after stop().
                    guard !Task.isCancelled else { break }
                    handle(event)
                }
            }
        ]
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        devices = []
        disconnect()
        connection = .noKeyboard
    }

    public func follow() { isFollowing = true }

    public func stopFollowing() { isFollowing = false }

    /// How the keyboard's firmware relates to a layout; nil when no keyboard reports a serial.
    /// - Parameter importedLayout: see ``FirmwareIdentity/importedLayout(of:revisions:library:)``.
    public func match(_ layout: KeyboardLayout, libraryID: UUID, importedLayout: KeyboardLayout?) -> FirmwareMatch? {
        firmwareSerial.map {
            FirmwareMatch(
                serial: $0, expected: FirmwareIdentity(layout: layout, libraryID: libraryID, importedLayout: importedLayout),
                libraryID: libraryID, oryxLayoutID: layout.oryx?.layoutId)
        }
    }

    // MARK: Devices

    private func handle(_ event: DeviceEvent) {
        switch event {
        case let .attached(device):
            devices.removeAll { $0.id == device.id }
            devices.append(device)
        case let .detached(id):
            devices.removeAll { $0.id == id }
        }
        let keyboards = devices.compactMap { if case let .keyboard(k) = $0 { k } else { nil } }
        if let first = keyboards.first {
            if first != keyboard { connect(first) }
            return
        }
        disconnect()
        let bootloader = devices.lazy.compactMap { if case let .bootloader(b) = $0 { b } else { nil } }.first
        connection = bootloader.map { .bootloader($0) } ?? .noKeyboard
    }

    private func connect(_ device: KeyboardDevice) {
        disconnect()
        keyboard = device
        connection = .connected(device)
        firmwareSerial = device.serial
        isFollowing = true
        linkTask = Task { await runLink(device) }
        // Only presses need hiding, so the probe runs only while a keyboard can send them.
        secureInputTask = Task {
            while !Task.isCancelled {
                let on = secureInputProbe()
                if on != isSecureInputOn { isSecureInputOn = on }
                try? await clock.sleep(for: .seconds(1))
            }
        }
    }

    private func disconnect() {
        linkTask?.cancel()
        linkTask = nil
        secureInputTask?.cancel()
        secureInputTask = nil
        isSecureInputOn = false
        keyboard = nil
        firmwareSerial = nil
        protocolVersion = nil
        activeLayer = nil
        pressed = []
    }

    // MARK: Live link

    /// Runs link sessions for a keyboard until it goes away, reopening them with backoff (1 s doubling to 30 s;
    /// a session that reached live mode resets it). Stops for good when hardware access is off.
    private func runLink(_ device: KeyboardDevice) async {
        var delay = Duration.seconds(1)
        while !Task.isCancelled {
            let events = link.session(with: device, board: board)
            let final = await clock.publish(events, board: board) { show($0, from: device) }
            guard !Task.isCancelled else { return }
            pressed = []
            switch final.endReason {
            case .hardwareAccessOff:
                connection = .hardwareAccessOff(device)
                return
            case .heldByAnotherApp:
                connection = .heldByAnotherApp(device)
            default: break
            }
            if final.isLive { delay = .seconds(1) }
            try? await clock.sleep(for: delay)
            delay = min(delay * 2, .seconds(30))
        }
    }

    private func show(_ state: LinkState, from device: KeyboardDevice) {
        guard keyboard == device else { return }  // an update still in flight when the keyboard went away
        if state.isLive, connection != .connected(device) { connection = .connected(device) }
        if let serial = state.serial, serial != firmwareSerial { firmwareSerial = serial }
        if state.protocolVersion != protocolVersion { protocolVersion = state.protocolVersion }
        if state.layer != activeLayer { activeLayer = state.layer }
        if state.pressed != pressed { pressed = state.pressed }
    }
}

extension Clock where Duration == Swift.Duration {
    /// Folds a link session's events into state and calls `body` with it debounced by 1/60 s on this clock: a
    /// burst collapses into one update, updates come at most 60 times a second, and nothing runs while the
    /// keyboard is idle. Returns the final state. A method so it can be called on an `any Clock` (passing one
    /// to a generic parameter doesn't compile in this module).
    /// shortcut: during a burst with gaps under 1/60 s the update waits for the pause; move to a leading-and-trailing
    /// throttle if that lag ever shows.
    fileprivate func publish(
        _ events: AsyncStream<LiveEvent>, board: BoardDefinition, to body: @MainActor (LinkState) -> Void
    ) async -> LinkState {
        var last = LinkState()
        let states = events.reductions(into: LinkState()) { state, event in state.apply(event, board: board) }
        for await state in states.debounce(for: .seconds(1) / 60, clock: self) {
            last = state
            await body(state)
        }
        return last
    }
}

/// What one link session has reported so far.
private struct LinkState: Sendable {
    var serial: String?
    var protocolVersion: UInt8?
    var layer: Int?
    var pressed: Set<Int> = []
    /// The session reached live mode (layer or key events). Old firmware reports its version and then ends.
    var isLive = false
    var endReason: DeviceError?

    mutating func apply(_ event: LiveEvent, board: BoardDefinition) {
        if case let .ended(reason) = event {
            endReason = reason
            return
        }
        switch event {
        case let .firmwareSerial(s): serial = s
        case let .protocolVersion(v): protocolVersion = v
        case let .layer(l):
            layer = l
            isLive = true
        case let .keyDown(row, column):
            if let i = board.keyIndex(matrixRow: row, column: column) { pressed.insert(i) }
            isLive = true
        case let .keyUp(row, column):
            if let i = board.keyIndex(matrixRow: row, column: column) { pressed.remove(i) }
            isLive = true
        case .ended: break
        }
    }
}
