import Clocks
import Foundation
import SextantApplication
import SextantDomain
import Testing

/// One Build & Flash at a time waits for flash mode and writes, app-wide (spec §7.6).
@MainActor
struct FlashModeClaimTests {
    @Test func aSecondLayoutIsTurnedAwayUntilTheFirstLetsGo() async throws {
        let store = InMemoryLibrary()
        let library = Library(store: store)
        let watcher = FakeDeviceWatcher()
        let live = LiveSession(watcher: FakeDeviceWatcher(), link: FakeKeyboardLink(), secureInputProbe: { false })
        func make() async throws -> BuildFlashSession {
            let document = try await library.open(try await library.importOryxJSON(Fixtures.userLayoutData).id)
            return BuildFlashSession(
                session: document, library: store, generator: FakeGenerator(), toolchain: FakeToolchain(), watcher: watcher,
                flasher: FakeFlasher(), md5: { _ in "" }, clock: TestClock(), live: live)
        }
        let first = try await make()
        let second = try await make()
        first.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { first.phase == .waitingForFlashMode(stillWaiting: false) })
        #expect(live.flashingLayoutID != nil)
        second.buildAndFlash(connectedKeyboard: nil)
        #expect(await eventually { second.phase == .failed(.flashingElsewhere) }, "it never waits for flash mode")
        first.stop()
        #expect(await eventually { live.flashingLayoutID == nil }, "Stop lets go")
        second.retry()
        #expect(await eventually { second.phase == .waitingForFlashMode(stillWaiting: false) })
    }
}
