import Foundation
import Testing

@testable import SextantUI

/// The activity capsule's states (spec §3.5).
struct ActivityStateTests {
    @Test func looks() {
        typealias Status = ActivityState.Status
        #expect(Status.noKeyboard.look.text == "No keyboard")
        #expect(
            Status.notOnKeyboard(edits: 5).look
                == ActivityLook(symbol: "arrow.up.circle", tone: .warning, text: "Not on keyboard", detail: "5 edits"))
        #expect(Status.notOnKeyboard(edits: 1).look.detail == "1 edit")
        #expect(Status.building(file: "keymap.c", done: 12, total: 41).look.symbol == nil, "a spinner")
        #expect(Status.building(file: "keymap.c", done: 0, total: 0).look.progress == .determinate(0), "no division by zero")
        #expect(Status.writing(fraction: 0.64, bytes: 41_984).look.text == "Writing · 64%")
        #expect(Status.waitingForFlashMode.look.progress == .indeterminate)
        #expect(Status.buildFailed(errors: 1, key: 45).look.detail == "1 error · key 45")
        #expect(Status.buildFailed(errors: 2, key: nil).look.detail == "2 errors")
    }

    @Test func busyAndConnected() {
        #expect(!ActivityState().isBusy && !ActivityState().isKeyboardConnected)
        #expect(ActivityState(device: .flashMode, status: .verifying(fraction: 0.4, bytes: 1)).isBusy)
        #expect(!ActivityState(device: .flashMode, status: .flashFailed).isKeyboardConnected, "flash mode is not a live keyboard")
    }
}

/// Spec §13.3 item 6: a press changes only its own key's state.
@MainActor
struct PressedKeysTests {
    @Test func onlyChangedKeysFlip() {
        let pressed = PressedKeys()
        let a = pressed.state(3)
        let b = pressed.state(7)
        pressed.update([3, 9])
        #expect(a.isDown && !b.isDown && pressed.state(9).isDown)
        pressed.update([9])
        #expect(!a.isDown && pressed.state(9).isDown)
        pressed.update([])
        #expect(!pressed.state(9).isDown)
    }
}
