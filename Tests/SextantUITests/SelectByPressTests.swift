import Foundation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

@testable import SextantUI

/// Select Key by Pressing It (⇧⌘L, ADR 0052) over a live session on fakes: nothing here touches a keyboard.
@MainActor
struct SelectByPressTests {
    private let watcher = FakeDeviceWatcher()
    private let link = FakeKeyboardLink()
    private let secureInput = SecureInput()

    /// The user's layout in a window over a live session; Live View is on unless `live` is false. Follow stays off, so the
    /// shown layer is the test's.
    func window(live isLive: Bool = true) async throws -> (LayoutWindowModel, LiveSession) {
        let library = Library(store: MemoryLibrary())
        _ = try await library.importOryxJSON(try #require(userLayoutData))
        let secureInput = secureInput
        let live = LiveSession(watcher: watcher, link: link, followsOnConnect: { false }, secureInputProbe: { secureInput.isOn })
        live.start()
        if isLive { live.startLive() }
        let model = LayoutWindowModel(library: library, live: live)
        await model.open(nil)
        return (model, live)
    }

    /// Plugs the keyboard in; with Live View on, its session pairs and reports layer 0.
    func plugIn(_ live: LiveSession) async {
        watcher.attach(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: nil)))
        guard live.isLive else { return }
        #expect(await eventually { link.sessionCount > 0 })
        link.send(.layer(0))
        #expect(await eventually { live.canSend })
    }

    @Test func pressingRow5Column0SelectsKey24OnTheShownLayer() async throws {
        let (model, live) = try await window()
        await plugIn(live)
        let session = try #require(model.session)
        session.select(layer: 1)
        model.startSelectByPress()
        #expect(model.selectsByPress)

        link.send(.keyDown(row: 5, column: 0))
        #expect(await eventually { session.selection.keyIndex == 24 })
        #expect(session.selection.layer == 1, "the shown layer, whatever the keyboard's")
        #expect(!model.selectsByPress, "the capsule goes")
        // Until the key-up, the Mac's copy of the press is kept from type-to-search and the esc ladder.
        #expect(model.selectByPressTakes(keyCode: 0x24, isKeyDown: true))
        #expect(model.selectByPress != nil)

        link.send(.keyUp(row: 5, column: 0))
        #expect(await eventually { model.selectByPress == nil })
        #expect(!model.selectByPressTakes(keyCode: 0x24, isKeyDown: true), "the Mac's keys reach the window again")
    }

    /// The press feed comes before the 60 Hz coalescing, so a tap under one frame still selects.
    @Test func aDownAndUpWithin16msStillSelects() async throws {
        let (model, live) = try await window()
        await plugIn(live)
        model.startSelectByPress()
        link.send(.keyDown(row: 5, column: 0), .keyUp(row: 5, column: 0))
        #expect(await eventually { model.session?.selection.keyIndex == 24 && model.selectByPress == nil })
    }

    @Test func escAndCancelEndTheMode() async throws {
        let (model, live) = try await window()
        await plugIn(live)
        let session = try #require(model.session)
        session.select(key: 19)

        model.startSelectByPress()
        model.endSelectByPress()  // [Cancel]
        #expect(model.selectByPress == nil)

        // Esc from the Mac waits a moment for the keyboard's own Esc before it cancels; it is swallowed either way.
        model.startSelectByPress()
        #expect(model.selectByPressTakes(keyCode: 0x35, isKeyDown: true))
        #expect(await eventually { model.selectByPress == nil })

        // Esc that reaches the board (the monitor isn't installed while the window isn't key): its rung, before deselecting.
        model.startSelectByPress()
        model.escapeBoard()
        #expect(model.selectByPress == nil)
        #expect(session.selection.keyIndex == 19)

        // Nothing selects after the mode ends.
        link.send(.keyDown(row: 5, column: 0), .layer(2))
        #expect(await eventually { live.activeLayer == 2 })
        #expect(session.selection.keyIndex == 19)
    }

    /// The keyboard's Esc reports itself before the Mac's copy arrives: that Esc selects key 0 and doesn't cancel.
    @Test func theKeyboardsOwnEscIsSelectedNotTakenForCancel() async throws {
        let (model, live) = try await window()
        await plugIn(live)
        model.startSelectByPress()
        let esc = BoardDefinition.voyager.keys[0]
        link.send(.keyDown(row: esc.matrixRow, column: esc.matrixColumn))
        #expect(await eventually { model.session?.selection.keyIndex == 0 })
        #expect(model.selectByPressTakes(keyCode: 0x35, isKeyDown: true))
        try await Task.sleep(for: LayoutWindowModel.selectByPressTail * 2)
        #expect(model.selectByPress != nil, "it waits for the key-up")
        #expect(model.session?.selection.keyIndex == 0)
    }

    @Test func itExcludesRecordKeyAndThePalette() async throws {
        let (model, live) = try await window()
        await plugIn(live)
        model.session?.select(key: 19)

        model.startRecording()
        model.startSelectByPress()
        #expect(model.recorder == nil && model.selectByPress != nil)
        model.startRecording()
        #expect(await eventually { model.selectByPress == nil })

        model.openPalette()
        model.startSelectByPress()
        #expect(model.palette == nil && model.selectByPress != nil)
        model.openPalette()
        #expect(await eventually { model.selectByPress == nil })
    }

    @Test func pressesAreIgnoredDuringSecureInput() async throws {
        secureInput.isOn = true
        let (model, live) = try await window()
        await plugIn(live)
        #expect(await eventually { live.isSecureInputOn })
        model.startSelectByPress()
        #expect(model.selectsByPress && model.selectByPressIsPaused)

        // The press reaches the main actor before the debounced layer does, so once the layer shows it was dropped.
        link.send(.keyDown(row: 5, column: 0), .layer(2))
        #expect(await eventually { live.activeLayer == 2 })
        #expect(model.session?.selection.keyIndex == nil)
        #expect(model.selectsByPress, "still waiting for a press")
    }

    @Test func theModeEndsWhenTheSessionDrops() async throws {
        let (model, live) = try await window()
        await plugIn(live)
        model.startSelectByPress()
        link.send(.ended(.io("unplugged")))
        #expect(await eventually { model.selectByPress == nil })
    }

    @Test func theCommandSaysWhyItCantStart() async throws {
        let (off, offLive) = try await window(live: false)
        #expect(off.selectByPressRefusal == "Connect your keyboard to select a key by pressing it.")
        await plugIn(offLive)
        #expect(await eventually { offLive.connection != .noKeyboard })
        #expect(off.selectByPressRefusal == "Turn on Live View (Keyboard ▸ Live View) to select a key by pressing it.")
        off.startSelectByPress()
        #expect(off.selectByPress == nil, "Live View off: nothing to read")

        // The keyboard is already plugged in: this session pairs at once, but reports no layer yet.
        let (model, live) = try await window()
        #expect(await eventually { model.selectByPressRefusal == "Live View is still connecting to the keyboard." })
        await plugIn(live)
        #expect(model.selectByPressRefusal == nil)
        model.destination = .macros
        #expect(model.selectByPressRefusal == "Show the board to select a key by pressing it.")
        model.destination = .combos
        #expect(model.selectByPressRefusal == nil, "Combos shows the board")
    }

    /// A page that hides the board ends the mode.
    @Test func leavingTheBoardEndsTheMode() async throws {
        let (model, live) = try await window()
        await plugIn(live)
        model.startSelectByPress()
        model.destination = .firmwareSettings
        #expect(await eventually { model.selectByPress == nil })
    }
}

