import AppKit
import SextantApplication
import SextantDomain
import SwiftUI
import Testing

@testable import SextantUI

/// What the device card, the Device popover, the menu bar and the layout window offer when the keyboard runs a layout
/// Sextant doesn't have (ADR 0061). The keyboard is a stand-in, and nothing here reads from it.
@MainActor
struct KeyboardLayoutPromptTests {
    private let serial = "sx-C57FDF8B-9084DE1F"
    private let suite = "sextant-keyboard-layout-\(UUID().uuidString)"

    @Test func thePromptFollowsThePullOnlyForALayoutSextantDoesntHave() {
        #expect(KeyboardLayoutPrompt(.idle, serial: serial, runsKnownLayout: false) == .notInLibrary(serial: serial))
        #expect(KeyboardLayoutPrompt(.reading(0.25), serial: serial, runsKnownLayout: false) == .reading(0.25))
        #expect(KeyboardLayoutPrompt(.noRecord, serial: serial, runsKnownLayout: false) == .noRecord)
        #expect(
            KeyboardLayoutPrompt(.failed(.mismatch), serial: serial, runsKnownLayout: false)
                == .failed(PullFailure.mismatch.localizedDescription))
        #expect(KeyboardLayoutPrompt(.idle, serial: nil, runsKnownLayout: false) == nil, "no keyboard, or one in flash mode")
        #expect(KeyboardLayoutPrompt(.noRecord, serial: serial, runsKnownLayout: true) == nil, "Sextant has the layout")
    }

    /// The window over the app's pull: the keyboard is plugged in with Live View off, and nothing is read until Get Layout.
    @Test func theWindowOffersGetLayoutWithoutReadingAnything() async throws {
        let fake = StandInKeyboard(serial: serial, events: [])
        let (live, onKeyboard, library, pull) = Self.session(fake)
        let model = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard, keyboardLayout: pull)
        #expect(await eventually { live.firmwareSerial == serial && onKeyboard.resolvedSerial == serial })
        #expect(model.keyboardLayoutPrompt == .notInLibrary(serial: serial))
        let panel = MenuBarPanelState(
            live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil, keyboardLayout: pull)
        #expect(panel.keyboard == .liveOff && panel.keyboardLayout == .notInLibrary(serial: serial))
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.sessions == 0 && fake.commands.isEmpty, "showing the prompt pairs with nothing")

        // Without the app's pull (tests, snapshots), a fixed value.
        let plain = LayoutWindowModel(library: library, live: live)
        #expect(plain.keyboardLayoutPrompt == nil)
        plain.keyboardLayoutPrompt = .noRecord
        #expect(plain.keyboardLayoutPrompt == .noRecord)
    }

    @Test func aLayoutInTheLibraryGetsNoPrompt() async throws {
        let fake = StandInKeyboard(serial: "KlgM7/40xJ7M", events: [])
        let (live, onKeyboard, library, pull) = Self.session(fake)
        _ = try await library.importOryxJSON(#require(userLayoutData))
        #expect(await eventually { onKeyboard.running != nil })
        let model = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard, keyboardLayout: pull)
        #expect(model.keyboardLayoutPrompt == nil)
        let panel = MenuBarPanelState(
            live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil, keyboardLayout: pull)
        #expect(panel.keyboardLayout == nil)
    }

    /// Nothing is offered while the serial is still being looked up: a layout the library has would otherwise read as
    /// "not in your library" for a moment on every connect.
    @Test func nothingIsOfferedUntilTheSerialIsLookedUp() async throws {
        let fake = StandInKeyboard(serial: serial, events: [])
        let (live, onKeyboard, library, pull) = Self.session(fake, looksUp: false)
        let model = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard, keyboardLayout: pull)
        #expect(await eventually { live.firmwareSerial == serial })
        #expect(onKeyboard.resolvedSerial == nil && model.keyboardLayoutPrompt == nil)
        let panel = MenuBarPanelState(
            live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil, keyboardLayout: pull)
        #expect(panel.keyboardLayout == nil)

        onKeyboard.start()
        #expect(await eventually { onKeyboard.resolvedSerial == serial })
        #expect(model.keyboardLayoutPrompt == .notInLibrary(serial: serial), "looked up, and not in the library")
    }

    /// Oryx's build of a revision the library lacks, of an Oryx layout it has: as before Sextant read layouts back, nothing
    /// is offered. Oryx's build stores no layout, and Import from Oryx brings in the revision (spec §3.6).
    @Test func anotherRevisionOfAnOryxLayoutInTheLibraryGetsNoPrompt() async throws {
        let newer = "KlgM7/Zq9xR2"
        let fake = StandInKeyboard(serial: newer, events: [])
        let (live, onKeyboard, library, pull) = Self.session(fake)
        _ = try await library.importOryxJSON(#require(userLayoutData))
        #expect(await eventually { onKeyboard.resolvedSerial == newer && !library.entries.isEmpty })
        #expect(onKeyboard.running == nil, "the library doesn't have that revision")
        let model = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard, keyboardLayout: pull)
        #expect(model.keyboardLayoutPrompt == nil && model.unknownOryxSerial == nil)
        let panel = MenuBarPanelState(
            live: live, onKeyboard: onKeyboard, shortcuts: nil, library: library, buildTarget: nil, keyboardLayout: pull)
        #expect(panel.keyboardLayout == nil)
    }

    /// Add to Library… from the menu bar works with no window open: the Dock icon comes back, then the window opens.
    @Test func addToLibraryOpensItsWindowFromTheMenuBarAlone() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SettingsKey.keepsInMenuBar)
        let presence = AppPresence(defaults: defaults, apply: { _ in })
        presence.windowOpened()
        presence.windowClosed()
        #expect(presence.policy == .accessory, "only in the menu bar")

        let fake = StandInKeyboard(serial: serial, events: [])
        let (live, onKeyboard, library, pull) = Self.session(fake)
        var activations = 0
        let router = WindowRouter(
            library: library, onKeyboard: onKeyboard, live: live, presence: presence, activate: { activations += 1 })
        var opened = 0
        let actions = MenuBarActions(
            live: live, onKeyboard: onKeyboard, windows: router, openWindow: { _ in }, openSettings: {}, keyboardLayout: pull,
            openKeyboardLayout: { opened += 1 })
        actions.addKeyboardLayout()
        #expect(opened == 1 && activations == 1 && presence.policy == .regular)
        #expect(fake.sessions == 0, "opening the window reads nothing")
    }

    /// Spec §13.3: the panel stays under 520 pt with the prompt in each state.
    @Test func thePanelWithThePromptStaysUnder520Points() {
        let note = "Sextant doesn’t have the keyboard’s layout, so it can move it only to layer 0."
        let failure = PullFailure.keyboard(.timedOut).localizedDescription
        let states = [
            MenuBarPanelState(keyboard: .liveOff, running: serial, keyboardLayout: .notInLibrary(serial: serial)),
            MenuBarPanelState(keyboard: .connecting, running: serial, layerNote: note, keyboardLayout: .reading(0.5)),
            MenuBarPanelState(keyboard: .live, running: serial, layer: 0, layerNote: note, keyboardLayout: .noRecord),
            MenuBarPanelState(keyboard: .live, running: serial, layer: 0, layerNote: note, keyboardLayout: .found(title: "Work")),
            MenuBarPanelState(keyboard: .live, running: serial, layer: 0, layerNote: note, keyboardLayout: .failed(failure)),
        ]
        let typing = TypingStats(today: 12_408, wordsPerMinute: 0)
        for state in states {
            let size = NSHostingView(rootView: MenuBarPanelContent(state: state, typingStats: typing)).fittingSize
            #expect(size.width == 360)
            #expect(size.height < 520, "\(String(describing: state.keyboardLayout)): \(size.height) pt")
        }
    }

    // MARK: Use It

    @Test func theCapsuleSaysWhichRevisionTheKeyboardRuns() {
        let look = ActivityState.Status.keyboardRunsRevision(number: 7).look
        #expect(look == ActivityLook(symbol: "arrow.down.circle", tone: .warning, text: "Keyboard runs revision 7"))
        #expect(!ActivityState(device: .connected(serial: serial, matchesLayout: true), status: .keyboardRunsRevision(number: 7)).isBusy)
    }

    /// Use It is offered only when it would change the working copy: for its title, which Use It takes from the keyboard
    /// since it is part of the fingerprint, but not for its macro drafts, which Use It keeps.
    @Test func useItCountsTheTitleButNotMacroDrafts() throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        var renamed = layout
        renamed.title = "From the other Mac"
        #expect(LayoutWindowModel.differs(layout, from: renamed), "Use It takes the keyboard's title")
        var drafted = layout
        drafted.macroDrafts = [MacroDraft(macro: Macro(steps: [MacroStep(code: "KC_A")]))]
        #expect(!LayoutWindowModel.differs(drafted, from: layout), "drafts never reach the keyboard")
        var edited = layout
        edited.layers[0].keys[0] = Key("KC_F13")
        #expect(LayoutWindowModel.differs(edited, from: layout))
    }

    /// The other Mac flashed the layout under another title. Live View reads it into History, and Use It makes the working
    /// copy exactly that, title included, so it reads as on the keyboard. Then the offer ends: later edits don't bring it
    /// back. The keyboard is a stand-in that answers reads as a Sextant build would.
    @Test func useItTakesTheKeyboardsLayoutAndTheOfferEnds() async throws {
        let id = UUID()
        var mine = KeyboardLayout.blankQWERTY(title: "Travel")
        mine.updateKey(layer: 0, index: 1) { $0 = Key("KC_F14") }
        var keyboard = mine
        keyboard.title = "Travel at home"
        keyboard.updateKey(layer: 0, index: 1) { $0 = Key("KC_F13") }
        let running = FirmwareIdentity(layout: keyboard, libraryID: id, importedLayout: nil).serial
        let fake = RecordKeyboard(serial: running, record: try LayoutRecord(layout: keyboard, libraryIDs: [id]).encoded())
        // Only saved here, never flashed or imported: the keyboard's layout goes to History, not into the working copy.
        let store = OneLayoutLibrary(mine, id: id)
        let live = LiveSession(watcher: fake, link: fake, secureInputProbe: { false })
        let library = Library(store: store)
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        let pull = KeyboardLayoutPull(live: live, onKeyboard: onKeyboard, library: library, store: store)
        let model = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard, keyboardLayout: pull)
        await model.open(id)
        let session = try #require(model.session)
        live.start()
        onKeyboard.start()
        pull.start()
        live.startLive()
        #expect(await eventually(tries: 500) { model.keyboardRevision != nil })
        let offered = try #require(model.keyboardRevision)

        model.useKeyboardRevision()
        #expect(await eventually { pull.status == .idle }, "the offer ends")
        #expect(session.layout == keyboard, "the keyboard's layout, title included")
        #expect(model.firmwareMatch == .current)
        #expect(session.revisions.last?.message == "Restored revision \(offered.number)")

        session.setCode("KC_Q", layer: 0, index: 2)
        #expect(model.keyboardRevision == nil, "later edits don't bring the offer back")
    }

    // MARK: The window

    @Test func theWindowSaysWhereTheLayoutCameFromAndWhyALayoutIsSuggested() {
        let layout = KeyboardLayout(title: "Mine", layers: [], oryx: OryxRevisionInfo(layoutId: "KlgM7", revisionId: "40xJ7M"))
        #expect(KeyboardLayoutWindow.origin(of: layout, serial: "KlgM7/40xJ7M") == "Oryx revision 40xJ7M")
        #expect(KeyboardLayoutWindow.origin(of: layout, serial: serial) == "Flashed from Sextant on another Mac")
        let oryx = LibraryEntry(id: UUID(), title: "Work", origin: .oryx(layoutId: "KlgM7", revisionId: "aa11"), modifiedAt: Date())
        #expect(KeyboardLayoutWindow.suggestion(oryx, for: layout) == "Work (same Oryx layout)")
        let named = LibraryEntry(id: UUID(), title: "Mine", origin: .local, modifiedAt: Date())
        #expect(KeyboardLayoutWindow.suggestion(named, for: layout) == "Mine (same name)")
    }

    /// Sextant's build of an Oryx revision reads as on the keyboard only in a layout from that Oryx layout, so Add to offers
    /// only those besides New Layout. A Sextant build's layout can go in any.
    @Test func addToOffersAnOryxRevisionsBuildOnlyItsOryxLayout() {
        let layout = KeyboardLayout(title: "Mine", layers: [], oryx: OryxRevisionInfo(layoutId: "KlgM7", revisionId: "40xJ7M"))
        let oryx = LibraryEntry(id: UUID(), title: "Work", origin: .oryx(layoutId: "KlgM7", revisionId: "aa11"), modifiedAt: Date())
        let other = LibraryEntry(id: UUID(), title: "Travel", origin: .oryx(layoutId: "Q9x2", revisionId: "bb22"), modifiedAt: Date())
        let named = LibraryEntry(id: UUID(), title: "Mine", origin: .local, modifiedAt: Date(), aliases: [UUID()])
        let imported = KeyboardLayoutPull.Found(layout: layout, serial: "KlgM7/40xJ7M", suggested: nil)
        #expect(KeyboardLayoutWindow.destinations(for: imported, in: [named, oryx, other]) == [oryx])
        let built = KeyboardLayoutPull.Found(layout: layout, serial: serial, suggested: nil)
        #expect(KeyboardLayoutWindow.destinations(for: built, in: [named, oryx, other]) == [named, oryx, other])
    }

    // MARK: Settings › Build

    @Test func storingTheLayoutIsOnUntilTurnedOff() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(BuildSettings.storesLayoutInFirmware(in: defaults))
        defaults.set(false, forKey: SettingsKey.storesLayoutInFirmware)
        #expect(!BuildSettings.storesLayoutInFirmware(in: defaults))
    }

    /// A started live session over `fake`, the layout on its keyboard, an empty in-memory library, and the pull, which is
    /// never started, so it reads only when asked. Without `looksUp` the layout on the keyboard isn't started either, so
    /// it never looks the serial up.
    private static func session(
        _ fake: StandInKeyboard, looksUp: Bool = true
    ) -> (LiveSession, OnKeyboard, Library, KeyboardLayoutPull) {
        let live = LiveSession(watcher: fake, link: fake, secureInputProbe: { false })
        let store = MemoryLibrary()
        let library = Library(store: store)
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        live.start()
        if looksUp { onKeyboard.start() }
        return (live, onKeyboard, library, KeyboardLayoutPull(live: live, onKeyboard: onKeyboard, library: library, store: store))
    }
}

