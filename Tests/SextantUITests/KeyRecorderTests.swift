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
}
