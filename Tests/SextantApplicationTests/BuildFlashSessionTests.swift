import Clocks
import Foundation
import SextantApplication
import SextantDomain
import Testing

@MainActor
struct BuildFlashSessionTests {
    let store = InMemoryLibrary()
    let watcher = FakeDeviceWatcher()
    let clock = TestClock()

    func make(
        generator: FakeGenerator = FakeGenerator(), toolchain: FakeToolchain = FakeToolchain(), flasher: FakeFlasher = FakeFlasher(),
        issues: @escaping @Sendable (KeyboardLayout) -> [LayoutIssue] = { _ in [] }
    ) async throws -> (BuildFlashSession, EditSession) {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let document = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let session = BuildFlashSession(
            session: document, library: store, generator: generator, toolchain: toolchain, watcher: watcher, flasher: flasher,
            md5: { _ in "d41d8cd9" }, clock: clock, issues: issues)
        return (session, document)
    }

    /// Waits for the flash-mode step, connects `devices` in flash mode, and lets the choice settle.
    func enterFlashMode(_ session: BuildFlashSession, _ devices: BootloaderDevice...) async -> Bool {
        guard await eventually({ session.phase == .waitingForFlashMode(stillWaiting: false) && watcher.subscriberCount == 1 })
        else { return false }
        for device in devices.isEmpty ? [.stm32()] : devices { watcher.attach(.bootloader(device)) }
        return await eventually {
            await clock.advance(by: .milliseconds(100))
            return session.phase != .waitingForFlashMode(stillWaiting: false)
        }
    }

    func isDone(_ session: BuildFlashSession) -> Bool { if case .done = session.phase { true } else { false } }

    // MARK: Happy paths

    @Test func buildsFlashesVerifiesAndRecordsARevision() async throws {
        let generator = FakeGenerator(), flasher = FakeFlasher()
        let (session, document) = try await make(generator: generator, flasher: flasher)
        session.buildAndFlash(connectedKeyboard: .voyager(serial: "KlgM7/40xJ7M"))
        #expect(await enterFlashMode(session))
        #expect(generator.lastIdentity?.serial == "KlgM7/40xJ7M", "an unchanged import keeps Oryx's serial")
        #expect(session.log == ["Compiling keymap.c"])
        #expect(await eventually { session.phase == .verifying })
        #expect(flasher.calls.map(\.md5) == ["d41d8cd9"] && flasher.calls.first?.device == .stm32())
        #expect(!session.canStop)
        watcher.detach(9)
        watcher.attach(.keyboard(.voyager(id: 2, serial: "KlgM7/40xJ7M")))
        #expect(await eventually { isDone(session) })
        guard case let .done(revision?, nil) = session.phase else {
            Issue.record("\(session.phase)")
            return
        }
        #expect(revision.source == .flash && revision.message?.hasPrefix("Flashed ") == true)
        #expect(document.revisions.last == revision)
    }

