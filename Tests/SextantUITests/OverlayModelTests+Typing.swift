import SextantDomain
import Testing

@testable import SextantUI

/// Hide while typing on the layer (ADR 0064), on ``OverlayModelTests``' test clock and layouts.
extension OverlayModelTests {
    /// Keys pressed on a held layer hide the overlay until they're all let go and none goes down for the delay.
    @Test func typingHidesTheHeldOverlayUntilItStopsForTheDelay() async throws {
        var settings = OverlaySettings()
        settings.hidesWhileTyping = true
        let model = try model(settings: settings)
        let held = OverlayPresentation.full(layer: 1, heldBy: KeyRef(layer: 0, index: 24))
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        #expect(model.presentation == held)
        model.handle(.keyDown(index: 13, layer: 1))
        #expect(model.presentation == nil, "hides at the key-down")
        #expect(model.pressedKeys == [13, 24])
        model.handle(.keyDown(index: 14, layer: 1))
        model.handle(.keyUp(index: 13))
        await advance(500)
        #expect(model.presentation == nil, "while a key is still down")
        model.handle(.keyUp(index: 14))
        await advance(100)
        model.handle(.keyDown(index: 15, layer: 1))
        model.handle(.keyUp(index: 15))
        await advance(149)
        #expect(model.presentation == nil, "a key-down starts the delay again")
        await advance(1)
        #expect(model.presentation == held)
        model.handle(.keyUp(index: 24))
        #expect(model.presentation == nil)
    }

    @Test func typingBeforeTheDelayHoldsTheOverlayBack() async throws {
        var settings = OverlaySettings()
        settings.hidesWhileTyping = true
        let model = try model(settings: settings)
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(100)
        model.handle(.keyDown(index: 13, layer: 1))
        await advance(100)
        #expect(model.presentation == nil)
        model.handle(.keyUp(index: 13))
        await advance(149)
        #expect(model.presentation == nil)
        await advance(1)
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)))
    }

    @Test func typingKeepsTheOverlayWithTheSettingOff() async throws {
        let model = try model()
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        model.handle(.keyDown(index: 13, layer: 1))
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)))
    }

    /// With no delay it still waits ``OverlayModel/typingSettle``, so it doesn't flash back between keystrokes.
    @Test func typingWithNoDelayWaitsTheSettleTime() async throws {
        var settings = OverlaySettings()
        settings.hidesWhileTyping = true
        settings.delay = .zero
        let model = try model(settings: settings)
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        #expect(model.presentation != nil)
        model.handle(.keyDown(index: 13, layer: 1))
        model.handle(.keyUp(index: 13))
        await advance(99)
        #expect(model.presentation == nil)
        await advance(1)
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)))
    }

    /// A locked layer's full overlay hides too; its reminder doesn't.
    @Test func typingHidesALockedLayersFullOverlayButNotItsReminder() async throws {
        var settings = OverlaySettings()
        settings.hidesWhileTyping = true
        settings.locked = .full
        let full = try model(synthetic(), settings: settings)
        full.handle(.layer(3))
        await advance(150)
        full.handle(.keyDown(index: 10, layer: 3))
        #expect(full.presentation == nil)
        full.handle(.keyUp(index: 10))
        await advance(150)
        #expect(full.presentation == .full(layer: 3, heldBy: nil))

        settings.locked = .reminder
        let reminder = try model(synthetic(), settings: settings)
        reminder.handle(.layer(3))
        await advance(150)
        reminder.handle(.keyDown(index: 10, layer: 3))
        #expect(reminder.presentation == .pill(layer: 3))
    }

    /// A layer key isn't typing: holding another layer from a held one still switches at once.
    @Test func aLayerKeyIsntTyping() async throws {
        var layout = synthetic()
        layout.layers[0].keys[0] = Key(tap: .momentary(1))
        layout.layers[1].keys[30] = Key(tap: .momentary(2))
        var settings = OverlaySettings()
        settings.hidesWhileTyping = true
        let model = try model(layout, settings: settings)
        model.handle(.keyDown(index: 0, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        model.handle(.keyDown(index: 30, layer: 1))
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 0)))
        model.handle(.layer(2))
        #expect(model.presentation == .full(layer: 2, heldBy: KeyRef(layer: 1, index: 30)))
    }

    /// Letting go of the layer forgets the typing: held again, the overlay shows after the delay alone.
    @Test func typingEndsWithTheLayer() async throws {
        var settings = OverlaySettings()
        settings.hidesWhileTyping = true
        let model = try model(settings: settings)
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        model.handle(.keyDown(index: 13, layer: 1))
        model.handle(.keyUp(index: 24))
        model.handle(.layer(0))
        model.handle(.keyDown(index: 24, layer: 0))
        model.handle(.layer(1))
        await advance(150)
        #expect(model.presentation == .full(layer: 1, heldBy: KeyRef(layer: 0, index: 24)), "key 13, still down, typed over the last hold")
    }
}
