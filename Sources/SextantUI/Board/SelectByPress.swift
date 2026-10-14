import Accessibility
import Observation
import SextantApplication
import SextantDomain
import SwiftUI

/// Select Key by Pressing It (⇧⌘L, ADR 0052): the next key pressed on the keyboard is selected on the shown layer. It
/// reads the live session's presses, which flow only while Live View is on and paired.
struct SelectByPress {
    /// Read the keyboard's presses, and watch for what ends the mode, until it ends.
    let tasks: [Task<Void, Never>]
    /// This run, for the endings that wait a moment: a later run must not take them.
    let id = UUID()
    /// The key a press selected. The mode lasts until its key-up, so the Mac's copy of the same press is swallowed.
    var selected: Int?
    /// Esc came from the Mac while armed. It cancels unless the keyboard reports a press within the tail: then it was
    /// the keyboard's own Esc, which is selected.
    var escapePending = false

    /// Waiting for a press: the lens lane shows the capsule.
    var isArmed: Bool { selected == nil }
}

extension LayoutWindowModel {
    /// The Mac's copy of a keyboard press can reach the window just before or just after the keyboard reports it over raw
    /// HID, so the mode waits this long before an esc cancels it, and keeps swallowing this long after the key-up.
    static let selectByPressTail = Duration.milliseconds(50)

    /// Why Select Key by Pressing It can't start now, for the menu item's help tag; nil when it can.
    var selectByPressRefusal: String? {
        guard session != nil else { return String(localized: "Open a layout first.") }
        if page?.showsBoard == false { return String(localized: "Show the board to select a key by pressing it.") }
        if boardPick != nil { return String(localized: "Finish choosing keys on the board first.") }
        switch live?.connection {
        case nil, .noKeyboard?: return String(localized: "Connect your keyboard to select a key by pressing it.")
        case .bootloader?: return String(localized: "The keyboard is in flash mode.")
        case .liveOff?: return String(localized: "Turn on Live View (Keyboard ▸ Live View) to select a key by pressing it.")
        case .heldByAnotherApp?: return DeviceError.heldByAnotherApp.localizedDescription
        case .connected?: return live?.canSend == true ? nil : String(localized: "Live View is still connecting to the keyboard.")
        }
    }

    /// Waiting for a press on the keyboard.
    var selectsByPress: Bool { selectByPress?.isArmed == true }
    /// Secure input is on, so the keyboard's presses don't reach Sextant: the mode waits.
    var selectByPressIsPaused: Bool { live?.isSecureInputOn == true }

    /// Key ▸ Select Key by Pressing It (⇧⌘L). It ends Record Key and Record Steps and closes the palette, which would
    /// take the same press.
    public func startSelectByPress() {
        guard selectByPressRefusal == nil, let live else { return }
        endSelectByPress()
        (palette, recorder, macros.stepRecorder) = (nil, nil, nil)
        // Subscribed now, so a press made right after the menu click isn't missed.
        let presses = live.activity()
        selectByPress = SelectByPress(tasks: [
            Task { [weak self] in await self?.listen(to: presses) }, Task { [weak self] in await self?.watchForEnd() },
        ])
        AccessibilityNotification.Announcement(String(localized: "Press a key on the keyboard to select it.")).post()
    }

    /// Ends the mode: esc, Cancel, the window resigning key, or anything that rules it out.
    func endSelectByPress() {
        selectByPress?.tasks.forEach { $0.cancel() }
        selectByPress = nil
    }

    /// A key event from Sextant's own window while the mode is on (the local monitor Record Key shares). Every one is
    /// swallowed, so the Mac's copy of the keyboard's press reaches neither type-to-search nor the esc ladder.
    func selectByPressTakes(keyCode: UInt16, isKeyDown: Bool) -> Bool {
        guard var mode = selectByPress else { return false }
        if isKeyDown, keyCode == 0x35, mode.isArmed, !mode.escapePending {
            mode.escapePending = true
            selectByPress = mode
            endSelectByPressSoon(onlyOnEscape: true)
        }
        return true
    }

    /// Anything that rules the mode out ends it (the board hidden, a pick, the session dropping, Record Key, Record Steps
    /// or the palette), and so does secure input while it waits for the key-up, which then never arrives.
    private var selectByPressEnds: Bool {
        guard let mode = selectByPress else { return true }
        if selectByPressRefusal != nil || palette != nil || recorder != nil || macros.stepRecorder != nil { return true }
        return !mode.isArmed && selectByPressIsPaused
    }

    private func listen(to presses: AsyncStream<LiveActivity>) async {
        for await event in presses {
            guard selectByPress != nil else { break }
            take(event)
        }
    }

    private func watchForEnd() async {
        for await ends in Observations({ [weak self] in self?.selectByPressEnds ?? true }) where ends {
            endSelectByPress()
            break
        }
    }

    private func take(_ event: LiveActivity) {
        guard var mode = selectByPress else { return }
        switch event {
        case let .keyDown(index, _) where mode.isArmed:
            // No press arrives during secure input: the feed asks at every event, unlike the once-a-second flag the
            // capsule reads.
            guard selectByPressRefusal == nil, let session, index < session.layout.keyCount else { return }
            (mode.selected, mode.escapePending) = (index, false)
            selectByPress = mode
            click(key: index)
            let legend = Legends.legend(layout: session.layout, layer: session.selection.layer, index: index)
            AccessibilityNotification.Announcement(String(localized: "Selected key \(index), \(KeyText.label(legend, index: index))"))
                .post()
        case let .keyUp(index) where index == mode.selected:
            endSelectByPressSoon(onlyOnEscape: false)
        default:
            break
        }
    }

    /// Ends this run after the tail: an esc only if no press came meanwhile.
    private func endSelectByPressSoon(onlyOnEscape: Bool) {
        guard let id = selectByPress?.id else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.selectByPressTail)
            guard let self, let mode = selectByPress, mode.id == id, !onlyOnEscape || (mode.isArmed && mode.escapePending) else { return }
            endSelectByPress()
        }
    }
}

/// The lens lane's capsule while the mode waits for a press (spec §3.7), with [Cancel].
struct SelectByPressCapsule: View {
    var model: LayoutWindowModel

    var body: some View {
        HStack(spacing: 8) {
            if model.selectByPressIsPaused {
                Image(systemName: "eye.slash").foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Paused: secure input is on · esc cancels").lineLimit(1)
            } else {
                Image(systemName: "keyboard").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text("Press a key on the keyboard… esc cancels").lineLimit(1)
            }
            Button("Cancel") { model.endSelectByPress() }.buttonStyle(.borderless)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
    }
}
