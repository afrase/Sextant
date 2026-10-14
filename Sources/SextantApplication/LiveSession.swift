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
/// logged. ``send(_:)`` writes a command over the paired session (ADR 0038). A session that took the keyboard's lights
/// gives them back before Live View ends it (ADR 0051).
@MainActor
@Observable
public final class LiveSession {
    public enum Connection: Hashable, Sendable {
        case noKeyboard
        case connected(KeyboardDevice)
        case bootloader(BootloaderDevice)
        /// Another app (Keymapp) holds the live interface; Sextant keeps retrying.
        case heldByAnotherApp(KeyboardDevice)
        /// The keyboard is plugged in but the live view isn't on (ADR 0057): nothing is written to it, and presence and
        /// the USB serial still work.
        case liveOff(KeyboardDevice)
    }

    public private(set) var connection = Connection.noKeyboard
    /// The user turned the live view on (``startLive()``). It pairs with the keyboard only then, never at launch or when
    /// a keyboard is plugged in, and lasts until ``stopLive()`` or quit, across replugs.
    public private(set) var isLive = false
    /// The keyboard's serial (``FirmwareIdentity``): its USB serial, or what the live link reports.
    public private(set) var firmwareSerial: String?
    public private(set) var protocolVersion: UInt8?
    /// The keyboard's highest active layer.
    public private(set) var activeLayer: Int?
    /// Follow mode: the displayed layer tracks ``activeLayer``. On when the live view starts, unless the user turned
    /// that off (`followsOnConnect`); off when a layer is chosen by hand (``stopFollowing()``); ``follow()`` resumes it.
    public private(set) var isFollowing = false
    /// macOS secure input is on (a password field has focus): presses are hidden.
    public private(set) var isSecureInputOn = false
    /// The library layout whose Build & Flash is waiting for flash mode or flashing (spec §7.6). One at a time,
    /// app-wide: two would race to write different layouts to the same bootloader.
    public private(set) var flashingLayoutID: UUID?
    /// The Build & Flash run holding flash mode: a reopened window's run for the same layout is another one.
    public private(set) var flashingOwner: ObjectIdentifier?
    /// A Build & Flash is validating, erasing or writing the keyboard, or verifying it to record what it flashed, none of
    /// which can be interrupted: quitting waits. Verifying ends within 10 s.
    public internal(set) var isWritingFirmware = false
    /// How far that write has come, 0–1 in 5% steps (erasing fills the first half, writing the second); nil while nothing
    /// is being written. The menu bar's arc fills with it (spec §8.3); the steps keep it from redrawing at every block.
    public internal(set) var flashProgress: Double?
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
    /// Live View took this keyboard's lights (`05 01`, `06`, `09`) and hasn't given them back (`05 00`). It outlasts a
    /// session that ends while the keyboard stays plugged in: the board may still show them, so the next one releases.
    @ObservationIgnored private var lightsTaken = false
    /// A release was asked for while no session was paired (the reconnect after a failed write, Live View turned off
    /// then): the next session to pair sends it.
    @ObservationIgnored private var releaseDue = false
    /// `05 00` writes the keyboard hasn't answered (`08 00`) yet.
    @ObservationIgnored private var releasesInFlight = 0
    /// When the link will likely have written every command queued, on `clock`.
    @ObservationIgnored private var writesDone: (any InstantProtocol<Duration>)?
    /// Live View was turned off while the session held the lights: it ends once the keyboard has them back.
    @ObservationIgnored private var stopping: Task<Void, Never>?

    /// One queued write: the link writes a report and then waits 5 ms (ADR 0022), but its sleeps overshoot and the write
    /// takes time too (about 7.5 ms a report measured on a Mac with a free transport). A sender that waits this out never
    /// falls behind the link.
    static let writeAllowance = Duration.milliseconds(12)
    /// How long the keyboard's `08 00` may take once the link has likely written the `05 00`.
    static let releaseReplyWait = Duration.milliseconds(500)

    /// - Parameters:
    ///   - followsOnConnect: whether Follow turns on when the live view starts (Settings › Keyboard), asked each time.
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

