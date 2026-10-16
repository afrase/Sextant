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
        #expect(await eventually { live.firmwareSerial == serial })
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

    /// Use It is offered only when restoring would change the working copy: not for its title or its macro drafts.
    @Test func useItIgnoresTheTitleAndMacroDrafts() throws {
        let layout = try KeyboardLayout(oryxJSON: #require(userLayoutData))
        var renamed = layout
        renamed.title = "From the other Mac"
        #expect(!LayoutWindowModel.differs(layout, from: renamed), "a restore keeps the working copy's title")
        var drafted = layout
        drafted.macroDrafts = [MacroDraft(macro: Macro(steps: [MacroStep(code: "KC_A")]))]
        #expect(!LayoutWindowModel.differs(drafted, from: layout), "drafts never reach the keyboard")
        var edited = layout
        edited.layers[0].keys[0] = Key("KC_F13")
        #expect(LayoutWindowModel.differs(edited, from: layout))
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
    /// never started, so it reads only when asked.
    private static func session(_ fake: StandInKeyboard) -> (LiveSession, OnKeyboard, Library, KeyboardLayoutPull) {
        let live = LiveSession(watcher: fake, link: fake, secureInputProbe: { false })
        let store = MemoryLibrary()
        let library = Library(store: store)
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        live.start()
        onKeyboard.start()
        return (live, onKeyboard, library, KeyboardLayoutPull(live: live, onKeyboard: onKeyboard, library: library, store: store))
    }
}

/// Polls `condition`, letting other tasks run, for up to about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}
