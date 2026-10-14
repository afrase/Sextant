import Clocks
import Foundation
import Observation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

@MainActor
struct LiveSessionTests {
    let watcher = FakeDeviceWatcher()
    let link = FakeKeyboardLink()
    let clock = TestClock()
    let secureInput = Flag()

    func start() -> LiveSession {
        let secureInput = secureInput
        let live = LiveSession(watcher: watcher, link: link, clock: clock) { secureInput.isOn }
        live.start()
        live.startLive()
        return live
    }

    @Test func showsTheKeyboardsLayerAndPressesAtMost60TimesASecond() async throws {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { live.connection == .connected(.voyager(serial: "KlgM7/40xJ7M")) && link.sessionCount == 1 })
        #expect(live.firmwareSerial == "KlgM7/40xJ7M", "the USB serial, before the link says anything")
        #expect(live.isFollowing, "Follow turns on when a keyboard connects")

        // Matrix row 2, column 2 is key 13; row 0, column 0 is an unused cell.
        link.send(.protocolVersion(5), .layer(2), .keyDown(row: 2, column: 2), .keyDown(row: 0, column: 0))
        try await Task.sleep(for: .milliseconds(20))
        #expect(live.activeLayer == nil, "nothing is published until the 1/60 s debounce elapses")
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.activeLayer == 2
            })
        #expect(live.pressedKeys == [13] && live.protocolVersion == 5 && live.followedLayer == 2)

        link.send(.keyUp(row: 2, column: 2))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.pressedKeys.isEmpty
            })
    }

    @Test func aManualLayerChoiceStopsFollowingUntilResumed() async {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { live.isFollowing })
        live.stopFollowing()
        #expect(!live.isFollowing && live.followedLayer == nil)
        live.follow()
        #expect(live.isFollowing)
    }

    /// Settings › Keyboard › Follow the keyboard by default, asked at each connect.
    @Test func followStaysOffAtConnectWhenTheUserTurnedThatOff() async {
        let follows = Flag()
        let live = LiveSession(watcher: watcher, link: link, clock: clock, followsOnConnect: { follows.isOn }) { false }
        live.start()
        live.startLive()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.protocolVersion(5), .layer(2))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.activeLayer == 2
            })
        #expect(!live.isFollowing && live.followedLayer == nil)

        follows.isOn = true
        watcher.detach(1)
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { live.isFollowing }, "the next connect asks again")
    }

    @Test func secureInputHidesPresses() async {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.keyDown(row: 2, column: 2))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.pressedKeys == [13]
            })
        secureInput.isOn = true
        #expect(
            await eventually {
                await clock.advance(by: .seconds(1))
                return live.isSecureInputOn
            })
        #expect(live.pressedKeys.isEmpty)
    }

    /// True when, once `settled` holds, the next link session opens exactly `delay` later on the test clock.
    func reopens(after delay: Duration, once settled: () -> Bool) async -> Bool {
        let count = link.sessionCount
        guard await eventually(settled) else { return false }
        await clock.advance(by: delay - .milliseconds(1))
        guard link.sessionCount == count else { return false }
        await clock.advance(by: .milliseconds(1))
        return await eventually { link.sessionCount == count + 1 }
    }

    @Test func reconnectsWithBackoffWhileAnotherAppHoldsTheKeyboard() async {
        let live = start()
        let keyboard = KeyboardDevice.voyager(serial: "KlgM7/40xJ7M")
        watcher.attach(.keyboard(keyboard))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.ended(.heldByAnotherApp))
        #expect(await reopens(after: .seconds(1)) { live.connection == .heldByAnotherApp(keyboard) })
        link.send(.layer(0))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.connection == .connected(keyboard)
            })
    }

    @Test func backsOffUntilASessionGoesLive() async {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        // Firmware too old for live events reports its protocol version, then ends: that is not live.
        for (version, seconds) in [(1, 1), (2, 2), (3, 4), (4, 8)] as [(UInt8, Int64)] {
            link.send(.protocolVersion(version), .ended(.io("firmware is too old")))
            #expect(await reopens(after: .seconds(seconds)) { live.protocolVersion == version }, "session \(version)")
        }
        link.send(.layer(1), .ended(.io("unplugged")))
        #expect(await reopens(after: .seconds(1)) { live.activeLayer == 1 }, "a live session resets the backoff")
    }

    @Test func stopBeforeTheWatcherRunsStartsNoLink() async throws {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        live.stop()
        try await Task.sleep(for: .milliseconds(100))  // let the cancelled watcher loop drain what it holds
        #expect(link.sessionCount == 0 && live.connection == .noKeyboard)
    }

    /// Nothing is written to a keyboard until the user turns Live View on (ADR 0057), and turning it off ends the link.
    @Test func theLinkOpensOnlyWhileLiveViewIsOn() async {
        let live = LiveSession(watcher: watcher, link: link, clock: clock) { false }
        live.start()
        let keyboard = KeyboardDevice.voyager(serial: "KlgM7/40xJ7M")
        watcher.attach(.keyboard(keyboard))
        #expect(await eventually { live.connection == .liveOff(keyboard) })
        await clock.advance(by: .seconds(60))
        #expect(link.sessionCount == 0, "plugging in writes nothing")
        #expect(live.firmwareSerial == "KlgM7/40xJ7M", "the USB serial still works")
        #expect(throws: DeviceError.notLive) { try live.send(.moveToLayer(1)) }
        live.startLive()
        #expect(await eventually { link.sessionCount == 1 && live.connection == .connected(keyboard) })
        live.stopLive()
        #expect(live.connection == .liveOff(keyboard) && !live.isLive && !live.isFollowing)
        await clock.advance(by: .seconds(60))
        #expect(link.sessionCount == 1, "no reconnects once it's off")
    }

    @Test func followsTheDeviceThroughFlashMode() async {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { live.firmwareSerial != nil })
        watcher.detach(1)
        watcher.attach(.bootloader(.stm32()))
        #expect(await eventually { live.connection == .bootloader(.stm32()) })
        #expect(live.firmwareSerial == nil && live.pressedKeys.isEmpty)
        #expect(throws: DeviceError.notLive) { try live.send(.moveToLayer(0)) }
        live.stopFollowing()
        watcher.detach(9)
        #expect(await eventually { live.connection == .noKeyboard })
        watcher.attach(.keyboard(.voyager(id: 2, serial: "KlgM7/q7Lm2E")))
        #expect(await eventually { live.firmwareSerial == "KlgM7/q7Lm2E" })
        #expect(live.isFollowing, "reconnecting turns Follow back on")
    }

    @Test func matchesTheSerialAgainstALayout() async throws {
        let live = start()
        let layout = try KeyboardLayout(oryxJSON: Fixtures.userLayoutData)
        #expect(live.match(layout, libraryID: UUID(), importedLayout: layout) == nil, "no keyboard, no match")
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { live.firmwareSerial != nil })
        #expect(live.match(layout, libraryID: UUID(), importedLayout: layout) == .current)
        #expect(live.match(layout, libraryID: UUID(), importedLayout: nil) == .thisLayout)
    }

    // MARK: Commands (ADR 0038)

    /// True once the newest link session's layer report has been published, which pairs it for commands.
    func pair(_ live: LiveSession, layer: Int = 0) async -> Bool {
        link.send(.layer(layer))
        return await eventually {
            await clock.advance(by: .milliseconds(17))
            return live.canSend
        }
    }

    @Test func sendsCommandsOnlyOverAPairedSession() async throws {
        let live = start()
        #expect(throws: DeviceError.notFound) { try live.send(.moveToLayer(1)) }
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.protocolVersion(5))
        #expect(!live.canSend)
        #expect(throws: DeviceError.notLive) { try live.send(.moveToLayer(1)) }
        #expect(await pair(live))
        try live.send(.moveToLayer(1))
        try live.send(.setLED(index: 51, red: 255, green: 0, blue: 0))
        #expect(await eventually { link.commands == [[.moveToLayer(1), .setLED(index: 51, red: 255, green: 0, blue: 0)]] })
    }

    @Test(arguments: [
        KeyboardCommand.moveToLayer(32), .moveToLayer(-1), .setLED(index: 52, red: 0, green: 0, blue: 0),
        .setLED(index: -1, red: 0, green: 0, blue: 0),
    ])
    func refusesLayersAndLightsOutsideTheBoard(_ command: KeyboardCommand) async throws {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        #expect(await pair(live))
        #expect(throws: DeviceError.outOfRange) { try live.send(command) }
        try live.send(.moveToLayer(31))
        #expect(await eventually { link.commands == [[.moveToLayer(31)]] }, "only the allowed command arrives")
    }

    @Test func refusesWhileAnotherAppHoldsTheKeyboardOrAccessIsOff() async {
        let live = start()
        let keyboard = KeyboardDevice.voyager(serial: nil)
        watcher.attach(.keyboard(keyboard))
        #expect(await eventually { link.sessionCount == 1 })
        #expect(await pair(live))
        link.send(.ended(.heldByAnotherApp))
        #expect(await reopens(after: .seconds(1)) { live.connection == .heldByAnotherApp(keyboard) && !live.canSend })
        #expect(throws: DeviceError.heldByAnotherApp) { try live.send(.moveToLayer(1)) }
        live.stopLive()
        #expect(live.connection == .liveOff(keyboard))
        #expect(throws: DeviceError.notLive) { try live.send(.moveToLayer(1)) }
        #expect(link.commands == [[], []])
    }

    @Test func aReconnectedSessionGetsItsOwnCommands() async throws {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        #expect(await pair(live))
        try live.send(.moveToLayer(1))
        link.send(.ended(.io("unplugged")))
        #expect(await reopens(after: .seconds(1)) { !live.canSend })
        #expect(throws: DeviceError.notLive) { try live.send(.moveToLayer(2)) }
        #expect(await pair(live, layer: 1))
        try live.send(.moveToLayer(0))
        #expect(await eventually { link.commands == [[.moveToLayer(1)], [.moveToLayer(0)]] })
        watcher.detach(1)
        #expect(await eventually { !live.canSend })
        #expect(throws: DeviceError.notFound) { try live.send(.moveToLayer(0)) }
    }

    /// The debounce still publishes a session's last state after it ends; that state must not open the command feed.
    @Test func aSessionThatEndsBeforePublishingNeverTakesCommands() async {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        let wasSendable = Flag()
        withObservationTracking {
            _ = live.canSend
        } onChange: {
            Task { @MainActor in if live.canSend { wasSendable.isOn = true } }
        }
        link.send(.layer(0), .ended(.io("unplugged")))
        #expect(await eventually { live.activeLayer == 0 })
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!wasSendable.isOn && !live.canSend)
    }

    // MARK: Activity

    @Test func activityDeliversEveryPressTheDebounceCollapses() async {
        let live = start()
        let seen = Recorded<LiveActivity>()
        let stream = live.activity()
        let reader = Task { for await activity in stream { seen.append(activity) } }
        defer { reader.cancel() }
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        // Two taps shorter than a frame, around a layer change: matrix (2, 2) is key 13 and (5, 0) is key 24.
        link.send(
            .layer(0), .keyDown(row: 2, column: 2), .keyUp(row: 2, column: 2), .layer(1), .keyDown(row: 5, column: 0),
            .keyUp(row: 5, column: 0), .keyDown(row: 0, column: 0))
        #expect(
            await eventually {
                seen.values == [
                    .layer(0), .keyDown(index: 13, layer: 0), .keyUp(index: 13), .layer(1), .keyDown(index: 24, layer: 1),
                    .keyUp(index: 24),
                ]
            })
        #expect(live.activeLayer == nil && live.pressedKeys.isEmpty, "the debounced state hasn't published yet")
    }

    /// Asked at every event, not at the once-a-second poll: a password's first keys come right after its field focuses.
    @Test func activityIsSilentDuringSecureInput() async {
        let live = start()
        let seen = Recorded<LiveActivity>()
        let stream = live.activity()
        let reader = Task { for await activity in stream { seen.append(activity) } }
        defer { reader.cancel() }
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 && secureInput.reads > 0 })
        secureInput.isOn = true  // the poll saw it off and sleeps for a second
        link.send(.layer(0), .keyDown(row: 2, column: 2), .keyUp(row: 2, column: 2))
        // They reach the main actor's queue before the debounced state does, so once it shows they were dropped.
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.activeLayer == 0
            })
        secureInput.isOn = false
        link.send(.keyDown(row: 5, column: 0))
        #expect(await eventually { seen.values == [.keyDown(index: 24, layer: 0)] })
    }

    /// Asked as each event arrives too: a press made during secure input stays out even when the field loses focus
    /// before the main actor would deliver it. The probe here says "on" only off the main thread, so it is on as events
    /// arrive and off by the time the main actor sees them.
    @Test func aPressFromAPasswordFieldNeverWaitsForTheMainActor() async {
        let live = LiveSession(watcher: watcher, link: link, clock: clock) { pthread_main_np() == 0 }
        live.start()
        live.startLive()
        defer { live.stop() }
        let seen = Recorded<LiveActivity>()
        let stream = live.activity()
        let reader = Task { for await activity in stream { seen.append(activity) } }
        defer { reader.cancel() }
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.layer(0), .keyDown(row: 2, column: 2))
        // The activity reaches the main actor's queue before the debounced state does, so once the press shows it
        // has been dropped or delivered.
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.pressedKeys == [13]
            })
        #expect(seen.values.isEmpty)
    }

    /// Within a session only a change is activity. A new session's pairing reports the layer it finds, even when it repeats
    /// the last one: the keyboard may have changed layers between the two, unseen (ADR 0053). Lighting replies and
    /// refusals pass through.
    @Test func activityReportsALayerOnlyWhenItChanges() async {
        let live = start()
        let seen = Recorded<LiveActivity>()
        let stream = live.activity()
        let reader = Task { for await activity in stream { seen.append(activity) } }
        defer { reader.cancel() }
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.layer(0), .layer(0), .ended(.io("unplugged")))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(100))
                return link.sessionCount == 2
            })
        link.send(.layer(0), .layer(2), .lighting(true), .error(0x04))
        #expect(await eventually { seen.values == [.layer(0), .layer(0), .layer(2), .lighting(true), .refused(0x04)] })
    }

    /// What secure input hides, subscribers can't follow: the keys they saw go down come up, and the next layer report
    /// arrives even when it repeats the last one they got.
    @Test func secureInputReleasesTheKeysDownAndLetsTheNextLayerThrough() async {
        let live = start()
        let seen = Recorded<LiveActivity>()
        let stream = live.activity()
        let reader = Task { for await activity in stream { seen.append(activity) } }
        defer { reader.cancel() }
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.layer(0), .keyDown(row: 5, column: 0))
        #expect(await eventually { seen.values == [.layer(0), .keyDown(index: 24, layer: 0)] })
        secureInput.isOn = true
        link.send(.layer(1), .keyUp(row: 5, column: 0), .layer(0))
        #expect(await eventually { seen.values.count == 3 })
        #expect(seen.values.last == .keyUp(index: 24))
        secureInput.isOn = false
        link.send(.layer(0))
        #expect(await eventually { seen.values == [.layer(0), .keyDown(index: 24, layer: 0), .keyUp(index: 24), .layer(0)] })
    }

    /// A key-up that will never come arrives anyway when the session ends.
    @Test func aSessionThatEndsReleasesItsKeys() async {
        let live = start()
        let seen = Recorded<LiveActivity>()
        let stream = live.activity()
        let reader = Task { for await activity in stream { seen.append(activity) } }
        defer { reader.cancel() }
        watcher.attach(.keyboard(.voyager(serial: nil)))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.layer(0), .keyDown(row: 5, column: 0), .keyDown(row: 2, column: 2), .keyUp(row: 2, column: 2), .ended(nil))
        #expect(
            await eventually {
                seen.values == [
                    .layer(0), .keyDown(index: 24, layer: 0), .keyDown(index: 13, layer: 0), .keyUp(index: 13), .keyUp(index: 24),
                ]
            })
    }
}

/// Values a reading task collects for the test.
final class Recorded<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])
    var values: [Value] { storage.withLock { $0 } }
    func append(_ value: Value) { storage.withLock { $0.append(value) } }
}

final class Flag: Sendable {
    private let value = Mutex(false)
    private let readCount = Mutex(0)
    var isOn: Bool {
        get {
            readCount.withLock { $0 += 1 }
            return value.withLock { $0 }
        }
        set { value.withLock { $0 = newValue } }
    }
    /// How often `isOn` was read.
    var reads: Int { readCount.withLock { $0 } }
}
