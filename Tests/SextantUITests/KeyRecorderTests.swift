import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// Record Key (spec §5.8): positional mapping, sides, lone modifiers and esc.
struct KeyRecorderTests {
    /// Device-dependent flag bits (`NX_DEVICE*KEYMASK`) plus the device-independent ones.
    let leftShift: UInt = 0x2 | (1 << 17)
    let rightShift: UInt = 0x4 | (1 << 17)
    let leftCommand: UInt = 0x8 | (1 << 20)
    let rightCommand: UInt = 0x10 | (1 << 20)

    @Test func everyMappedKeyIsACatalogKeycode() {
        for code in KeyRecorder.codes.values {
            #expect(KeycodeCatalog.entry(for: code)?.code == code, "\(code)")
        }
        #expect(KeyRecorder.codes[0x00] == "KC_A")
        #expect(KeyRecorder.codes[0x0A] == "KC_NONUS_BACKSLASH", "ISO §")
        #expect(KeyRecorder.codes[0x5D] == "KC_INTERNATIONAL_3", "JIS ¥")
    }

    @Test func chordsKeepTheirSides() {
        var recorder = KeyRecorder(target: 0)
        #expect(recorder.keyDown(0x21, flags: rightCommand) == .assign(code: "KC_LBRC", modifiers: [.rightCommand]))
        #expect(KeyRecorder.modifiers(leftShift | rightShift) == [.leftShift, .rightShift])
        #expect(KeyRecorder.modifiers(1 << 17) == [.leftShift], "without device bits, the left side")
    }

    @Test func aLoneModifierAssignsItself() {
        var recorder = KeyRecorder(target: 0)
        #expect(recorder.flagsChanged(0x3C, flags: rightShift) == nil)
        #expect(recorder.flagsChanged(0x3C, flags: 0) == .assign(code: "KC_RIGHT_SHIFT", modifiers: []))
        // Held for a chord, it is part of the chord and not assigned on release.
        #expect(recorder.flagsChanged(0x38, flags: leftShift) == nil)
        #expect(recorder.keyDown(0x00, flags: leftShift) == .assign(code: "KC_A", modifiers: [.leftShift]))
        #expect(recorder.flagsChanged(0x38, flags: 0) == nil)
        // Two modifiers together are not a lone modifier.
        _ = recorder.flagsChanged(0x37, flags: leftCommand)
        _ = recorder.flagsChanged(0x38, flags: leftCommand | leftShift)
        #expect(recorder.flagsChanged(0x38, flags: leftCommand) == nil)
    }

    @Test func escCancelsAndUnknownKeysSaySo() {
        var recorder = KeyRecorder(target: 0)
        #expect(recorder.keyDown(0x35, flags: leftCommand) == .cancel)
        #expect(recorder.keyDown(0xFF, flags: 0) == .unmapped)
        #expect(recorder.flagsChanged(0x3F, flags: 1 << 23) == .unmapped, "fn")
        #expect(recorder.flagsChanged(0x39, flags: 1 << 16) == .assign(code: "KC_CAPS", modifiers: []))
    }