    /// Turns the live view on: pairs with the keyboard now, or when one is plugged in (ADR 0057).
    public func startLive() {
        guard !isLive else { return }
        isLive = true
        guard let keyboard else { return }
        // While the last session still gives the lights back, it pairs again once that is done, and reads as connecting.
        if stopping == nil { goLive(keyboard) } else { connection = .connected(keyboard) }
    }

    /// Turns the live view off: ends the link session and forgets its layer and presses; the keyboard stays connected.
    /// A session that took the keyboard's lights gives them back first (ADR 0051): it reads as off and takes no commands at
    /// once, and ends when the keyboard answers, since ending it drops whatever is still queued. Between two sessions they
    /// go back when Live View next pairs.
    public func stopLive() {
        guard isLive else { return }
        isLive = false
        guard let keyboard else { return }
        // Turned on and off again while the last session gives the lights back: it still ends once that is done.
        guard stopping == nil else { return connection = .liveOff(keyboard) }
        guard liveCommands != nil, lightsTaken || releasesInFlight > 0 else { return connect(keyboard) }
        let replies = activity()
        releaseLights()
        liveCommands = nil
        (connection, isFollowing, activeLayer, pressed) = (.liveOff(keyboard), false, nil, [])
        stopping = Task {
            await waitForReleases(replies)
            guard !Task.isCancelled else { return }
            stopping = nil
            connect(keyboard)
        }
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
        case .liveOff: throw .notLive
        case .heldByAnotherApp: throw .heldByAnotherApp
        case .connected: break
        }
        guard let liveCommands else { throw .notLive }
        guard command.isAllowed(on: board) else { throw .outOfRange }
        liveCommands.yield(command)
        switch command {
        case .moveToLayer: break
        case .lighting(true), .setLED, .setAllLEDs: (lightsTaken, releaseDue) = (true, false)
        case .lighting(false): (lightsTaken, releaseDue, releasesInFlight) = (false, false, releasesInFlight + 1)
        }
        // A layer move is written with the `01` after it (ADR 0038).
        let reports = if case .moveToLayer = command { 2 } else { 1 }
        writesDone = clock.instant(Self.writeAllowance * reports, afterNowOr: writesDone)
    }

    /// Waits until the link has likely written every command queued so far. A sender that can outpace it (the lighting
    /// preview) waits between batches, so at most one batch is ever queued.
    public func waitForQueuedWrites() async {
        let left = clock.time(until: writesDone)
        guard left > .zero else { return }
        try? await clock.sleep(for: left)
    }

    /// Gives the keyboard its own lighting back (`05 00`) if Live View took it. With no session paired it is sent when the
    /// next one pairs, unless the lights are taken again first.
    public func releaseLights() {
        guard lightsTaken else { return }
        do throws(DeviceError) { try send(.lighting(false)) } catch { releaseDue = true }
    }

    /// Gives the keyboard its lighting back and waits until it says so for every `05 00` queued, at most until the link has
    /// likely written them and half a second more, since `IOHIDDeviceSetReport` has no timeout. Quitting ends the process
    /// next, and anything still queued with it.
    public func releaseLightsAndWait() async {
        let replies = activity()  // before the write, so the reply can't come first
        releaseLights()
        await waitForReleases(replies)
    }

    private func waitForReleases(_ replies: AsyncStream<LiveActivity>) async {
        guard releasesInFlight > 0 else { return }
        let bound = clock.time(until: writesDone) + Self.releaseReplyWait
        let clock = clock
        await withTaskGroup { group in
            // ``deliver(_:from:)`` counts each reply before handing it on.
            group.addTask {
                for await event in replies where event == .lighting(false) || event == .refused(0x04) {
                    if await self.releasesInFlight == 0 { return }
                }
            }
            group.addTask { try? await clock.sleep(for: bound) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Everything the keyboard reports from now on, as it reports it: before the 60 Hz coalescing, so a tap shorter
    /// than a frame still arrives. No press, release or layer arrives while secure input is on; the keyboard's replies
    /// (``LiveActivity/lighting(_:)``, ``LiveActivity/refused(_:)``) always do. Every key-down gets its key-up: when
    /// secure input hides an event, or the session ends, a key-up arrives for each key still down, and after secure input
    /// the next layer report arrives even if it repeats the last one. Ends when the consumer stops.
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
        // The same keyboard, still plugged in, may still show the lights a session took (Live View turned off between
        // two sessions): the next session to pair gives them back.
        let taken = device == keyboard && lightsTaken
        disconnect()
        (lightsTaken, releaseDue) = (taken, taken)
        keyboard = device
        connection = .liveOff(device)
        firmwareSerial = device.serial
        if isLive { goLive(device) }
    }

    /// Opens the link: the first write to the keyboard, so only once the user turned the live view on.
    private func goLive(_ device: KeyboardDevice) {
        connection = .connected(device)
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
        stopping?.cancel()
        stopping = nil
        (lightsTaken, releaseDue, releasesInFlight, writesDone) = (false, false, 0, nil)
        linkTask?.cancel()
        linkTask = nil
        liveCommands?.finish()
        liveCommands = nil
        secureInputTask?.cancel()
        secureInputTask = nil
        isSecureInputOn = false
        keyboard = nil
        isFollowing = false
        deliveredLayer = nil
        firmwareSerial = nil
        protocolVersion = nil
        activeLayer = nil
        pressed = []
    }

    // MARK: Live link

    /// Runs link sessions for a keyboard until it goes away, reopening them with backoff (1 s doubling to 30 s;
    /// a session that reached live mode resets it). Stops when the live view is turned off.
    private func runLink(_ device: KeyboardDevice) async {
        var delay = Duration.seconds(1)
        while !Task.isCancelled {
            // Each session gets its own command feed, so a command never reaches a later session.
            let (commands, feed) = AsyncStream.makeStream(of: KeyboardCommand.self)
            let (activity, tap) = AsyncStream.makeStream(of: LiveActivity?.self)
            async let delivered: Void = deliver(activity, from: device)
            let events = link.session(with: device, board: board, commands: commands)
            let final = await clock.publish(events, board: board, tap: tap, secureInput: secureInputProbe) { state in
                show(state, from: device)
                // The debounce flushes the last state after the session ends; an ended session takes no commands.
                if state.isLive, !state.hasEnded, liveCommands == nil, !Task.isCancelled, keyboard == device, isPaired {
                    liveCommands = feed
                    if releaseDue { releaseLights() }
                }
            }
            feed.finish()
            tap.finish()
            // A cancelled run leaves the state alone: disconnect() has reset it, and a new run may own it now.
            if !Task.isCancelled { (liveCommands, releasesInFlight, writesDone) = (nil, 0, nil) }
            await delivered
            // Live View off while the lights went back: no new session; `stopping` ends this run.
            guard !Task.isCancelled, stopping == nil else { return }
            pressed = []
            if final.endReason == .heldByAnotherApp { connection = .heldByAnotherApp(device) }
            if final.isLive { delay = .seconds(1) }
            try? await clock.sleep(for: delay)
            delay = min(delay * 2, .seconds(30))
        }
    }

    private func show(_ state: LinkState, from device: KeyboardDevice) {
        guard keyboard == device, isPaired else { return }  // an update still in flight when the keyboard went away or live ended
        if state.isLive, connection != .connected(device) { connection = .connected(device) }
        if let serial = state.serial, serial != firmwareSerial { firmwareSerial = serial }
        if state.protocolVersion != protocolVersion { protocolVersion = state.protocolVersion }
        if state.layer != activeLayer { activeLayer = state.layer }
        if state.pressed != pressed { pressed = state.pressed }
    }

    /// Live View is on and its session isn't giving the lights back before it ends.
    private var isPaired: Bool { isLive && stopping == nil }

    /// Hands one session's activity to every ``activity()`` stream. Presses and layers stop while Live View is off and
    /// during secure input, asked per event because the once-a-second poll would let the first keys typed into a password
    /// field through. A nil event is one the session hid for secure input as it arrived.
    private func deliver(_ activity: AsyncStream<LiveActivity?>, from device: KeyboardDevice) async {
        // The keys subscribers saw go down and not yet up.
        var down: Set<Int> = []
        for await event in activity where keyboard == device {
            guard let event else {
                hide(&down)
                continue
            }
            switch event {
            case .lighting(false): releasesInFlight = max(releasesInFlight - 1, 0)
            // RGB_MATRIX_NOT_ENABLED: this build has no lights to take or give back.
            case .refused(0x04): (lightsTaken, releaseDue, releasesInFlight) = (false, false, 0)
            default: break
            }
            if event.isTyping {
                guard isPaired, !secureInputProbe() else {
                    hide(&down)
                    continue
                }
                switch event {
                case let .layer(layer):
                    // Every pairing reports the layer again (each reconnect, and the resync after a layer move).
                    guard layer != deliveredLayer else { continue }
                    deliveredLayer = layer
                case let .keyDown(index, _): down.insert(index)
                case let .keyUp(index): down.remove(index)
                case .lighting, .refused: break
                }
            }
            subscribers.values.forEach { $0.yield(event) }
        }
        // The session ended: its keys' key-ups will never come.
        if keyboard == device { releaseKeys(&down) }
    }

    /// Subscribers can't follow what is hidden: their keys may come up unseen, and their layer may change.
    private func hide(_ down: inout Set<Int>) {
        releaseKeys(&down)
        deliveredLayer = nil
    }

    private func releaseKeys(_ down: inout Set<Int>) {
        for index in down.sorted() { subscribers.values.forEach { $0.yield(.keyUp(index: index)) } }
        down = []
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

    /// A press, release or layer: what secure input hides. The keyboard's replies carry no typing.
    fileprivate var isTyping: Bool {
        switch self {
        case .keyDown, .keyUp, .layer: true
        case .lighting, .refused: false
        }
    }
}

extension Clock where Duration == Swift.Duration {
    /// Folds a link session's events into state and calls `body` with it debounced by 1/60 s on this clock: a
    /// burst collapses into one update, updates come at most 60 times a second, and nothing runs while the
    /// keyboard is idle. `tap` gets each event's ``LiveActivity`` as it is folded in, undebounced, or nil when secure
    /// input hides it. Returns the final state. A method so it can be called on an `any Clock` (passing one to a generic
    /// parameter doesn't compile in this module).
    /// shortcut: during a burst with gaps under 1/60 s the update waits for the pause; move to a leading-and-trailing
    /// throttle if that lag ever shows.
    fileprivate func publish(
        _ events: AsyncStream<LiveEvent>, board: BoardDefinition, tap: AsyncStream<LiveActivity?>.Continuation,
        secureInput: @escaping @Sendable () -> Bool, to body: @MainActor (LinkState) -> Void
    ) async -> LinkState {
        var last = LinkState()
        let states = events.reductions(into: LinkState()) { state, event in
            // Asked as the event arrives, so a press made during secure input never waits for the main actor.
            // A press, release or layer is hidden as nil, so the subscribers learn that something happened without what.
            if let activity = state.apply(event, board: board) { tap.yield(activity.isTyping && secureInput() ? nil : activity) }
        }
        for await state in states.debounce(for: .seconds(1) / 60, clock: self) {
            last = state
            await body(state)
        }
        return last
    }

    /// `duration` after now, or after `start` (an instant of this clock) when that is later. Type-erased, since an
    /// `any Clock`'s instants can't be named.
    fileprivate func instant(
        _ duration: Duration, afterNowOr start: (any InstantProtocol<Duration>)?
    ) -> any InstantProtocol<Duration> {
        let now = now
        guard let start = start as? Instant, start > now else { return now.advanced(by: duration) }
        return start.advanced(by: duration)
    }

    /// The time from now until `instant` (one of this clock's), or zero when it has passed or there is none.
    fileprivate func time(until instant: (any InstantProtocol<Duration>)?) -> Duration {
        guard let end = instant as? Instant else { return .zero }
        return max(now.duration(to: end), .zero)
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
            // Left out before the session's first layer report: there is no layer to tag the press with yet (RawHIDLink
            // sends none before pairing, which reports the layer).
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
