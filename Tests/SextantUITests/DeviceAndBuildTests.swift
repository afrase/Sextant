import Foundation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

@testable import SextantUI

/// The window over a live session and Build & Flash, both on fakes (spec §3.5, §7, §8.2).
@MainActor
struct DeviceAndBuildTests {
    private let watcher = Watcher()
    private let link = Link()
    private let flashMode = Watcher()

    /// A window with the user's layout open, a live session on the fake watcher and link (or `live`, shared with
    /// another window), and Build & Flash whose build succeeds and then waits for flash mode on `flashMode`.
    func window(
        library: Library? = nil, live: LiveSession? = nil, toolchain: any Toolchain = Builds(), flasher: any Flasher = HoldingFlasher()
    ) async throws -> LayoutWindowModel {
        let store = MemoryLibrary()
        let library = library ?? Library(store: store)
        if library.entries.isEmpty { _ = try await library.importOryxJSON(try #require(userLayoutData)) }
        let live = live ?? LiveSession(watcher: watcher, link: link, secureInputProbe: { false })
        live.start()
        live.startLive()
        let flashMode = flashMode
        let model = LayoutWindowModel(
            library: library, live: live,
            makeBuildFlash: { session in
                BuildFlashSession(
                    session: session, library: store, generator: Generator(), toolchain: toolchain, watcher: flashMode,
                    flasher: flasher, md5: { _ in "" }, live: live)
            })
        await model.open(nil)
        return model
    }

    @Test func followTracksTheKeyboardUntilALayerIsChosenByHand() async throws {
        let model = try await window()
        let session = try #require(model.session)
        let following = Task { await model.followKeyboard() }
        defer { following.cancel() }
        #expect(model.activity == ActivityState(), "no keyboard")
        #expect(!model.canFollow)

        watcher.attach(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))
        let key13 = BoardDefinition.voyager.keys[13]
        #expect(await eventually { link.sessions > 0 })
        link.send(.protocolVersion(5), .layer(2), .keyDown(row: key13.matrixRow, column: key13.matrixColumn))
        #expect(await eventually { session.selection.layer == 2 }, "the shown layer follows the keyboard's")
        #expect(model.isFollowing && model.canFollow && model.pressedKeys.state(13).isDown)
        #expect(model.activity.device == .connected(serial: "KlgM7/40xJ7M", matchesLayout: true))

        session.select(layer: 1)
        #expect(await eventually { !model.isFollowing }, "a layer chosen by hand stops Follow")
        link.send(.layer(0), .keyUp(row: key13.matrixRow, column: key13.matrixColumn))
        #expect(await eventually { model.live?.activeLayer == 0 && !model.pressedKeys.state(13).isDown }, "the window saw it")
        #expect(session.selection.layer == 1, "the keyboard no longer moves the shown layer")

        model.isFollowing = true  // ⌘L
        #expect(await eventually { session.selection.layer == 0 })
        #expect(model.isFollowing, "Follow's own layer change doesn't count as a hand's")
    }

    @Test func buildCommandsRunTheWindowsBuildFlashAndClosingStopsIt() async throws {
        let model = try await window()
        let build = try #require(model.buildFlash)
        #expect(model.canBuild && !model.canStop)
        model.build(.buildAndFlash)
        #expect(model.showsBuildSheet, "⌘R shows the sheet")
        #expect(await eventually { build.phase == .waitingForFlashMode(stillWaiting: false) })
        #expect(model.activity.status == .waitingForFlashMode)
        #expect(model.canStop && !model.canBuild, "Stop instead of Build while waiting")
        model.showsBuildSheet = false  // Hide
        #expect(build.phase == .waitingForFlashMode(stillWaiting: false), "hiding keeps it running")
        await model.trashLayout(try #require(model.session?.id))
        #expect(build.phase == .idle, "a trashed or closed layout can't flash the next keyboard put in flash mode")
        #expect(model.buildFlash == nil)
    }

    /// The build tools' download stops from the toolbar and ⌘., like a build.
    @Test func settingUpCanBeStopped() async throws {
        let model = try await window(toolchain: HeldSetup())
        let build = try #require(model.buildFlash)
        model.build(.buildAndFlash)
        #expect(await eventually { if case .needsSetup = build.phase { true } else { false } })
        build.setUpBuildTools()
        #expect(await eventually { model.activity.status == .settingUp(fraction: 0.5) })
        #expect(model.canStop && !model.canBuild)
        model.build(.stop)
        #expect(build.phase == .idle)
    }

    /// Leaving a layout stops its Build & Flash: a waiting run has no time limit and would flash the next keyboard.
    @Test func switchingLayoutsStopsTheOldLayoutsBuild() async throws {
        let library = Library(store: MemoryLibrary())
        let data = try #require(userLayoutData)
        let first = try await library.importOryxJSON(data)
        let second = try await library.importOryxJSON(data)
        let model = try await window(library: library)
        await model.open(first.id)
        let old = try #require(model.buildFlash)
        old.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { old.phase == .waitingForFlashMode(stillWaiting: false) })
        await model.open(second.id)
        #expect(old.phase == .idle)
        #expect(model.buildFlash !== old, "each layout gets its own")
    }

    /// Keymapp holding the keyboard: Follow is on but nothing arrives. Then Live View off (the default, ADR 0057).
    @Test func nothingClaimsToBeLiveWithoutALayer() async throws {
        let model = try await window()
        let keyboard = KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")
        watcher.attach(.keyboard(keyboard))
        #expect(await eventually { link.sessions > 0 })
        link.send(.ended(.heldByAnotherApp))
        #expect(await eventually { model.live?.connection == .heldByAnotherApp(keyboard) })
        #expect(model.live?.isFollowing == true, "the live session turned Follow on when Live View started")
        #expect(!model.isFollowing && !model.canFollow && model.laneStatus == nil)
        #expect(model.readout == "Layer 0 · base · 52 keys")
        model.isLive = false
        #expect(model.live?.connection == .liveOff(keyboard) && model.canGoLive && !model.canFollow)
    }

    /// A flash that writes can't be stopped, so the window keeps its layout until it ends.
    @Test func switchingLayoutsWaitsForAFlashThatIsWriting() async throws {
        let library = Library(store: MemoryLibrary())
        let data = try #require(userLayoutData)
        let first = try await library.importOryxJSON(data)
        let second = try await library.importOryxJSON(data)
        let flasher = HoldingFlasher()
        let model = try await window(library: library, flasher: flasher)
        await model.open(first.id)
        let build = try #require(model.buildFlash)
        flashMode.attach(.bootloader(BootloaderDevice(id: 9, productID: 0x0791, kind: .stm32, version: 1)))
        build.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { if case .writing = build.phase { true } else { false } })
        #expect(!model.canStop && !model.canBuild, "nothing stops or restarts a flash that writes (spec §7.4)")
        #expect(await model.open(second.id) == first.id, "refused while writing")
        #expect(model.buildFlash === build && model.session?.id == first.id)
        await model.trashLayout(first.id)
        #expect(!model.canTrash(first.id) && model.session?.id == first.id, "nor trashed")
        flasher.release()
        #expect(await eventually { build.phase == .verifying })
        #expect(!model.canStop && !model.canBuild)
        flashMode.attach(.keyboard(KeyboardDevice(id: 2, productID: 0x1977, serial: build.identity?.serial)))
        #expect(await eventually { if case .done = build.phase { true } else { false } })
        #expect(await model.open(second.id) == second.id, "once flashed, the window moves on")
    }

