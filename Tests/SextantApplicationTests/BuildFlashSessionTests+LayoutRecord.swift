import Foundation
import SextantApplication
import SextantDomain
import Testing

/// The layout a build stores in the firmware, so Sextant on the user's other Macs can read it back (ADR 0061).
extension BuildFlashSessionTests {
    @Test func aBuildStoresTheLayoutWithItsIdsOnEveryMac() async throws {
        let generator = FakeGenerator()
        let (session, document) = try await make(generator: generator)
        let (first, second) = (UUID(), UUID())
        // Linked since the window opened: read at the build.
        try await store.link(document.id, to: [second, first, document.id])
        session.build()
        #expect(await eventually { session.phase == .built })
        let identity = try #require(generator.lastIdentity)
        let ids = [document.id] + [first, second].sorted { $0.uuidString < $1.uuidString }
        #expect(identity.record == LayoutRecord(layout: document.layout, libraryIDs: ids), "its own id first, then its aliases")
        #expect(identity.serial == "KlgM7/40xJ7M", "the serial doesn't change")
    }

    @Test func storingTheLayoutCanBeTurnedOff() async throws {
        let generator = FakeGenerator()
        let (session, _) = try await make(generator: generator, storesLayoutRecord: { false })
        session.build()
        #expect(await eventually { session.phase == .built })
        #expect(generator.lastIdentity?.record == nil)
        #expect(generator.lastIdentity?.serial == "KlgM7/40xJ7M")
    }

    @Test func aRecordTooLargeToStoreBuildsWithoutOne() async throws {
        let generator = FakeGenerator()
        let (session, document) = try await make(generator: generator)
        // Random text barely compresses: far over the 32 KiB a record may take.
        document.setTitle((0..<3000).map { _ in UUID().uuidString }.joined())
        session.build()
        #expect(await eventually { session.phase == .built }, "the build goes on")
        #expect(generator.lastIdentity?.record == nil)
        #expect(generator.lastIdentity?.serial.hasPrefix("sx-") == true)
    }

    /// The other Mac's build of the same content is this layout as it is now: no "Replace the layout on this keyboard?".
    @Test func aBuildOfThisLayoutFromAnotherMacIsntAnotherLayout() async throws {
        let (session, document) = try await make()
        document.setCode("KC_F13", layer: 0, index: 1)
        let otherMac = UUID()
        let fromOtherMac = FirmwareIdentity(layout: document.layout, libraryID: otherMac, importedLayout: nil).serial
        session.buildAndFlash(connectedKeyboard: .voyager(serial: fromOtherMac))
        #expect(await eventually { if case .confirmingReplace = session.phase { true } else { false } }, "unlinked, another layout")
        session.stop()

        try await store.link(document.id, to: [otherMac])
        session.buildAndFlash(connectedKeyboard: .voyager(serial: fromOtherMac))
        #expect(await eventually { session.phase == .waitingForFlashMode(stillWaiting: false) }, "linked: no question")
        session.stop()
    }
}
