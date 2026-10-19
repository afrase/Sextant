import AppKit
import Clocks
import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// When the overlay HUD shows (spec §8.4, ADR 0050), driven by the keyboard's live activity on a test clock. Nothing
/// here talks to a keyboard or puts a window on screen.
@MainActor
struct OverlayModelTests {
    let clock = TestClock()
    let id = UUID()

    /// The user's layout (⏎, key 24, holds Sym+Num; Space, key 51, holds Brd+Sys) with Live View on and the keyboard on
    /// its base layer.
    func model(_ layout: KeyboardLayout? = nil, settings: OverlaySettings = OverlaySettings()) throws -> OverlayModel {
        let model = OverlayModel(clock: clock)
        model.settings = settings
        model.keyboard = try OverlayLayout(id: id, layout: layout ?? KeyboardLayout(oryxJSON: #require(userLayoutData)))
        model.isLive = true
        model.handle(.layer(0))
        return model
    }

    /// Lets the main actor run the delay's task: before advancing the clock (so it sleeps) and after (so it shows).
    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    func advance(_ milliseconds: Int) async {
        await settle()
        await clock.advance(by: .milliseconds(milliseconds))
        await settle()
    }

    @Test func aHeldLayerShowsAfterTheDelayAndHidesOnRelease() async throws {
        let model = try model()
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(149)
        #expect(model.presentation == nil, "not before 150 ms")
        await advance(1)
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)))
        #expect(model.pressedKeys == [24])
        model.handle(.keyDown(index: 13, layer: 1))
        #expect(model.pressedKeys == [13, 24])
        model.handle(.keyUp(index: 13))
        model.handle(.keyUp(index: 24))
        #expect(model.presentation == nil, "hides on the holder's key-up, before the layer change arrives")
        model.handle(.layer(0))
        await advance(500)
        #expect(model.presentation == nil)
    }

    @Test func aTapShorterThanTheDelayShowsNothing() async throws {
        let model = try model()
        model.handle(.keyDown(index: 51, layer: 0))
        model.handle(.layer(2))
        await advance(100)
        model.handle(.keyUp(index: 51))
        model.handle(.layer(0))
        await advance(500)
        #expect(model.presentation == nil)
    }

    /// The firmware can drop the layer change back to the base layer (research 03 O2): the key-up alone hides it, and the
    /// layer it seems to stay on isn't taken for a locked one.
    @Test func aMissingLayerChangeLeavesNoReminder() async throws {
        let model = try model()
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        model.handle(.keyUp(index: 24))
        await advance(1000)
        #expect(model.presentation == nil)
        // Held again, with the layer report deduplicated away: the key-down alone brings it back.
        model.handle(.keyDown(index: 24, layer: 1))
        await advance(150)
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 1, index: 24)))
    }

    @Test func aLockedLayerShowsWhatSettingsSay() async throws {
        let layout = synthetic()
        let reminder = try model(layout)
        reminder.handle(.keyDown(index: 1, layer: 0))  // TG(3)
        reminder.handle(.layer(3))
        reminder.handle(.keyUp(index: 1))
        await advance(149)
        #expect(reminder.presentation == nil)
        await advance(1)
        #expect(reminder.presentation == .pill(layer: 3))
        reminder.handle(.layer(0))
        #expect(reminder.presentation == nil, "until the keyboard is back on its base layer")

        var settings = OverlaySettings()
        settings.locked = .full
        settings.delay = .zero
        let full = try model(layout, settings: settings)
        full.handle(.layer(3))
        await advance(49)
        #expect(full.presentation == nil, "a lock waits 50 ms even with no delay")
        await advance(1)
        #expect(full.presentation == .full(layer: 3, heldBy: nil))

        settings.locked = .nothing
        let nothing = try model(layout, settings: settings)
        nothing.handle(.layer(3))
        await advance(500)
        #expect(nothing.presentation == nil)
    }

    @Test func aTappedTapToggleIsLockedButAHeldOneIsNot() async throws {
        let tapped = try model(synthetic())
        tapped.handle(.keyDown(index: 3, layer: 0))  // TT(3)
        tapped.handle(.layer(3))
        await advance(40)
        tapped.handle(.keyUp(index: 3))
        await advance(150)
        #expect(tapped.presentation == .pill(layer: 3))

        let held = try model(synthetic())
        held.handle(.keyDown(index: 3, layer: 0))
        held.handle(.layer(3))
        await advance(300)
        #expect(held.presentation == .full(layer: 3, heldBy: KeyRef(layer: 0, index: 3)))
        // Its key-up comes just before the layer ends: no reminder in between.
        held.handle(.keyUp(index: 3))
        await advance(1)
        held.handle(.layer(0))
        await advance(500)
        #expect(held.presentation == nil)
    }

    @Test func aOneShotLayerHidesOnReleaseWithoutAReminder() async throws {
        let model = try model(synthetic())
        model.handle(.keyDown(index: 5, layer: 0))  // OSL(3)
        model.handle(.layer(3))
        await advance(150)
        #expect(model.presentation == .full(layer: 3, heldBy: KeyRef(layer: 0, index: 5)))
        model.handle(.keyUp(index: 5))
        await advance(500)
        #expect(model.presentation == nil)
    }

    /// Holding a layer key that sits on a held layer: Main's key 0 holds layer 1, where key 30 holds layer 2.
    @Test func movingToAnotherHeldLayerSwitchesAtOnce() async throws {
        var layout = synthetic()
        layout.layers[0].keys[0] = Key(tap: .momentary(1))
        layout.layers[1].keys[30] = Key(tap: .momentary(2))
        let model = try model(layout)
        model.handle(.keyDown(index: 0, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        model.handle(.keyDown(index: 30, layer: 1))
        model.handle(.layer(2))
        #expect(model.presentation == .full(layer: 2, heldBy: KeyRef(layer: 1, index: 30)), "already showing: no second delay")
        model.handle(.keyUp(index: 0))
        #expect(model.presentation == .full(layer: 2, heldBy: KeyRef(layer: 1, index: 30)), "key 0 holds layer 1, not 2")
        model.handle(.keyUp(index: 30))
        #expect(model.presentation == nil)
    }

    @Test func hiddenDuringSecureInputAndWhileLiveViewIsOff() async throws {
        let model = try model()
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        model.secureInput(true, layer: 1)
        #expect(model.presentation == nil)
        #expect(model.pressedKeys.isEmpty)
        // Nothing was hidden meanwhile, so ⏎ is still held: the overlay comes back after the delay.
        model.secureInput(false, layer: 1)
        await advance(150)
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)))

        model.isLive = false
        #expect(model.presentation == nil)
        model.isLive = true
        await advance(500)
        #expect(model.presentation == nil, "Live View off forgets the layer until the keyboard reports it again")
    }

    /// A layer reached while secure input hid the keys is unexplained: it isn't taken for a lock, and the next report
    /// counts. (The session releases the keys it hid and lets that report through: ``LiveSession/activity()``.)
    @Test func aLayerReachedDuringSecureInputIsntTakenForALock() async throws {
        let model = try model()
        model.secureInput(true, layer: 0)
        model.secureInput(false, layer: 1)
        await advance(500)
        #expect(model.presentation == nil, "the key that moved it may still be held")
        model.handle(.layer(0))
        model.handle(.layer(1))
        await advance(150)
        #expect(model.presentation == .pill(layer: 1))

        // Held across secure input, with keys typed meanwhile: the session releases ⏎ for the model.
        model.handle(.layer(0))
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        model.secureInput(true, layer: 1)
        model.handle(.keyUp(index: 24))
        model.secureInput(false, layer: 1)
        await advance(500)
        #expect(model.presentation == nil, "no reminder for a layer the model saw held")
    }

    /// From a lock's reminder, a layer key's tap shorter than the delay doesn't flash the full overlay.
    @Test func aQuickTapFromTheReminderWaitsForTheDelay() async throws {
        var layout = synthetic()
        layout.layers[0].keys[1] = Key(tap: .toggle(1))
        layout.layers[1].keys[0] = Key(tap: .momentary(2))
        let model = try model(layout)
        model.handle(.keyDown(index: 1, layer: 0))
        model.handle(.layer(1))
        model.handle(.keyUp(index: 1))
        await advance(150)
        #expect(model.presentation == .pill(layer: 1))
        model.handle(.keyDown(index: 0, layer: 1))
        model.handle(.layer(2))
        #expect(model.presentation == .pill(layer: 1))
        await advance(40)
        model.handle(.keyUp(index: 0))
        model.handle(.layer(1))
        await advance(500)
        #expect(model.presentation == .pill(layer: 1), "the full overlay never showed")
    }

    @Test func hiddenWhileAKeyWindowShowsTheSameLayer() async throws {
        let model = try model()
        let window = ObjectIdentifier(model)
        model.window(window, shows: ShownLayer(layoutID: id, layer: 1))
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(500)
        #expect(model.presentation == nil)
        model.window(window, shows: ShownLayer(layoutID: UUID(), layer: 1))
        await advance(150)
        #expect(model.presentation != nil, "another layout's layer 1 is another layer")
        model.window(window, shows: ShownLayer(layoutID: id, layer: 2))
        #expect(model.presentation != nil)
        model.window(window, shows: ShownLayer(layoutID: id, layer: 1))
        #expect(model.presentation == nil)
    }

    @Test func nothingShowsWhenTurnedOffWithoutTheLayoutOrOnTheAutoMouseLayer() async throws {
        var settings = OverlaySettings()
        settings.showsOverlay = false
        let off = try model(settings: settings)
        off.handle(.keyDown(index: 24, layer: 0))
        off.handle(.layer(1))
        await advance(500)
        #expect(off.presentation == nil)

        let unknown = try model()
        unknown.keyboard = nil
        unknown.handle(.keyDown(index: 24, layer: 0))
        unknown.handle(.layer(1))
        await advance(500)
        #expect(unknown.presentation == nil)

        var layout = synthetic()
        layout.navigator = NavigatorConfig(kind: .trackpad, side: .right)
        layout.automouseLayer = 2
        let pointer = try model(layout)
        pointer.handle(.layer(2))
        await advance(500)
        #expect(pointer.presentation == nil)
    }

    @Test func noDelayShowsAtOnceAndUnpairedKeyUpsAreIgnored() throws {
        var settings = OverlaySettings()
        settings.delay = .zero
        let model = try model(settings: settings)
        model.handle(.keyUp(index: 7))
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)))
    }

    @Test func settingsAreReadWithThePanesDefaults() throws {
        let suiteName = "OverlayModelTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(OverlaySettings(defaults) == OverlaySettings())
        defaults.set(false, forKey: SettingsKey.showsOverlay)
        defaults.set(1990, forKey: SettingsKey.overlayDelay)
        defaults.set("top", forKey: SettingsKey.overlayPosition)
        defaults.set("large", forKey: SettingsKey.overlaySize)
        defaults.set(true, forKey: SettingsKey.tintsOverlay)
        defaults.set("full", forKey: SettingsKey.lockedLayerOverlay)
        defaults.set("hideUntilNextHold", forKey: SettingsKey.overlayTyping)
        defaults.set(50, forKey: SettingsKey.overlayTypingDelay)
        let read = OverlaySettings(defaults)
        #expect(!read.showsOverlay && read.delay == .milliseconds(1000) && read.position == .top && read.size == .large)
        #expect(read.tints && read.locked == .full && read.typing == .hideUntilNextHold)
        #expect(read.typingDelay == .milliseconds(100), "clamped to the pane's range")
    }

    /// Settings › Keyboard's Preview (ADR 0062) shows the keyboard's layer 1 even with Live View off, and is never a
    /// presentation: a held layer shows in its place while it lasts.
    @Test func thePreviewShowsWithLiveViewOffAndGivesWayToAHeldLayer() async throws {
        let model = try model()
        let layout = try #require(model.keyboard?.layout)
        model.isLive = false
        model.isPreviewing = true
        #expect(model.shown == ShownOverlay(presentation: .full(layer: 1, heldBy: nil), layout: layout, isPreview: true))
        #expect(model.presentation == nil)

        model.isLive = true
        model.handle(.layer(0))
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        #expect(model.shown?.isPreview == true, "the preview stays up through the delay")
        await advance(150)
        let held = OverlayPresentation.full(layer: 1, heldBy: KeyRef(layer: 0, index: 24))
        #expect(model.presentation == held)
        #expect(model.shown == ShownOverlay(presentation: held, layout: layout, isPreview: false))
        model.handle(.keyUp(index: 24))
        model.handle(.layer(0))
        #expect(model.presentation == nil)
        #expect(model.shown?.isPreview == true, "back to the preview")

        model.isPreviewing = false
        #expect(model.shown == nil)
    }

    @Test func thePreviewDrawsASampleWithoutTheKeyboardsLayout() throws {
        let model = try model()
        model.keyboard = nil
        model.isPreviewing = true
        let shown = try #require(model.shown)
        #expect(shown == ShownOverlay(presentation: .full(layer: 0, heldBy: nil), layout: OverlayModel.previewSample, isPreview: true))
        #expect(shown.layout.layers.count == 1)
        model.isPreviewing = false
    }

    @Test func thePreviewEndsEightSecondsAfterTheLastChange() async throws {
        let model = try model()
        model.isPreviewing = true
        await advance(7000)
        var settings = model.settings
        settings.opacity = 0.5
        model.settings = settings
        await advance(7999)
        #expect(model.isPreviewing, "a change starts its time again")
        await advance(1)
        #expect(!model.isPreviewing && model.shown == nil)

        model.isPreviewing = true
        await advance(8000)
        #expect(!model.isPreviewing, "with no change, 8 s after it started")
    }

    @Test func turningTheOverlayOffEndsThePreview() async throws {
        let model = try model()
        model.isPreviewing = true
        var settings = model.settings
        settings.showsOverlay = false
        model.settings = settings
        #expect(!model.isPreviewing && model.shown == nil)
        model.isPreviewing = true
        #expect(!model.isPreviewing, "it can't start while the overlay is off")
        settings.showsOverlay = true
        model.settings = settings
        await advance(10_000)
        #expect(model.shown == nil)
    }

    /// The panel never takes focus or clicks (spec §13.3 rule 8). It is made, never shown.
    @Test func thePanelNeverBecomesKeyAndLetsClicksThrough() {
        let panel = OverlayPanel()
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(panel.ignoresMouseEvents && !panel.hidesOnDeactivate && panel.level == .statusBar)
        #expect(!panel.canHide, "hiding Sextant leaves it, so unhiding can't bring back a presentation that ended")
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
        #expect(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]))
        #expect(!panel.isVisible)
    }

    @Test func theHUDSitsCenteredClearOfTheScreensEdges() {
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 900)
        let size = CGSize(width: 696, height: 300)
        // The default distance, 72 pt; the other spots are in OverlayPlacementTests.
        let bottom = OverlayPanel.frame(size: size, position: .bottom, margin: 72, on: visible)
        #expect(bottom == CGRect(x: 408, y: 112, width: 696, height: 300))
        #expect(OverlayPanel.frame(size: size, position: .top, margin: 72, on: visible) == CGRect(x: 408, y: 568, width: 696, height: 300))
        #expect(HUDView.width(size: .medium, screenWidth: 1512) == 696)
        #expect(HUDView.width(size: .medium, screenWidth: 2560) == 720)
        #expect(HUDView.width(size: .small, screenWidth: 2560) == 540)
        #expect(HUDView.width(size: .large, screenWidth: 2560) == 900)
        #expect(HUDView.width(size: .large, screenWidth: 800) == 460)
    }

    /// Main's keys 0–8 hold layer 3 in each layer function's way (as in `LayerHoldTests`).
    func synthetic() -> KeyboardLayout {
        var layout = KeyboardLayout(
            title: "Synthetic", layers: (0..<4).map { Layer.transparent(title: "L\($0)", color: HexColor(red: 0, green: 0.5, blue: 1)) })
        let keys: [Int: Key] = [
            1: Key(tap: .toggle(3)), 3: Key(tap: KeyAction(code: "TT", layer: 3)), 5: Key(tap: .oneShotLayer(3)),
        ]
        layout.layers[0].keys = (0..<52).map { keys[$0] ?? Key("KC_A") }
        return layout
    }
}
