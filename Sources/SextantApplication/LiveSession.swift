import AsyncAlgorithms
import Foundation
import Observation
import SextantDomain

/// The keyboard as it is right now (spec §8.2): which device is plugged in, what its firmware reports, the
/// active layer, the keys held down, and Follow mode.
///
/// Presence comes from a ``DeviceWatcher``; a keyboard in normal mode also gets a ``KeyboardLink`` session,
/// reopened with backoff when it ends. Live events are folded into state and published at most 60 times a
/// second; ``activity()`` streams each press, release and layer change as it happens. They stay in memory and are never
/// logged. ``send(_:)`` writes a command over the paired session (ADR 0038).
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
    /// Follow mode: the displayed layer tracks ``activeLayer``. On when a keyboard connects, unless the user turned
    /// that off (`followsOnConnect`); off when a layer is chosen by hand (``stopFollowing()``); ``follow()`` resumes it.
    public private(set) var isFollowing = false
    /// macOS secure input is on (a password field has focus): presses are hidden.
    public private(set) var isSecureInputOn = false
    /// The library layout whose Build & Flash is waiting for flash mode or flashing (spec §7.6). One at a time,
    /// app-wide: two would race to write different layouts to the same bootloader.
    public private(set) var flashingLayoutID: UUID?
    /// The Build & Flash run holding flash mode: a reopened window's run for the same layout is another one.
    public private(set) var flashingOwner: ObjectIdentifier?
    /// A Build & Flash is validating, erasing or writing the keyboard, which can't be interrupted: quitting waits.
    public internal(set) var isWritingFirmware = false
    private var pressed: Set<Int> = []
    /// The command feed of the link session that is paired now; nil otherwise.
    private var liveCommands: AsyncStream<KeyboardCommand>.Continuation?

    /// Indices of the keys held down; empty while secure input is on.
    public var pressedKeys: Set<Int> { isSecureInputOn ? [] : pressed }
    /// The layer to display, while following.
    public var followedLayer: Int? { isFollowing ? activeLayer : nil }
    /// A paired session is open, so ``send(_:)`` can write.
    public var canSend: Bool { liveCommands != nil }

    @ObservationIgnored private let watcher: any DeviceWatcher
    @ObservationIgnored private let link: any KeyboardLink
    @ObservationIgnored private let board: BoardDefinition
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let secureInputProbe: @Sendable () -> Bool
    @ObservationIgnored private let followsOnConnect: @MainActor () -> Bool
    @ObservationIgnored private var devices: [ConnectedDevice] = []
    @ObservationIgnored private var keyboard: KeyboardDevice?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var linkTask: Task<Void, Never>?
    @ObservationIgnored private var secureInputTask: Task<Void, Never>?
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<LiveActivity>.Continuation] = [:]
    /// The layer ``activity()`` last reported for this keyboard.
    @ObservationIgnored private var deliveredLayer: Int?

    /// - Parameters:
    ///   - followsOnConnect: whether Follow turns on when a keyboard connects (Settings › Keyboard), asked at each connect.
    ///   - secureInputProbe: `IsSecureEventInputEnabled`, polled once a second while a keyboard is connected and asked
    ///     again for each event ``activity()`` would deliver.
    public init(
        watcher: any DeviceWatcher, link: any KeyboardLink, board: BoardDefinition = .voyager,
        clock: any Clock<Duration> = ContinuousClock(), followsOnConnect: @escaping @MainActor () -> Bool = { true },
        secureInputProbe: @escaping @Sendable () -> Bool
    ) {
        self.watcher = watcher
        self.link = link
        self.board = board
        self.clock = clock
        self.followsOnConnect = followsOnConnect
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

    /// Claims flash mode for one Build & Flash (`owner`) of a layout; false while another one holds it.
    public func claimFlashMode(for layoutID: UUID, owner: AnyObject) -> Bool {
        guard flashingOwner == nil || flashingOwner == ObjectIdentifier(owner) else { return false }
        (flashingLayoutID, flashingOwner) = (layoutID, ObjectIdentifier(owner))
        return true
    }

    /// Lets go of flash mode, unless another run holds it now.
    public func releaseFlashMode(owner: AnyObject) {
        guard flashingOwner == ObjectIdentifier(owner) else { return }
        (flashingLayoutID, flashingOwner) = (nil, nil)
    }

    /// How the keyboard's firmware relates to a layout; nil when no keyboard reports a serial.
    /// - Parameter importedLayout: see ``FirmwareIdentity/importedLayout(of:revisions:library:)``.
    public func match(_ layout: KeyboardLayout, libraryID: UUID, importedLayout: KeyboardLayout?) -> FirmwareMatch? {
        firmwareSerial.map {
            FirmwareMatch(
                serial: $0, expected: FirmwareIdentity(layout: layout, libraryID: libraryID, importedLayout: importedLayout),
                libraryID: libraryID, oryxLayoutID: layout.oryx?.layoutId)
        }
    }

    /// Queues a command for the paired session, which writes it in order (ADR 0038). Callers send only on a user
    /// gesture or an enabled rule, never at launch. A failed write ends the session, which shows in ``connection``.
    public func send(_ command: KeyboardCommand) throws(DeviceError) {
        switch connection {
        case .noKeyboard: throw .notFound
        case .bootloader: throw .notLive
        case .hardwareAccessOff: throw .hardwareAccessOff
        case .heldByAnotherApp: throw .heldByAnotherApp
        case .connected: break
        }
        guard let liveCommands else { throw .notLive }
        guard command.isAllowed(on: board) else { throw .outOfRange }
        liveCommands.yield(command)
    }

    /// Everything the keyboard reports from now on, as it reports it: before the 60 Hz coalescing, so a tap shorter
    /// than a frame still arrives. Nothing arrives while secure input is on. Ends when the consumer stops.
    public func activity() -> AsyncStream<LiveActivity> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveActivity.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.subscribers[id] = nil } }
        return stream
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
        isFollowing = followsOnConnect()
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
        liveCommands?.finish()
        liveCommands = nil
        secureInputTask?.cancel()
        secureInputTask = nil
        isSecureInputOn = false
        keyboard = nil
        deliveredLayer = nil
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
            // Each session gets its own command feed, so a command never reaches a later session.
            let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
            let (activity, tap) = AsyncStream.makeStream(of: LiveActivity.self)
            async let delivered: Void = deliver(activity, from: device)
            let events = link.session(with: device, board: board, commands: commands)
            let final = await clock.publish(events, board: board, tap: tap, secureInput: secureInputProbe) { state in
                show(state, from: device)
                // The debounce flushes the last state after the session ends; an ended session takes no commands.
                if state.isLive, !state.hasEnded, liveCommands == nil, !Task.isCancelled, keyboard == device {
                    liveCommands = feed
                }
            }
            feed.finish()
            tap.finish()
            // A cancelled run leaves the state alone: disconnect() has reset it, and a new run may own it now.
            if !Task.isCancelled { liveCommands = nil }
            await delivered
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

    /// Hands one session's activity to every ``activity()`` stream, except during secure input: asked per event,
    /// because the once-a-second poll would let the first keys typed into a password field through.
    private func deliver(_ activity: AsyncStream<LiveActivity>, from device: KeyboardDevice) async {
        for await event in activity where keyboard == device && !secureInputProbe() {
            // Every pairing reports the layer again (each reconnect, and the resync after a layer move).
            if case let .layer(layer) = event {
                guard layer != deliveredLayer else { continue }
                deliveredLayer = layer
            }
            subscribers.values.forEach { $0.yield(event) }
        }
    }
}