    @MainActor @Test func recordingAssignsToTheSelectedSlot() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19, slot: .hold)
        model.startRecording()
        #expect(model.record(keyCode: 0x21, flags: leftCommand, isKeyDown: true))
        #expect(session.selectedAction == KeyAction(code: "KC_LBRC", modifiers: [.leftCommand]))
        #expect(model.recorder == nil)

        model.startRecording()
        model.record(keyCode: 0xFF, flags: 0, isKeyDown: true)
        #expect(model.recorder?.cannotMap == true, "recording goes on after a key Sextant can't map")
        model.record(keyCode: 0x35, flags: 0, isKeyDown: true)
        #expect(model.recorder == nil, "esc cancels")
        #expect(!model.record(keyCode: 0x00, flags: 0, isKeyDown: true), "not recording: events pass through")
    }

    /// Every key Record Steps can hear is one a macro can type.
    @Test func everyMappedKeyCanBeAStep() {
        for code in KeyRecorder.codes.values { #expect(MacroStep.canType(code), "\(code)") }
        for code in ["KC_LEFT_CTRL", "KC_LEFT_SHIFT", "KC_RIGHT_SHIFT", "KC_LEFT_GUI", "KC_RIGHT_GUI", "KC_LEFT_ALT", "KC_RIGHT_ALT"] {
            #expect(MacroStep.canType(code), "\(code)")
        }
    }

    /// Record Steps (spec §6.3): each key is the next step, pauses round to 10 ms and stop at 5 s, a lone modifier is a
    /// step, and esc stops.
    @MainActor @Test func recordStepsAddsEachKeyUntilEsc() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.newMacro()
        let draft = try #require(session.selection.macro)
        model.macros.recordsPauses = true
        model.startRecordingSteps(in: draft)
        #expect(model.recordStep(keyCode: 0x28, flags: 0, isKeyDown: true, at: 10))
        model.recordStep(keyCode: 0x0E, flags: leftShift, isKeyDown: true, at: 10.1234)
        model.recordStep(keyCode: 0xFF, flags: 0, isKeyDown: true, at: 10.5)
        #expect(model.macros.stepRecorder?.cannotMap == true, "recording goes on after a key Sextant can't map")
        model.recordStep(keyCode: 0x3C, flags: rightShift, isKeyDown: false, at: 16)
        model.recordStep(keyCode: 0x3C, flags: 0, isKeyDown: false, at: 17)
        #expect(
            session.layout.macro(at: draft)?.steps == [
                MacroStep(code: "KC_K", delay: 120), MacroStep(code: "KC_E", modifiers: [.leftShift], delay: 5000),
                MacroStep(code: "KC_RIGHT_SHIFT"),
            ])
        #expect(session.selection.step == 2, "each step is selected, so the next goes after it")
        model.recordStep(keyCode: 0x35, flags: 0, isKeyDown: true, at: 18)
        #expect(model.macros.stepRecorder == nil && session.layout.macro(at: draft)?.steps.count == 3, "esc stops, unrecorded")
        #expect(!model.recordStep(keyCode: 0x00, flags: 0, isKeyDown: true, at: 19), "not recording: events pass through")

        // Without pauses the waits stay 0; recording stops at Oryx's 24 steps.
        model.macros.recordsPauses = false
        session.selectMacro(draft, step: nil)
        model.startRecordingSteps(in: draft)
        for i in 0..<21 { model.recordStep(keyCode: 0x00, flags: 0, isKeyDown: true, at: 20 + Double(i)) }
        let steps = try #require(session.layout.macro(at: draft)?.steps)
        #expect(steps.count == 24 && steps.suffix(21).allSatisfy { $0.delay == 0 } && model.macros.stepRecorder == nil)
    }

    /// A pause runs from key press to key press, a lone modifier's included, and only a step recorded right before
    /// takes one: a step clicked meanwhile keeps its own wait.
    @MainActor @Test func recordedPausesRunBetweenPresses() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.newMacro()
        let draft = try #require(session.selection.macro)
        session.insertStep(MacroStep(code: "KC_A", delay: 150), at: 0, in: draft)
        model.macros.recordsPauses = true
        model.startRecordingSteps(in: draft)
        model.recordStep(keyCode: 0x07, flags: 0, isKeyDown: true, at: 10)  // X
        model.recordStep(keyCode: 0x38, flags: leftShift, isKeyDown: false, at: 10.1)
        model.recordStep(keyCode: 0x38, flags: 0, isKeyDown: false, at: 12)
        model.recordStep(keyCode: 0x39, flags: 0, isKeyDown: false, at: 12.5)  // Caps Lock: a step as it goes down
        session.selectMacro(draft, step: 0)
        model.recordStep(keyCode: 0x10, flags: 0, isKeyDown: true, at: 15)  // Y, after A
        #expect(
            session.layout.macro(at: draft)?.steps.map { "\($0.code)/\($0.delay)" } == [
                "KC_A/150", "KC_Y/0", "KC_X/100", "KC_LEFT_SHIFT/2400", "KC_CAPS/0",
            ])
    }

    /// Opening the palette (the toolbar's Search) or the picker ends Record Steps, which would otherwise take the typing.
    @MainActor @Test func thePaletteEndsRecordSteps() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.destination = .macros
        session.newMacro()
        let draft = try #require(session.selection.macro)
        model.startRecordingSteps(in: draft)
        model.openPalette()
        #expect(model.macros.stepRecorder == nil && !model.recordStep(keyCode: 0x11, flags: 0, isKeyDown: true, at: 1))
        model.startRecordingSteps(in: draft)
        model.openStepPicker(step: nil, in: draft)
        #expect(model.macros.stepRecorder == nil)
    }

    /// Follow can show another layer while a layer key is held for the key being recorded (F1 on a function layer).
    @MainActor @Test func recordingAssignsToTheLayerItStartedOn() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        model.startRecording()
        session.select(layer: 1)
        model.record(keyCode: 0x7A, flags: 0, isKeyDown: true)
        #expect(session.layout.key(layer: 0, index: 19)?.tap?.code == "KC_F1")
        #expect(session.layout.key(layer: 1, index: 19)?.tap?.code != "KC_F1")
    }
}
