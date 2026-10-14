import Accessibility
import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// Record Key (spec §5.8): turns the next key pressed on the Mac's keyboard into a QMK keycode. Positional: it reads
/// the virtual keycode (`kVK_*`), never the character, so it works on any input source (§13.3 item 10).
struct KeyRecorder: Equatable {
    enum Outcome: Equatable {
        case assign(code: String, modifiers: Modifiers)
        case cancel
        case unmapped
    }

    /// The key being recorded; choosing another key ends recording.
    let target: Int
    /// The layer it is on, by id: Follow moves the board while a layer key is held, not the key being recorded.
    var layerID = ""
    /// A modifier pressed on its own; released before any other key, it is the key to assign (Right Shift).
    private(set) var loneModifier: UInt16?
    /// The last key couldn't be mapped; the capsule says so and recording goes on.
    var cannotMap = false

    mutating func keyDown(_ keyCode: UInt16, flags: UInt) -> Outcome {
        loneModifier = nil
        // Esc always cancels and is never recorded; the picker assigns it.
        if keyCode == 0x35 { return .cancel }
        guard let code = Self.codes[keyCode] else { return .unmapped }
        return .assign(code: code, modifiers: Self.modifiers(flags))
    }

    mutating func flagsChanged(_ keyCode: UInt16, flags: UInt) -> Outcome? {
        if keyCode == 0x39 { return .assign(code: "KC_CAPS", modifiers: []) }
        guard let key = Self.modifierKeys[keyCode] else { return keyCode == 0x3F ? .unmapped : nil }  // fn has no QMK code
        if flags & key.deviceBit != 0 {
            loneModifier = Self.modifiers(flags) == key.modifier ? keyCode : nil
            return nil
        }
        guard loneModifier == keyCode else { return nil }
        loneModifier = nil
        return .assign(code: key.code, modifiers: [])
    }

    /// Held modifiers with their side, from the device-dependent bits of `NSEvent.ModifierFlags` (`NX_DEVICE*KEYMASK`).
    /// Events without them (synthesized ones) count as the left side.
    static func modifiers(_ flags: UInt) -> Modifiers {
        var mods: Modifiers = []
        for key in modifierKeys.values where flags & key.deviceBit != 0 { mods.insert(key.modifier) }
        let sides: [(UInt, Modifiers, Modifiers)] = [
            (1 << 17, .leftShift, [.leftShift, .rightShift]), (1 << 18, .leftControl, [.leftControl, .rightControl]),
            (1 << 19, .leftOption, [.leftOption, .rightOption]), (1 << 20, .leftCommand, [.leftCommand, .rightCommand]),
        ]
        for (flag, left, either) in sides where flags & flag != 0 && mods.isDisjoint(with: either) { mods.insert(left) }
        return mods
    }

    private static let modifierKeys: [UInt16: (code: String, modifier: Modifiers, deviceBit: UInt)] = [
        0x3B: ("KC_LEFT_CTRL", .leftControl, 0x1), 0x38: ("KC_LEFT_SHIFT", .leftShift, 0x2), 0x3C: ("KC_RIGHT_SHIFT", .rightShift, 0x4),
        0x37: ("KC_LEFT_GUI", .leftCommand, 0x8), 0x36: ("KC_RIGHT_GUI", .rightCommand, 0x10), 0x3A: ("KC_LEFT_ALT", .leftOption, 0x20),
        0x3D: ("KC_RIGHT_ALT", .rightOption, 0x40), 0x3E: ("KC_RIGHT_CTRL", .rightControl, 0x2000),
    ]