/// One thing the keyboard just did, from ``LiveSession/activity()``.
public enum LiveActivity: Hashable, Sendable {
    /// A key went down (by key index) while `layer` was the highest active one.
    case keyDown(index: Int, layer: Int)
    case keyUp(index: Int)
    /// The highest active layer changed, or was first reported for this keyboard.
    case layer(Int)
    /// A host holds the board's lights (true) or gave them back (false): the reply to ``KeyboardCommand/lighting(_:)``,
    /// whichever host sent it.
    case lighting(Bool)
    /// The firmware refused a command, with its Oryx error code (`0x04`: the build has no RGB matrix).
    case refused(UInt8)
}

extension Clock where Duration == Swift.Duration {
    /// Folds a link session's events into state and calls `body` with it debounced by 1/60 s on this clock: a
    /// burst collapses into one update, updates come at most 60 times a second, and nothing runs while the
    /// keyboard is idle. `tap` gets each event's ``LiveActivity`` as it is folded in, undebounced. Returns the final
    /// state. A method so it can be called on an `any Clock` (passing one to a generic parameter doesn't compile in
    /// this module).
    /// shortcut: during a burst with gaps under 1/60 s the update waits for the pause; move to a leading-and-trailing
    /// throttle if that lag ever shows.
    fileprivate func publish(
        _ events: AsyncStream<LiveEvent>, board: BoardDefinition, tap: AsyncStream<LiveActivity>.Continuation,
        secureInput: @escaping @Sendable () -> Bool, to body: @MainActor (LinkState) -> Void
    ) async -> LinkState {
        var last = LinkState()
        let states = events.reductions(into: LinkState()) { state, event in
            // Asked as the event arrives, so a press made during secure input never waits for the main actor.
            if let activity = state.apply(event, board: board), !secureInput() { tap.yield(activity) }
        }
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
    /// `.ended` arrived; `endReason` is nil when the device just went away.
    var hasEnded = false
    var endReason: DeviceError?

    /// Folds in one event; returns it as activity unless it identifies the keyboard or ends the session.
    mutating func apply(_ event: LiveEvent, board: BoardDefinition) -> LiveActivity? {
        switch event {
        case let .ended(reason): (hasEnded, endReason) = (true, reason)
        case let .firmwareSerial(s): serial = s
        case let .protocolVersion(v): protocolVersion = v
        case let .layer(l):
            layer = l
            isLive = true
            return .layer(l)
        case let .keyDown(row, column):
            isLive = true
            guard let i = board.keyIndex(matrixRow: row, column: column) else { break }
            pressed.insert(i)
            // Left out before the session's first layer report: events flow during the handshake only when another
            // host paired the board earlier, and then there is no layer to tag the press with yet.
            return layer.map { .keyDown(index: i, layer: $0) }
        case let .keyUp(row, column):
            isLive = true
            guard let i = board.keyIndex(matrixRow: row, column: column) else { break }
            pressed.remove(i)
            return .keyUp(index: i)
        case let .lighting(on): return .lighting(on)
        case let .error(code): return .refused(code)
        }
        return nil
    }
}