// MARK: - Fakes

private final class SecureInput: Sendable {
    private let state = Mutex(false)
    var isOn: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

/// Presence as the real watcher reports it: devices already present first, then changes.
private final class FakeDeviceWatcher: DeviceWatcher {
    private let state = Mutex<(present: [ConnectedDevice], subscribers: [AsyncStream<DeviceEvent>.Continuation])>(([], []))

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
        state.withLock { s in
            s.present.forEach { continuation.yield(.attached($0)) }
            s.subscribers.append(continuation)
        }
        return stream
    }

    func attach(_ device: ConnectedDevice) {
        state.withLock { s in
            s.present.append(device)
            s.subscribers.forEach { $0.yield(.attached(device)) }
        }
    }
}

/// A live link whose newest session the test drives. Nothing is written anywhere.
private final class FakeKeyboardLink: KeyboardLink {
    private let open = Mutex<[AsyncStream<LiveEvent>.Continuation]>([])

    var sessionCount: Int { open.withLock { $0.count } }

    func session(
        with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>
    ) -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self)
        open.withLock { $0.append(continuation) }
        return stream
    }

    /// Sends events on the newest session; `.ended` also ends it.
    func send(_ events: LiveEvent...) {
        guard let session = open.withLock({ $0.last }) else { return }
        for event in events {
            session.yield(event)
            if case .ended = event { session.finish() }
        }
    }
}

/// Polls `condition`, letting other tasks run, for up to about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