    /// macOS virtual keycodes (Carbon `kVK_*`: ANSI, ISO and JIS) to catalog keycodes.
    static let codes: [UInt16: String] = [
        // Letters and digits (kVK_ANSI_*).
        0x00: "KC_A", 0x0B: "KC_B", 0x08: "KC_C", 0x02: "KC_D", 0x0E: "KC_E", 0x03: "KC_F", 0x05: "KC_G", 0x04: "KC_H", 0x22: "KC_I",
        0x26: "KC_J", 0x28: "KC_K", 0x25: "KC_L", 0x2E: "KC_M", 0x2D: "KC_N", 0x1F: "KC_O", 0x23: "KC_P", 0x0C: "KC_Q", 0x0F: "KC_R",
        0x01: "KC_S", 0x11: "KC_T", 0x20: "KC_U", 0x09: "KC_V", 0x0D: "KC_W", 0x07: "KC_X", 0x10: "KC_Y", 0x06: "KC_Z",
        0x12: "KC_1", 0x13: "KC_2", 0x14: "KC_3", 0x15: "KC_4", 0x17: "KC_5", 0x16: "KC_6", 0x1A: "KC_7", 0x1C: "KC_8", 0x19: "KC_9",
        0x1D: "KC_0",
        // Punctuation, including ISO § (kVK_ISO_Section).
        0x1B: "KC_MINUS", 0x18: "KC_EQUAL", 0x21: "KC_LBRC", 0x1E: "KC_RBRC", 0x2A: "KC_BSLS", 0x29: "KC_SCLN", 0x27: "KC_QUOTE",
        0x32: "KC_GRAVE", 0x2B: "KC_COMMA", 0x2F: "KC_DOT", 0x2C: "KC_SLASH", 0x0A: "KC_NONUS_BACKSLASH",
        // Editing and navigation. Help sits where Insert is on a PC keyboard.
        0x24: "KC_ENTER", 0x30: "KC_TAB", 0x31: "KC_SPACE", 0x33: "KC_BSPC", 0x75: "KC_DELETE", 0x72: "KC_INSERT",
        0x73: "KC_HOME", 0x77: "KC_END", 0x74: "KC_PAGE_UP", 0x79: "KC_PGDN",
        0x7B: "KC_LEFT", 0x7C: "KC_RIGHT", 0x7D: "KC_DOWN", 0x7E: "KC_UP", 0x6E: "KC_APPLICATION",
        // Function keys.
        0x7A: "KC_F1", 0x78: "KC_F2", 0x63: "KC_F3", 0x76: "KC_F4", 0x60: "KC_F5", 0x61: "KC_F6", 0x62: "KC_F7", 0x64: "KC_F8",
        0x65: "KC_F9", 0x6D: "KC_F10", 0x67: "KC_F11", 0x6F: "KC_F12", 0x69: "KC_F13", 0x6B: "KC_F14", 0x71: "KC_F15", 0x6A: "KC_F16",
        0x40: "KC_F17", 0x4F: "KC_F18", 0x50: "KC_F19", 0x5A: "KC_F20",
        // Volume keys on keyboards that send them.
        0x48: "KC_AUDIO_VOL_UP", 0x49: "KC_AUDIO_VOL_DOWN", 0x4A: "KC_AUDIO_MUTE",
        // Keypad. Clear sits where Num Lock is.
        0x52: "KC_KP_0", 0x53: "KC_KP_1", 0x54: "KC_KP_2", 0x55: "KC_KP_3", 0x56: "KC_KP_4", 0x57: "KC_KP_5", 0x58: "KC_KP_6",
        0x59: "KC_KP_7", 0x5B: "KC_KP_8", 0x5C: "KC_KP_9", 0x41: "KC_KP_DOT", 0x43: "KC_KP_ASTERISK", 0x45: "KC_KP_PLUS",
        0x4B: "KC_KP_SLASH", 0x4E: "KC_KP_MINUS", 0x4C: "KC_KP_ENTER", 0x51: "KC_KP_EQUAL", 0x47: "KC_NUM_LOCK",
        // JIS: ¥, _, keypad comma, 英数 and かな.
        0x5D: "KC_INTERNATIONAL_3", 0x5E: "KC_INTERNATIONAL_1", 0x5F: "KC_KP_COMMA", 0x66: "KC_LANGUAGE_2", 0x68: "KC_LANGUAGE_1",
    ]
}

extension LayoutWindowModel {
    /// Starts Record Key on the selected slot (⇧⌘R). Opening the picker ends it, and so does the reverse.
    public func startRecording() {
        guard let index = session?.selection.keyIndex else { return }
        palette = nil
        recorder = KeyRecorder(target: index, layerID: session?.currentLayer?.id ?? "")
    }

    func cancelRecording() { recorder = nil }

    /// Feeds one key event from Sextant's own window to Record Key. Returns whether the event was consumed.
    @discardableResult
    func record(keyCode: UInt16, flags: UInt, isKeyDown: Bool) -> Bool {
        guard var recorder else { return false }
        let outcome = isKeyDown ? recorder.keyDown(keyCode, flags: flags) : recorder.flagsChanged(keyCode, flags: flags)
        self.recorder = recorder
        switch outcome {
        case .cancel?:
            self.recorder = nil
        case .unmapped?:
            self.recorder?.cannotMap = true
        case let .assign(code, modifiers)?:
            self.recorder = nil
            // Gone (deleted while recording): nothing to assign to.
            guard let session, let layer = session.layout.layers.firstIndex(where: { $0.id == recorder.layerID }) else { break }
            let action = KeyAction(code: code, modifiers: modifiers)
            session.setAction(action, layer: layer, index: recorder.target)
            let names = modifiers.names + [KeycodeCatalog.entry(for: code)?.name ?? code]
            AccessibilityNotification.Announcement(String(localized: "Assigned \(names.joined(separator: " plus "))")).post()
        case nil:
            break
        }
        return true
    }
}

/// Record Steps (spec §6.3): each key pressed on the Mac's keyboard becomes the macro's next step, mapped as Record Key
/// maps it, until esc.
struct StepRecorder {
    let macro: MacroLocator
    /// Record Key's mapping and lone-modifier state; its target key is unused.
    var keys = KeyRecorder(target: 0)
    /// The last recorded step: its index and when its key went down (event time, in seconds).
    var lastStep: (index: Int, time: TimeInterval)?
    /// When the lone modifier went down: it becomes a step on its release, but its time is its press.
    var modifierDown: TimeInterval?
    /// The last key couldn't be mapped; the page says so and recording goes on.
    var cannotMap = false

