import Clocks
import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

/// Quitting (spec §7.4) never cuts off a firmware write or its verify, and never leaves an edit unsaved: an edit made
/// while it waits for a write is flushed after the write too.
@MainActor
struct QuittingTests {
    let store = InMemoryLibrary()
    let watcher = FakeDeviceWatcher()
    let clock = TestClock()

    /// A run waiting for flash mode starts writing while the quit's flush awaits the disk, and the user edits during the
    /// write. The quit waits through the write and the verify, then writes that edit.
    @Test func flushesAgainAfterAWriteThatStartedDuringTheFlush() async throws {
        let live = LiveSession(watcher: watcher, link: FakeKeyboardLink(), clock: TestClock()) { false }
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        // Only a flush saves: the autosave waits a minute.
        let document = try await library.open(entry.id, autosaveDelay: .seconds(60))
        let flasher = FakeFlasher(holds: true)
        let session = BuildFlashSession(
            session: document, library: store, generator: FakeGenerator(), toolchain: FakeToolchain(), watcher: watcher,
            flasher: flasher, md5: { _ in "d41d8cd9" }, clock: clock, issues: { _ in [] }, live: live)
        session.buildAndFlash(connectedKeyboard: .voyager(serial: "KlgM7/40xJ7M"))
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) && watcher.subscriberCount == 1 })
        document.setCode("KC_F1", layer: 0, index: 1)

        var flushes = 0
        let flush: @MainActor () async -> Bool = {
            flushes += 1
            let saved = await library.flushOpenSessions()
            if flushes == 1 {
                // The keyboard enters flash mode while the flush awaits the disk.
                watcher.attach(.bootloader(.stm32()))
                _ = await eventually {
                    await clock.advance(by: .milliseconds(100))
                    return live.isWritingFirmware
                }
            }
            return saved
        }
        var pauses = 0
        let pause: @MainActor () async -> Void = {
            pauses += 1
            guard pauses == 1 else { return await Task.yield() }
            // An edit during the write, then the write, the verify and the record of the flash.
            document.setCode("KC_F2", layer: 0, index: 1)
            flasher.release()
            _ = await eventually { session.phase == .verifying }
            watcher.detach(9)
            watcher.attach(.keyboard(.voyager(id: 2, serial: "KlgM7/40xJ7M")))
            _ = await eventually { if case .done = session.phase { true } else { false } }
        }
        let quitting = Quitting(flush: flush, isWriting: { live.isWritingFirmware }, pause: pause)
        let quits = await quitting.run {
            Issue.record("every edit was saved")
            return true
        }
        #expect(quits && flushes == 2 && pauses >= 1 && !live.isWritingFirmware)
        let stored = try await store.load(entry.id)
        #expect(stored.layout.key(layer: 0, index: 1)?.tap?.code == "KC_F2", "the edit made during the write")
        #expect(stored.revisions.last?.source == .flash)
    }

    /// With nothing being written, one flush; an edit that can't be saved asks first.
    @Test func flushesOnceAndAsksWhenAnEditCantBeSaved() async {
        var flushes = 0
        let saving = Quitting(
            flush: {
                flushes += 1
                return true
            }, isWriting: { false }, pause: {})
        #expect(
            await saving.run {
                Issue.record("saved"); return true
            })
        #expect(flushes == 1)
        let failing = Quitting(flush: { false }, isWriting: { false }, pause: {})
        var asked = 0
        #expect(
            await !failing.run {
                asked += 1; return false
            })
        #expect(
            await failing.run {
                asked += 1; return true
            })
        #expect(asked == 2)
    }

    /// Each flush starting another write ends after a few rounds, on a wait: no write is cut off, and the quit ends. A
    /// failed save after a write asks once.
    @Test func roundsAreBoundedAndEndOnAWait() async {
        var writing = false
        var flushes = 0
        let quitting = Quitting(
            flush: {
                flushes += 1
                writing = true
                return true
            }, isWriting: { writing }, pause: { writing = false })
        #expect(
            await quitting.run {
                Issue.record("saved"); return true
            })
        #expect(flushes == 1 + Quitting.rounds && !writing)

        var asked = 0
        flushes = 0
        let failing = Quitting(
            flush: {
                flushes += 1
                writing = true
                return flushes == 1
            }, isWriting: { writing }, pause: { writing = false })
        #expect(
            await !failing.run {
                asked += 1; return false
            })
        #expect(asked == 1 && flushes == 2)
    }
}