/// A Voyager running a Sextant build that stores `record` (ADR 0061): Live View pairs at once, and each layout read is
/// answered as the firmware answers it, up to 24 bytes from the offset. Nothing else is answered.
private final class RecordKeyboard: DeviceWatcher, KeyboardLink, Sendable {
    private let serial: String
    private let record: [UInt8]

    init(serial: String, record: [UInt8]) {
        self.serial = serial
        self.record = record
    }

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: serial)))) }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        let bytes = record
        return AsyncStream { continuation in
            // The first layer report pairs the session.
            continuation.yield(.layer(0))
            let task = Task {
                for await command in commands {
                    guard case let .readLayoutRecord(offset) = command else { continue }
                    let part = bytes.indices.contains(offset) ? Array(bytes[offset..<min(offset + 24, bytes.count)]) : []
                    continuation.yield(.layoutRecord(LayoutRecordChunk(offset: offset, size: bytes.count, bytes: part)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// One layout whose working copy and revisions are kept, enough for the keyboard layout pull, the layout on the keyboard
/// and History. It starts with one saved revision of the layout.
private actor OneLayoutLibrary: LayoutLibrary {
    private var entry: LibraryEntry
    private var working: KeyboardLayout
    private var revisions: [(summary: RevisionSummary, layout: KeyboardLayout)] = []

    init(_ layout: KeyboardLayout, id: UUID) {
        entry = LibraryEntry(id: id, title: layout.title, origin: .local, modifiedAt: Date())
        working = layout
        revisions = [(Self.summary(1, layout, source: .save, message: nil), layout)]
    }

    private static func summary(_ n: Int, _ layout: KeyboardLayout, source: RevisionSource, message: String?) -> RevisionSummary {
        RevisionSummary(
            id: "000\(n)-rev", number: n, createdAt: Date(), source: source, message: message, contentHash: "h\(layout.hashValue)")
    }

    func entries() -> [LibraryEntry] { [entry] }
    func load(_ id: UUID) throws(LibraryError) -> StoredLayout {
        guard id == entry.id else { throw .notFound(id) }
        return StoredLayout(entry: entry, layout: working, contentHash: "h\(working.hashValue)", revisions: revisions.map(\.summary))
    }
    func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) -> LibraryEntry { entry }
    func save(_ layout: KeyboardLayout, to id: UUID) { working = layout }
    func appendRevision(_ draft: RevisionDraft, to id: UUID) -> RevisionSummary {
        let summary = Self.summary(revisions.count + 1, draft.layout, source: draft.source, message: draft.message)
        revisions.append((summary, draft.layout))
        return summary
    }
    func layout(ofRevision revisionID: String, in id: UUID) throws(LibraryError) -> KeyboardLayout {
        guard let layout = revisions.first(where: { $0.summary.id == revisionID })?.layout else { throw .notFound(id) }
        return layout
    }
    func rename(_ id: UUID, to title: String) {}
    func duplicate(_ id: UUID) throws(LibraryError) -> LibraryEntry { throw .notFound(id) }
    func trash(_ id: UUID) {}
    func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) {}
    func firmware(revisionID: String, of id: UUID) -> (data: Data, md5: String)? { nil }
    func location(of id: UUID) -> URL? { nil }
    func saveRecovery(_ layout: KeyboardLayout, for id: UUID) {}
    func recovery(of id: UUID) -> KeyboardLayout? { nil }
    func discardRecovery(of id: UUID) {}
    func appLayerRules(of id: UUID) -> AppLayerRules { AppLayerRules() }
    func saveAppLayerRules(_ rules: AppLayerRules, for id: UUID) {}
    func link(_ id: UUID, to ids: Set<UUID>) { entry.aliases.formUnion(ids.subtracting([entry.id])) }
}

/// Polls `condition`, letting other tasks run, for up to about two seconds (`tries` of 10 ms).
@MainActor
private func eventually(tries: Int = 200, _ condition: () -> Bool) async -> Bool {
    for _ in 0..<tries where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