    /// The wait for the step before a new one at `index`, pressed at `time`: the time since the last recorded key in ms,
    /// rounded to 10 and kept to the 5 s a wait can last. Nil unless that step is the last recorded one (a step clicked
    /// meanwhile keeps its own wait).
    func pause(at time: TimeInterval, inserting index: Int) -> Int? {
        guard let lastStep, lastStep.index == index - 1 else { return nil }
        return min(max(Int(((time - lastStep.time) * 100).rounded()) * 10, 0), Macro.maxDelay)
    }
}

extension LayoutWindowModel {
    /// Feeds one key event from Sextant's own window to Record Steps. Returns whether the event was consumed.
    @discardableResult
    func recordStep(keyCode: UInt16, flags: UInt, isKeyDown: Bool, at time: TimeInterval) -> Bool {
        guard var recorder = macros.stepRecorder else { return false }
        let armed = recorder.keys.loneModifier
        let outcome = isKeyDown ? recorder.keys.keyDown(keyCode, flags: flags) : recorder.keys.flagsChanged(keyCode, flags: flags)
        switch outcome {
        case .cancel?:
            macros.stepRecorder = nil
            return true
        case .unmapped?:
            recorder.cannotMap = true
        case let .assign(code, modifiers)?:
            // Gone (deleted or undone while recording): nothing to record into.
            guard let session, let count = session.layout.macro(at: recorder.macro)?.steps.count else {
                macros.stepRecorder = nil
                return true
            }
            let after = session.selection.macro == recorder.macro ? session.selection.step.map { $0 + 1 } : nil
            let releasesLoneModifier = !isKeyDown && armed == keyCode
            let (index, pressed) = (after ?? count, releasesLoneModifier ? recorder.modifierDown ?? time : time)
            let pause = macros.recordsPauses ? recorder.pause(at: pressed, inserting: index) : nil
            let step = MacroStep(code: code, modifiers: modifiers)
            session.recordStep(step, pause: pause, at: index, in: recorder.macro)
            announce(MacroText.spoken(step, index: index))
            recorder.lastStep = (index, pressed)
            recorder.cannotMap = false
            // Oryx's editor limit, which the page keeps to as well.
            if count + 1 >= Macro.maxSteps {
                macros.stepRecorder = nil
                return true
            }
        case nil:
            if recorder.keys.loneModifier == keyCode { recorder.modifierDown = time }
        }
        macros.stepRecorder = recorder
        return true
    }
}

extension LaneStatus {
    var isIssue: Bool { if case .issue = self { true } else { false } }
}

/// The lens lane's Recording capsule (spec §3.7): red-tinted glass, the prompt and [Cancel].
struct RecordingCapsule: View {
    var model: LayoutWindowModel

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Tokens.danger.color).frame(width: 7, height: 7)
            Text(
                model.recorder?.cannotMap == true
                    ? "Sextant can’t map that key. Try another, or search for it." : "Listening for a key… esc cancels"
            )
            .lineLimit(1)
            Button("Cancel") { model.cancelRecording() }.buttonStyle(.borderless)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(Tokens.danger.color.opacity(0.15)))
        .surface(Capsule(), interactive: true)
    }
}

/// While Record Key or Record Steps runs, a local monitor on Sextant's key window feeds it key-downs and modifier changes
/// (no Input Monitoring, no TCC). Recording ends when the window resigns key or the selected key changes. The global
/// layer shortcuts stand aside meanwhile, or ⌃⌥ digits would move the keyboard instead of being recorded (ADR 0048).
struct RecordKeyMonitor: ViewModifier {
    var model: LayoutWindowModel
    @Environment(LayerShortcuts.self) private var layerShortcuts: LayerShortcuts?

    func body(content: Content) -> some View {
        content
            .task(id: model.recorder != nil || model.macros.stepRecorder != nil) {
                guard model.recorder != nil || model.macros.stepRecorder != nil, let window = NSApp.keyWindow else { return }
                let number = window.windowNumber
                layerShortcuts?.suspend()
                defer { layerShortcuts?.resume() }
                let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                    guard event.windowNumber == number else { return event }
                    let isKeyDown = event.type == .keyDown
                    if isKeyDown && event.isARepeat { return nil }
                    let (code, flags, time) = (event.keyCode, event.modifierFlags.rawValue, event.timestamp)
                    let consumed = MainActor.assumeIsolated {
                        model.record(keyCode: code, flags: flags, isKeyDown: isKeyDown)
                            || model.recordStep(keyCode: code, flags: flags, isKeyDown: isKeyDown, at: time)
                    }
                    return consumed ? nil : event
                }
                for await _ in NotificationCenter.default.notifications(named: NSWindow.didResignKeyNotification, object: window) {
                    model.cancelRecording()
                    model.stopRecordingSteps()
                    break
                }
                if let monitor { NSEvent.removeMonitor(monitor) }
            }
            .onChange(of: model.session?.selection.keyIndex) { _, key in
                if model.recorder?.target != key { model.cancelRecording() }
            }
    }
}