    @Test func buildOnlyIsQuietAndTheCapsuleShowsItsSize() async throws {
        let model = try await window()
        let build = try #require(model.buildFlash)
        model.build(.build)
        #expect(await eventually { build.phase == .built })
        #expect(!model.showsBuildSheet, "⌘B doesn't bring up the sheet")
        #expect(model.activity.status == .built(bytes: 65_786, percentOfFlash: 54))
        model.build(.showLog)
        #expect(model.showsBuildSheet && model.showsBuildLog)
    }

    @Test func aKeyboardRunningAnUnknownOryxLayoutOffersImport() async throws {
        let model = try await window()
        watcher.attach(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "Q9x2a/aa11")))
        #expect(await eventually { model.unknownOryxSerial == "Q9x2a/aa11" })
        #expect(model.activity.status == .otherLayout(serial: "Q9x2a/aa11"))
        watcher.detach(1)
        watcher.attach(.keyboard(KeyboardDevice(id: 2, productID: 0x1977, serial: "KlgM7/0aB1cD")))
        #expect(await eventually { model.live?.firmwareSerial == "KlgM7/0aB1cD" })
        #expect(model.unknownOryxSerial == nil, "the library has a layout from that Oryx layout")
        #expect(model.activity.status == .notOnKeyboard(edits: nil), "an earlier revision of this layout")
        #expect(model.liveLayerTitle(1) == "Sym+Num")
    }

    /// Spec §7.6: while one window waits for flash mode or flashes, the others can't start a Build & Flash.
    @Test func oneWindowFlashesAtATime() async throws {
        let library = Library(store: MemoryLibrary())
        let data = try #require(userLayoutData)
        _ = try await library.importOryxJSON(data)
        _ = try await library.importOryxJSON(data)
        let first = try await window(library: library)
        let second = try await window(library: library, live: first.live)
        #expect(first.session?.id != second.session?.id && second.canBuild)
        first.build(.buildAndFlash)
        #expect(await eventually { first.activity.status == .waitingForFlashMode })
        #expect(!second.canBuild && second.activity.status == .flashingElsewhere(layout: "My MacOS Layout"))
        let flashing = try #require(first.session?.id)
        #expect(second.canTrash(flashing), "waiting can be stopped: closing that window stops the run")
        await first.close()
        #expect(await eventually { second.canBuild }, "free again once the run stops")
    }

    /// Another layout's layer numbers mean other layers: the window doesn't move, badge or name them.
    @Test func aKeyboardOnAnotherLayoutDoesntMoveOrNameTheLayers() async throws {
        let model = try await window()
        let session = try #require(model.session)
        let following = Task { await model.followKeyboard() }
        defer { following.cancel() }
        watcher.attach(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "Q9x2a/aa11")))
        #expect(await eventually { link.sessions > 0 })
        let key13 = BoardDefinition.voyager.keys[13]
        link.send(.protocolVersion(5), .layer(2), .keyDown(row: key13.matrixRow, column: key13.matrixColumn))
        #expect(await eventually { model.pressedKeys.state(13).isDown }, "the window saw the layer with the press")
        #expect(session.selection.layer == 0 && !model.runsThisLayout)
        #expect(model.laneStatus == .live(text: "LIVE · Layer 2"))
    }

    /// The user's main state: the unedited import on the keyboard reads "On keyboard"; edits are counted.
    @Test func theImportOnTheKeyboardIsOnKeyboardUntilEdited() async throws {
        let model = try await window()
        let session = try #require(model.session)
        let following = Task { await model.followKeyboard() }
        defer { following.cancel() }
        watcher.attach(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))
        #expect(await eventually { if case .onKeyboard = model.activity.status { true } else { false } })
        session.renameLayer(2, to: "Board")
        #expect(model.activity.status == .notOnKeyboard(edits: nil), "only key edits are counted")
        session.setCode("KC_F13", layer: 0, index: 1)
        #expect(model.activity.status == .notOnKeyboard(edits: 1))
    }

    @Test func buildWithLiveErrorsShowsWhatBlocksIt() async throws {
        let model = try await window()
        model.session?.setCode("KC_FOO", layer: 0, index: 1)
        model.build(.build)
        #expect(model.showsBuildSheet, "⌘B would otherwise seem to do nothing")
        #expect(await eventually { if case .blocked = model.buildFlash?.phase { true } else { false } })
    }

    /// Spec §7.5: a compile error the source map placed on a key rings its cap and fills the lens lane.
    @Test func aMappedCompileErrorReachesTheBoardAndTheLane() async throws {
        let key = KeyRef(layer: 2, index: 45, slot: .tap)
        let error = Diagnostic(file: "keymap.c", line: 31, column: 9, severity: .error, message: "undeclared", key: key)
        let model = try await window(toolchain: FailingBuild(diagnostics: [error]))
        model.build(.build)
        #expect(await eventually { model.buildFlash?.phase.isFailure == true })
        #expect(model.issueMap[KeyRef(layer: 2, index: 45)] == .error)
        #expect(model.laneStatus == .issue(text: "Build error on Brd+Sys · key 45 · Tap", key: key))
    }

    /// First launch (spec §12.1): no layout for the keyboard to differ from.
    @Test func withNoLayoutOpenTheKeyboardIsJustConnected() async throws {
        let live = LiveSession(watcher: watcher, link: link, secureInputProbe: { false })
        live.start()
        let model = LayoutWindowModel(library: Library(store: MemoryLibrary()), live: live)
        await model.open(nil)
        watcher.attach(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))
        #expect(await eventually { model.live?.firmwareSerial != nil })
        #expect(
            model.activity == ActivityState(device: .connected(serial: "KlgM7/40xJ7M", matchesLayout: true), status: .keyboardConnected))
    }

    // MARK: Mapping

    @Test func phasesMapToTheCapsule() {
        typealias Status = ActivityState.Status
        func status(_ phase: BuildFlashSession.Phase) -> Status? { Status(phase, usedBytes: 61_440, capacity: 122_880) }
        #expect(status(.idle) == nil && status(.blocked([])) == nil && status(.confirmingReplace(serial: nil, title: nil)) == nil)
        #expect(status(.needsSetup("1 GB")) == .needsSetup)
        #expect(status(.compiling(file: "keymap.c", done: 12, total: 41)) == .building(file: "keymap.c", done: 12, total: 41))
        #expect(status(.built) == .built(bytes: 61_440, percentOfFlash: 50))
        #expect(status(.erasing(done: 0, total: 0)) == .erasing(fraction: 0), "no division by zero")
        #expect(status(.writing(done: 16, total: 64)) == .writing(fraction: 0.25, bytes: 16))
        let mapped = Diagnostic(file: "keymap.c", line: 31, column: 9, severity: .error, message: "", key: KeyRef(layer: 2, index: 45))
        let unmapped = Diagnostic(file: "quantum.c", line: 1, column: 1, severity: .error, message: "")
        let warning = Diagnostic(file: "keymap.c", line: 2, column: 1, severity: .warning, message: "", key: KeyRef(layer: 0, index: 1))
        #expect(status(.failed(.toolchain(.compileFailed([warning, unmapped, mapped])))) == .buildFailed(errors: 2, key: 45))
        #expect(status(.failed(.toolchain(.tooLarge(overBy: 10)))) == .buildFailed(errors: 1, key: nil))
        #expect(status(.failed(.flash(.dfuError(status: 10, address: 0x0800_2000)))) == .flashFailed)
        #expect(status(.failed(.setup(.failed("offline")))) == .needsSetup, "a failed download isn't a failed build")
        let revision = RevisionSummary(id: "2", number: 2, createdAt: .now, source: .flash, message: nil, contentHash: "")
        #expect(status(.done(revision: revision, saveError: nil)) == .flashed(revision: "revision 2"))
        #expect(status(.done(revision: nil, saveError: .io("disk full"))) == .flashedNotSaved, "the capsule keeps the failure")
        #expect(status(.failed(.flashingElsewhere)) == nil, "the capsule says which window is flashing instead")
        #expect(Status.verifying.look.progress == .indeterminate, "reconnecting has no percentage")
    }

    @Test func theKeyboardMapsToTheCapsule() {
        typealias Status = ActivityState.Status
        let keyboard = KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")
        let date = Date(timeIntervalSince1970: 0)
        func status(_ connection: LiveSession.Connection, _ match: FirmwareMatch?) -> Status {
            Status(connection, match: match, serial: keyboard.serial, edits: 3, revisionDate: date)
        }
        #expect(status(.noKeyboard, nil) == .noKeyboard)
        #expect(status(.connected(keyboard), .current) == .onKeyboard(revisionDate: date))
        #expect(status(.connected(keyboard), .thisLayout) == .notOnKeyboard(edits: 3))
        #expect(status(.liveOff(keyboard), .otherLayout) == .otherLayout(serial: "KlgM7/40xJ7M"), "the USB serial still works")
        #expect(status(.heldByAnotherApp(keyboard), .current) == .heldByAnotherApp("Keymapp"))
        #expect(status(.bootloader(BootloaderDevice(id: 9, productID: 0x0791, kind: .stm32, version: 1)), nil) == .inFlashMode)
        #expect(ActivityState.Device(.connected(keyboard), serial: "x", match: nil) == .connected(serial: "x", matchesLayout: false))
        #expect(ActivityState.Device(.connected(keyboard), serial: "x", match: .thisLayout) == .connected(serial: "x", matchesLayout: true))
        #expect(
            Status(.connected(keyboard), match: nil, serial: "x", edits: nil, revisionDate: nil, layoutOpen: false) == .keyboardConnected)
        #expect(
            ActivityState.Device(.connected(keyboard), serial: "x", match: nil, layoutOpen: false)
                == .connected(serial: "x", matchesLayout: true))
    }

    @Test func sheetStepsTitlesAndAnnouncements() {
        #expect(BuildFlashText.step(.compiling(file: "", done: 0, total: 1)) == 1)
        #expect(BuildFlashText.step(.waitingForFlashMode(stillWaiting: true)) == 2)
        #expect(BuildFlashText.step(.failed(.flash(.deviceBusy))) == 3)
        #expect(BuildFlashText.step(.failed(.flash(.hardwareAccessOff))) == 2, "flashing off never reaches flash mode")
        #expect(BuildFlashText.step(.failed(.notReconnected)) == 4)
        #expect(BuildFlashText.title(.failed(.toolchain(.tooLarge(overBy: 3_214)))) == "Firmware is 3,214 bytes too large")
        #expect(BuildFlashText.title(.failed(.flash(.imageRejected(.missingSuffix)))) == "Sextant won’t flash this image")
        #expect(BuildFlashText.title(.failed(.setup(.failed("offline")))) == "Couldn’t set up the build tools")
        let say = BuildFlashText.announcement
        #expect(say(.writing(done: 20, total: 100), .writing(done: 30, total: 100)) == "Flashing, 25 percent")
        #expect(say(.writing(done: 30, total: 100), .writing(done: 40, total: 100)) == nil, "once per quarter")
        #expect(say(.writing(done: 70, total: 100), .writing(done: 100, total: 100)) == nil, "done says Flashed instead")
        #expect(say(.linking, .built) == "Build succeeded")
        #expect(BuildFlashText.details(.flash(.dfuError(status: 10, address: 0x0800_2000))) == "DFU status 10 at 0x08002000")
    }
}

