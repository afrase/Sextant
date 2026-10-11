import Clocks
import Foundation
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

    @Test func reconnectsWithBackoffWhileAnotherAppHoldsTheKeyboard() async {
        let live = start()
        let keyboard = KeyboardDevice.voyager(serial: "KlgM7/40xJ7M")
        watcher.attach(.keyboard(keyboard))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.ended(.heldByAnotherApp))
        #expect(await eventually { live.connection == .heldByAnotherApp(keyboard) })
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(500))
                return link.sessionCount == 2
            })
        link.send(.layer(0))
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(17))
                return live.connection == .connected(keyboard)
            })
    }

    @Test func hardwareAccessOffStopsTheLinkButKeepsTheSerial() async {
        let live = start()
        let keyboard = KeyboardDevice.voyager(serial: "KlgM7/40xJ7M")
        watcher.attach(.keyboard(keyboard))
        #expect(await eventually { link.sessionCount == 1 })
        link.send(.ended(.hardwareAccessOff))
        #expect(await eventually { live.connection == .hardwareAccessOff(keyboard) })
        await clock.advance(by: .seconds(60))
        #expect(link.sessionCount == 1, "no retries while access is off")
        #expect(live.firmwareSerial == "KlgM7/40xJ7M")
    }

    @Test func followsTheDeviceThroughFlashMode() async {
        let live = start()
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { live.firmwareSerial != nil })
        watcher.detach(1)
        watcher.attach(.bootloader(.stm32()))
        #expect(await eventually { live.connection == .bootloader(.stm32()) })
        #expect(live.firmwareSerial == nil && live.pressedKeys.isEmpty)
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
}

final class Flag: Sendable {
    private let value = Mutex(false)
    var isOn: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
