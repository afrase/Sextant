import Foundation
import SextantApplication
import SextantDomain
import Testing

/// Firmware settings edits (spec §8.8): a coupled change and Reset All are one undo step each.
@MainActor
struct EditSessionSettingsTests {
    let store = InMemoryLibrary()

    func open() async throws -> (EditSession, UndoManager) {
        let library = Library(store: store)
        let entry = try await library.importOryxJSON(Fixtures.data("my-layout-KlgM7-full.json"))
        let session = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        return (session, undo)
    }

    func step(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test func aCoupledChangeIsOneUndoStep() async throws {
        let (session, undo) = try await open()
        step(undo) { session.setSetting("chordalHold", to: .bool(true)) }
        #expect(session.layout.settings["chordalHoldExcludeThumbs"] == .bool(true))
        step(undo) { session.setSetting("tappingTerm", to: .number(600)) }
        #expect(session.layout.settings["permissiveHold"] == .bool(true))
        undo.undo()
        #expect(session.layout.settings["tappingTerm"] == nil && session.layout.settings["permissiveHold"] == nil)
        undo.undo()
        #expect(session.layout.settings["chordalHold"] == nil && session.layout.settings["chordalHoldExcludeThumbs"] == nil)
    }

    /// Reset All puts back every offered setting, Navigator options included, in one named step.
    @Test func resetAllIsOneUndoStep() async throws {
        let (session, undo) = try await open()
        step(undo) { session.setSetting("tappingTerm", to: .number(180)) }
        step(undo) { session.setSetting("autoshift", to: .bool(true)) }
        step(undo) { session.setSetting("automouseTime", to: .number(800)) }
        step(undo) { session.setSetting("disabledAnimations", to: .strings(["breathing"])) }
        let edited = session.layout
        #expect(session.layout.changedSettings().count == 4)

        step(undo) { session.resetSettings() }
        #expect(undo.undoActionName == "Reset Firmware Settings")
        #expect(session.layout.changedSettings().isEmpty && session.layout.navigator?.options["automouseTime"] == nil)
        #expect(session.layout.navigator?.options["tap"] == .bool(true), "Navigator values outside the catalog stay")
        undo.undo()
        #expect(session.layout == edited)
    }

    /// Imported values of settings Sextant doesn't offer outlast Reset All (ADR 0040).
    @Test func resetAllKeepsSettingsSextantDoesntOffer() async throws {
        let library = Library(store: store)
        var layout = try KeyboardLayout(oryxJSON: Fixtures.data("my-layout-KlgM7-full.json"))
        layout.settings["liveTraining"] = .bool(false)
        layout.settings["german"] = .bool(true)
        layout.settings["debounce"] = .number(8)
        let entry = try #require(await library.create(layout))
        let session = try await library.open(entry.id, autosaveDelay: .milliseconds(1))
        session.resetSettings()
        #expect(session.layout.settings["debounce"] == nil)
        #expect(session.layout.settings["liveTraining"] == .bool(false) && session.layout.settings["german"] == .bool(true))
    }
}
