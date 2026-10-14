import Clocks
import Foundation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

@testable import SextantUI

/// The overlay fed by a real live session (``OverlayHUD/feed(_:from:keyboard:)``), on a stand-in keyboard and a test
/// clock: secure input and a session that ends leave nothing stale on screen. Nothing here talks to a keyboard or shows
/// a panel. Matrix (5, 0) is ⏎, key 24, which holds Sym+Num.
@MainActor
struct OverlayHUDTests {
    private let clock = TestClock()
    private let keyboard = SessionKeyboard()
    private let secureInput = SecureInput()

    private func start() async throws -> (LiveSession, OverlayModel, [Task<Void, Never>]) {
        let secureInput = secureInput
        let live = LiveSession(watcher: keyboard, link: keyboard, clock: clock) { secureInput.isOn }
        live.start()
        live.startLive()
        let model = OverlayModel(clock: clock)
        let layout = try OverlayLayout(id: UUID(), layout: KeyboardLayout(oryxJSON: #require(userLayoutData)))
        let tasks = OverlayHUD.feed(model, from: live, keyboard: { layout })
        #expect(await until { keyboard.sessionCount == 1 && model.isLive })
        return (live, model, tasks)
    }

    /// Runs the clock in frames until `condition` holds, for at most `limit`.
    private func until(_ limit: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        var elapsed = Duration.zero
        while !condition() && elapsed < limit {
            for _ in 0..<10 { await Task.yield() }
            await clock.advance(by: .milliseconds(10))
            elapsed += .milliseconds(10)
        }
        return condition()
    }

    @Test func aLayerChangedDuringSecureInputLeavesNothingStale() async throws {
        let (live, model, tasks) = try await start()
        defer { tasks.forEach { $0.cancel() } }
        defer { live.stop() }
        keyboard.send(.layer(0))
        #expect(await until { model.layer == 0 })
        secureInput.isOn = true
        #expect(await until { model.isSecureInputOn })
        // ⏎ goes down and moves the keyboard to Sym+Num while secure input hides both.
        keyboard.send(.keyDown(row: 5, column: 0), .layer(1))
        #expect(await until { live.activeLayer == 1 })
        secureInput.isOn = false
        #expect(await until { !model.isSecureInputOn })
        #expect(await !until(.milliseconds(300)) { model.presentation != nil }, "still held: no reminder for a lock")

        // Back on the base layer: the report repeats the last one delivered, and arrives all the same.
        keyboard.send(.keyUp(row: 5, column: 0), .layer(0))
        #expect(await until { model.layer == 0 })
        #expect(model.presentation == nil)
        // Locked by a layer move: the reminder shows.
        keyboard.send(.layer(1))
        #expect(await until { model.presentation == .pill(layer: 1) })
    }

    @Test func aSessionThatEndsLetsGoOfItsKeys() async throws {
        let (live, model, tasks) = try await start()
        defer { tasks.forEach { $0.cancel() } }
        defer { live.stop() }
        keyboard.send(.layer(0), .keyDown(row: 5, column: 0), .layer(1))
        #expect(await until { model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)) })
        keyboard.send(.ended(nil))
        #expect(await until { model.presentation == nil && model.pressedKeys.isEmpty })

        #expect(await until { keyboard.sessionCount == 2 })
        keyboard.send(.layer(0), .layer(1))
        #expect(await until { model.presentation == .pill(layer: 1) }, "a lock, not a layer ⏎ holds")
    }
}

/// A Voyager that is plugged in; each live session is the test's to drive.
private final class SessionKeyboard: DeviceWatcher, KeyboardLink {
    private let sessions = Mutex<[AsyncStream<LiveEvent>.Continuation]>([])

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self)
        sessions.withLock { $0.append(continuation) }
        return stream
    }

    var sessionCount: Int { sessions.withLock { $0.count } }

    /// Sends events on the newest session; `.ended` also ends it.
    func send(_ events: LiveEvent...) {
        guard let session = sessions.withLock({ $0.last }) else { return }
        for event in events {
            session.yield(event)
            if case .ended = event { session.finish() }
        }
    }
}

/// macOS secure input, as the test turns it on and off.
private final class SecureInput: Sendable {
    private let value = Mutex(false)
    var isOn: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