    @Test func buildOnlyMeasuresAgainstTheFlashWindowAndCanFlashLater() async throws {
        let toolchain = FakeToolchain()
        let warning = LayoutIssue(kind: .unreachableLayer(3), severity: .warning, key: nil)
        let (session, _) = try await make(toolchain: toolchain, issues: { _ in [warning] })
        session.build()
        #expect(await eventually { session.phase == .built }, "warnings don't block")
        #expect(session.usedBytes == 65_786 && session.capacity == 0x4_0000)
        #expect(watcher.subscriberCount == 0, "a build alone never looks for flash mode")
        session.flash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session))
        #expect(toolchain.buildCount == 1, "flashing a build doesn't rebuild it")
    }

    @Test func anEditedLayoutGetsASextantSerialAndTheRevisionHoldsWhatWasFlashed() async throws {
        let generator = FakeGenerator()
        let (session, document) = try await make(generator: generator)
        document.setCode("KC_F13", layer: 0, index: 1)
        let built = document.layout
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session))
        let serial = try #require(generator.lastIdentity?.serial)
        #expect(serial.hasPrefix("sx-"))
        document.setCode("KC_F14", layer: 0, index: 1)
        #expect(await eventually { session.phase == .verifying })
        watcher.attach(.keyboard(.voyager(id: 2, serial: serial)))
        #expect(await eventually { isDone(session) })
        guard case let .done(revision?, nil) = session.phase else {
            Issue.record("\(session.phase)")
            return
        }
        #expect(try await store.layout(ofRevision: revision.id, in: document.id) == built, "not the later edit")
    }

    // MARK: Before building

    @Test func liveIssueErrorsBlockTheBuild() async throws {
        let error = LayoutIssue(kind: .unknownKeycode("KC_LBRACKETT"), severity: .error, key: FakeGenerator.mappedKey)
        let warning = LayoutIssue(kind: .unreachableLayer(3), severity: .warning, key: nil)
        let toolchain = FakeToolchain()
        let (session, _) = try await make(toolchain: toolchain, issues: { _ in [warning, error] })
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { session.phase == .blocked([error]) })
        #expect(toolchain.buildCount == 0)
    }

    @Test func confirmsBeforeReplacingAnotherLayout() async throws {
        let toolchain = FakeToolchain()
        let (session, document) = try await make(toolchain: toolchain)
        var other = document.layout
        other.title = "Writing (Colemak)"
        _ = try await store.create(other, origin: .oryx(layoutId: "Q9x2", revisionId: "aa11"), firstRevision: nil)
        session.buildAndFlash(connectedKeyboard: .voyager(serial: "Q9x2/aa11"))
        #expect(await eventually { session.phase == .confirmingReplace(serial: "Q9x2/aa11", title: "Writing (Colemak)") })
        #expect(toolchain.buildCount == 0, "the confirmation comes before the build")
        session.confirmReplace()
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) })
    }

    @Test func confirmsBeforeReplacingFirmwareWithNoSerial() async throws {
        let toolchain = FakeToolchain()
        let (session, _) = try await make(toolchain: toolchain)
        session.buildAndFlash(connectedKeyboard: .voyager(serial: nil))
        #expect(await eventually { session.phase == .confirmingReplace(serial: nil, title: nil) })
        #expect(toolchain.buildCount == 0)
    }

    @Test func asksForSetupBeforeTheFirstBuild() async throws {
        let toolchain = FakeToolchain(readiness: .needsSetup("About 1 GB"))
        let (session, _) = try await make(toolchain: toolchain)
        session.build()
        #expect(await eventually { session.phase == .needsSetup("About 1 GB") })
        #expect(toolchain.buildCount == 0)
    }

    // MARK: Build failures

    @Test func reportsGeneratorFailures() async throws {
        let failure = GeneratorError.unsupported("tap dance", FakeGenerator.mappedKey)
        let (session, _) = try await make(generator: FakeGenerator(error: failure))
        session.build()
        #expect(await eventually { session.phase == .failed(.generator(failure)) })
    }

    @Test func mapsCompileErrorsInKeymapCToTheirKeys() async throws {
        let inKeymap = Diagnostic(
            file: "/build/keyboards/zsa/voyager/keymaps/sextant/keymap.c", line: FakeGenerator.mappedLine, column: 5, severity: .error,
            message: "'KC_LBRACKETT' undeclared")
        let elsewhere = Diagnostic(file: "quantum/quantum.c", line: FakeGenerator.mappedLine, column: 1, severity: .error, message: "x")
        let toolchain = FakeToolchain(script: [
            .compiling(file: "keymap.c", done: 1, total: 41), .failed(.compileFailed([inKeymap, elsewhere])),
        ])
        let (session, _) = try await make(toolchain: toolchain)
        session.build()
        #expect(await eventually { !session.diagnostics.isEmpty })
        #expect(session.diagnostics.map(\.key) == [FakeGenerator.mappedKey, nil])
        #expect(session.artifact == nil)
        session.retry()
        #expect(await eventually { toolchain.buildCount == 2 }, "a failed build retries by rebuilding")
    }

    @Test func refusesFirmwareThatDoesNotFit() async throws {
        let (session, _) = try await make(toolchain: FakeToolchain(script: FakeToolchain.success(usedBytes: 0x4_0000 + 3_214)))
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { session.phase == .failed(.toolchain(.tooLarge(overBy: 3_214))) })
        #expect(watcher.subscriberCount == 0)
    }

    @Test func aBuildThatEndsWithoutAnImageFails() async throws {
        let (session, _) = try await make(toolchain: FakeToolchain(script: [.linking]))
        session.build()
        #expect(await eventually { if case .failed(.toolchain(.failed)) = session.phase { true } else { false } })
    }

    // MARK: Flash-mode refusals

    @Test func refusesMoreThanOneKeyboardInFlashMode() async throws {
        let flasher = FakeFlasher()
        let (session, _) = try await make(flasher: flasher)
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session, .stm32(id: 9), .gd32(id: 10)))
        #expect(session.phase == .failed(.multipleBootloaders))
        #expect(session.phase.error?.localizedDescription == "Connect only one keyboard in flash mode.")
        #expect(flasher.calls.isEmpty)
    }

    @Test func saysStillWaitingAfter45Seconds() async throws {
        let (session, _) = try await make()
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) })
        await clock.advance(by: .seconds(44))
        #expect(session.phase == .waitingForFlashMode(stillWaiting: false))
        #expect(
            await eventually {
                await clock.advance(by: .seconds(1))
                return session.phase == .waitingForFlashMode(stillWaiting: true)
            })
    }

    @Test func refusesAnImageThatFailsValidationWithNoOverride() async throws {
        let flasher = FakeFlasher()
        let (session, _) = try await make(
            toolchain: FakeToolchain(script: FakeToolchain.success(image: Images.valid(productID: 0x0791))), flasher: flasher)
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session, .gd32()))
        #expect(session.phase == .failed(.flash(.imageRejected(.wrongProduct(image: 0x0791, bootloader: 0x1791)))))
        #expect(session.phase.error?.localizedDescription.hasPrefix("Sextant won't flash this image: ") == true)
        #expect(flasher.calls.isEmpty)
    }

    // MARK: Flash and verify failures

    @Test func aFailedFlashRetriesWithTheSameBuild() async throws {
        let toolchain = FakeToolchain()
        let failure = FlashError.dfuError(status: 0x0A, address: 0x0800_2000)
        let (session, _) = try await make(toolchain: toolchain, flasher: FakeFlasher(error: failure))
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session))
        #expect(await eventually { session.phase == .failed(.flash(failure)) })
        watcher.detach(9)
        session.retry()
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) })
        #expect(toolchain.buildCount == 1)
    }

    @Test func failsWhenTheKeyboardComesBackWithAnotherSerial() async throws {
        let (session, _) = try await make()
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session))
        #expect(await eventually { session.phase == .verifying })
        watcher.attach(.keyboard(.voyager(id: 2, serial: "Q9x2/aa11")))
        #expect(await eventually { session.phase == .failed(.unexpectedSerial("Q9x2/aa11")) })
    }

    @Test func failsWhenTheKeyboardDoesNotComeBackWithin10Seconds() async throws {
        let (session, document) = try await make()
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session))
        #expect(await eventually { session.phase == .verifying })
        await clock.advance(by: .seconds(9))
        #expect(session.phase == .verifying)
        await clock.advance(by: .seconds(1))
        #expect(await eventually { session.phase == .failed(.notReconnected) })
        #expect(document.revisions.count == 1, "no flash revision without verification")
    }

    // MARK: Stop

    @Test func stopWorksWhileBuildingAndWaiting() async throws {
        let (building, _) = try await make(
            toolchain: FakeToolchain(script: [.compiling(file: "keymap.c", done: 1, total: 41)], hangs: true))
        building.build()
        #expect(await eventually { building.phase == .compiling(file: "keymap.c", done: 1, total: 41) })
        #expect(building.canStop)
        building.stop()
        #expect(building.phase == .idle)

        let (waiting, _) = try await make()
        waiting.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { waiting.phase == .waitingForFlashMode(stillWaiting: false) && watcher.subscriberCount == 1 })
        waiting.stop()
        #expect(waiting.phase == .idle)
        #expect(await eventually { watcher.subscriberCount == 0 }, "stops watching for flash mode")
    }

    @Test func stopBeforeTheRunStartsNeverBuilds() async throws {
        let toolchain = FakeToolchain()
        let (session, _) = try await make(toolchain: toolchain)
        session.buildAndFlash(connectedKeyboard: nil)
        session.stop()
        try await Task.sleep(for: .milliseconds(100))  // let the cancelled run reach the toolchain, if it would
        #expect(toolchain.buildCount == 0 && session.phase == .idle)
    }

    /// Checks the whole "Stop never flashes" rule: TestClock can't hit the exact moment a `.settled` is buffered
    /// when Stop lands, so this doesn't pin the guard in the flash loop on its own.
    @Test func stopWhileABootloaderSettlesNeverFlashes() async throws {
        let flasher = FakeFlasher()
        let (session, _) = try await make(flasher: flasher)
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) && watcher.subscriberCount == 1 })
        watcher.attach(.bootloader(.stm32()))
        try await Task.sleep(for: .milliseconds(20))  // the loop sees it and starts the settle timer
        session.stop()
        await clock.advance(by: .seconds(1))
        #expect(flasher.calls.isEmpty && session.phase == .idle)
    }

    @Test func stopIsRefusedWhileWriting() async throws {
        let flasher = FakeFlasher(holds: true)
        let (session, _) = try await make(flasher: flasher)
        session.buildAndFlash(connectedKeyboard: nil)
        #expect(await enterFlashMode(session))
        #expect(await eventually { session.phase == .erasing(done: 1, total: 2) })
        #expect(!session.canStop)
        session.stop()
        #expect(session.phase == .erasing(done: 1, total: 2))
        flasher.release()
        #expect(await eventually { session.phase == .verifying })
    }
}

extension BuildFlashSession.Phase {
    var error: BuildFlashError? { if case let .failed(e) = self { e } else { nil } }
}