// MARK: - Fakes

/// Presence as the real watcher reports it: devices already present first, then changes.
private final class Watcher: DeviceWatcher {
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

    func detach(_ id: UInt64) {
        state.withLock { s in
            s.present.removeAll { $0.id == id }
            s.subscribers.forEach { $0.yield(.detached(id: id)) }
        }
    }
}

/// A live link whose newest session the test drives.
private final class Link: KeyboardLink {
    private let open = Mutex<[AsyncStream<LiveEvent>.Continuation]>([])

    var sessions: Int { open.withLock { $0.count } }

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

private struct Generator: FirmwareGenerator {
    func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        GeneratedSource(files: [:], sourceMap: [:])
    }
}

/// A build that succeeds at once, reporting 65,786 bytes, with an image that passes validation for an STM32 bootloader.
private struct Builds: Toolchain {
    func status() async -> ToolchainStatus { .ready("test") }
    func setUp() -> AsyncStream<SetupEvent> { AsyncStream { $0.finish() } }
    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        var payload = Data(count: 64)
        payload.replaceSubrange(0..<8, with: [0x00, 0x80, 0x00, 0x20, 0x01, 0x21, 0x00, 0x08])  // stack in RAM, odd reset vector
        let image = FirmwareImage.withSuffix(payload, vendorID: 0x3297, productID: 0x0791).data
        return AsyncStream { continuation in
            continuation.yield(.output("Compiling keymap.c"))
            continuation.yield(.finished(BuildArtifact(image: image, usedBytes: 65_786, log: [])))
            continuation.finish()
        }
    }
}

/// Needs the one-time setup, whose download holds at half until stopped.
private struct HeldSetup: Toolchain {
    func status() async -> ToolchainStatus { .needsSetup("test") }
    func setUp() -> AsyncStream<SetupEvent> { AsyncStream { $0.yield(.downloading(received: 5, total: 10)) } }
    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> { AsyncStream { $0.finish() } }
}

/// A build that fails with `diagnostics`.
private struct FailingBuild: Toolchain {
    var diagnostics: [Diagnostic]
    func status() async -> ToolchainStatus { .ready("test") }
    func setUp() -> AsyncStream<SetupEvent> { AsyncStream { $0.finish() } }
    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        AsyncStream { continuation in
            continuation.yield(.failed(.compileFailed(diagnostics)))
            continuation.finish()
        }
    }
}

/// Reports a write step, then holds until released.
private final class HoldingFlasher: Flasher {
    private let (gate, opener) = AsyncStream.makeStream(of: Void.self)

    func release() { opener.yield() }

    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) {
        progress(FlashProgress(phase: .writing, done: 1, total: 2))
        for await _ in gate { break }
    }
}

/// Polls `condition`, letting other tasks run, for up to about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
