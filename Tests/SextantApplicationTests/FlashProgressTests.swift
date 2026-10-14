import Clocks
import Foundation
import SextantApplication
import SextantDomain
import Testing

extension BuildFlashSessionTests {
    /// `LiveSession.flashProgress` fills the menu bar's arc (ADR 0049): nil until the write starts, then erasing as the
    /// first half and writing as the second in 5% steps, and nil again once the flash is verified and recorded.
    @Test func flashProgressCoversTheWriteInFivePercentSteps() async throws {
        let live = LiveSession(watcher: watcher, link: FakeKeyboardLink(), clock: TestClock()) { false }
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let document = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let flasher = SteppedFlasher()
        let session = BuildFlashSession(
            session: document, library: store, generator: FakeGenerator(), toolchain: FakeToolchain(), watcher: watcher,
            flasher: flasher, md5: { _ in "d41d8cd9" }, clock: clock, issues: { _ in [] }, live: live)
        session.buildAndFlash(connectedKeyboard: .voyager(serial: "KlgM7/40xJ7M"))
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) && watcher.subscriberCount == 1 })
        #expect(live.flashProgress == nil, "nothing is written while waiting for flash mode")
        watcher.attach(.bootloader(.stm32()))
        // Erased 33 of 33 pages, then 41,984 of 65,786 bytes written: half, plus 32% of the other half, down to 80%.
        #expect(
            await eventually {
                await clock.advance(by: .milliseconds(100))
                return session.phase == .writing(done: 41_984, total: 65_786)
            })
        #expect(live.flashProgress == 0.8)
        flasher.release()
        #expect(await eventually { session.phase == .verifying })
        #expect(live.flashProgress == 1, "verifying keeps the full arc")
        watcher.detach(9)
        watcher.attach(.keyboard(.voyager(id: 2, serial: "KlgM7/40xJ7M")))
        #expect(await eventually { isDone(session) })
        #expect(live.flashProgress == nil)
    }
}

/// Reports a whole erase and part of the write, holds until released, then finishes the write.
private final class SteppedFlasher: Flasher {
    private let (gate, opener) = AsyncStream.makeStream(of: Void.self)

    func release() { opener.yield() }

    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) {
        progress(FlashProgress(phase: .erasing, done: 33, total: 33))
        progress(FlashProgress(phase: .writing, done: 41_984, total: 65_786))
        for await _ in gate { break }
        progress(FlashProgress(phase: .writing, done: 65_786, total: 65_786))
        progress(FlashProgress(phase: .leaving, done: 0, total: 1))
    }
}
