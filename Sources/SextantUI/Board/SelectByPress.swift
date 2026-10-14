import Accessibility
import Observation
import SextantApplication
import SextantDomain
import SwiftUI

/// Select Key by Pressing It (⇧⌘L, ADR 0052): the next key pressed on the keyboard is selected on the shown layer. It
/// reads the live session's presses, which flow only while Live View is on and paired.
struct SelectByPress {
    /// Read the keyboard's presses, and watch for what ends the mode, until it ends.
    var tasks: [Task<Void, Never>]
    /// This run, for the endings that wait a moment: a later run must not take them.
    let id = UUID()
    /// When it started: a press the keyboard reports within the tail is ⇧⌘L itself, typed on the keyboard.
    let start = ContinuousClock.now
    /// Keys held when it started, such as the ⇧ and ⌘ of ⇧⌘L typed on the keyboard: until they are up, a press is still
    /// part of the shortcut.
    var heldAtStart: Set<Int>
    /// The key a press selected. The mode lasts until its key-up, so the Mac's copy of the same press is swallowed.
    var selected: Int?
    /// When the press was selected: the Mac's copy of it arrives within the tail, later Mac escs are the user's.
    var selectedAt: ContinuousClock.Instant?
    /// How long the Mac's copy can come after the selected key's key-up: a tap dance sends it a tapping term later.
    var releaseTail: Duration
    /// Esc came from the Mac while armed. It cancels unless the keyboard reports a press within the tail: then it was
    /// the keyboard's own Esc, which is selected.
    var escapePending = false

    /// Waiting for a press: the lens lane shows the capsule.
    var isArmed: Bool { selected == nil }
}

extension LayoutWindowModel {
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

    /// What the capsule says while waiting, and VoiceOver hears.
    var selectByPressPrompt: String {
        selectByPressIsPaused
            ? String(localized: "Paused: secure input is on · esc cancels") : String(localized: "Press a key on the keyboard to select it")
    }

    /// Key ▸ Select Key by Pressing It (⇧⌘L). It ends Record Key and Record Steps and closes the palette, which would
    /// take the same press.
    public func startSelectByPress() {
        guard selectByPressRefusal == nil, let live else { return }
        selectByPress?.tasks.forEach { $0.cancel() }
        (palette, recorder, macros.stepRecorder) = (nil, nil, nil)
        // Subscribed now, so a press made right after the menu click isn't missed.
        let presses = live.activity()
        selectByPress = SelectByPress(
            tasks: [
                Task { [weak self] in await self?.listen(to: presses) }, Task { [weak self] in await self?.watchForEnd() },
                Task { [weak self] in await self?.pruneHeldAtStart() },
            ],
            heldAtStart: live.pressedKeys, releaseTail: selectByPressTail)
        AccessibilityNotification.Announcement(selectByPressPrompt).post()
    }

    /// Ends the mode: esc, Cancel, the window resigning key, or anything that rules it out. VoiceOver hears it when it
    /// ends before a press, since the capsule just goes.
    func endSelectByPress() {
        guard let mode = selectByPress else { return }
        mode.tasks.forEach { $0.cancel() }
        selectByPress = nil
        if mode.isArmed { AccessibilityNotification.Announcement(String(localized: "Stopped selecting a key by pressing it.")).post() }
    }

    /// A key event from Sextant's own window while the mode is on (the local monitor Record Key shares). Every one is
    /// swallowed, so the Mac's copy of the keyboard's press reaches neither type-to-search nor the esc ladder.
    func selectByPressTakes(keyCode: UInt16, isKeyDown: Bool) -> Bool {
        guard var mode = selectByPress else { return false }
        guard isKeyDown, keyCode == 0x35 else { return true }
        if mode.isArmed, !mode.escapePending {
            mode.escapePending = true
            selectByPress = mode
            endSelectByPressSoon(after: selectByPressTail, onlyOnEscape: true)
        } else if let at = mode.selectedAt, ContinuousClock.now - at > selectByPressTail {
            // Not the selected key's own copy, which comes within the tail (the monitor drops its repeats): the user's
            // esc, so a lost key-up can't leave the window deaf.
            endSelectByPress()
        }
        return true
    }

    /// Anything that rules the mode out ends it: the board hidden, a pick, the session dropping, Record Key, Record Steps
    /// or the palette.
    private var selectByPressEnds: Bool {
        guard selectByPress != nil else { return true }
        return selectByPressRefusal != nil || palette != nil || recorder != nil || macros.stepRecorder != nil
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

    /// The selected key's release as the session's held keys show it, which change even when the per-event secure
    /// input check drops its key-up, and empty while secure input is on.
    private func watchRelease(of index: Int, since selectedAt: ContinuousClock.Instant) async {
        var held = false
        for await keys in Observations({ [weak self] in self?.live?.pressedKeys ?? [] }) {
            if keys.contains(index) {
                held = true
                continue
            }
            if held { break }
            // This task can start after the key-up, or after secure input hid the key, and then never sees it held; the
            // held keys update a frame late, so an absence counts once that frame has passed.
            try? await Task.sleep(until: selectedAt + .milliseconds(100), clock: .continuous)
            guard live?.pressedKeys.contains(index) == true else { break }
            held = true
        }
        guard !Task.isCancelled, let tail = selectByPress?.releaseTail else { return }
        endSelectByPressSoon(after: tail, onlyOnEscape: false)
    }

    /// A key held at start whose key-up came before the start (the held keys update a frame late) stops counting once that
    /// frame has passed. Only then: later the held keys can run ahead of the presses still on their way, and the presses'
    /// own key-ups take the rest out.
    private func pruneHeldAtStart() async {
        try? await Task.sleep(for: selectByPressTail)
        guard !Task.isCancelled, var mode = selectByPress, let live else { return }
        mode.heldAtStart.formIntersection(live.pressedKeys)
        selectByPress = mode
    }

    private func take(_ event: LiveActivity) {
        guard var mode = selectByPress else { return }
        switch event {
        case let .keyDown(index, layer) where mode.isArmed:
            // No press arrives during secure input: the feed asks at every event, unlike the once-a-second flag the
            // capsule reads.
            guard selectByPressRefusal == nil, let session, index < session.layout.keyCount else { return }
            guard mode.heldAtStart.isEmpty, ContinuousClock.now - mode.start >= selectByPressTail else {
                selectByPress = mode
                return
            }
            let selectedAt = ContinuousClock.now
            (mode.selected, mode.selectedAt, mode.escapePending) = (index, selectedAt, false)
            mode.releaseTail = selectByPressReleaseTail(index: index, layer: layer)
            mode.tasks.append(Task { [weak self] in await self?.watchRelease(of: index, since: selectedAt) })
            selectByPress = mode
            click(key: index)
            AccessibilityNotification.Announcement(selectByPressAnnouncement(index: index)).post()
        case let .keyUp(index) where mode.isArmed:
            mode.heldAtStart.remove(index)
            selectByPress = mode
        case let .keyUp(index) where index == mode.selected:
            endSelectByPressSoon(after: mode.releaseTail, onlyOnEscape: false)
        default:
            break
        }
    }

    /// "Selected key 24, Return, hold for Sym+Num", from the board as shown: on History, the revision's layer.
    func selectByPressAnnouncement(index: Int) -> String {
        let display = page == .history ? history?.display : nil
        guard let layout = display?.layout ?? session?.layout, let layer = display?.layer ?? session?.selection.layer else { return "" }
        let legend = Legends.legend(layout: layout, layer: layer, index: index)
        return String(localized: "Selected key \(index), \(KeyText.label(legend, index: index))")
    }

    /// The tail after the selected key's key-up, from the key the keyboard ran: a tap dance sends its tap only once the
    /// tapping term has passed without another tap, so its Mac copy comes that much later.
    private func selectByPressReleaseTail(index: Int, layer: Int) -> Duration {
        guard let layout = session?.layout, layout.layers.indices.contains(layer) else { return selectByPressTail }
        let key = layout.resolvedKey(layer: layer, index: index).effective
        guard key.usesTappingTerm else { return selectByPressTail }
        let term = layout.perKeyTappingTermsOn ? key.tappingTerm ?? layout.globalTappingTerm : layout.globalTappingTerm
        return .milliseconds(term) + selectByPressTail
    }

    /// Ends this run after `tail`: an esc only if no press came meanwhile.
    private func endSelectByPressSoon(after tail: Duration, onlyOnEscape: Bool) {
        guard let id = selectByPress?.id else { return }
        Task { [weak self] in
            try? await Task.sleep(for: tail)
            guard let self, let mode = selectByPress, mode.id == id, !onlyOnEscape || (mode.isArmed && mode.escapePending) else { return }
            endSelectByPress()
        }
    }
}

/// The lens lane's capsule while the mode waits for a press (spec §3.7), with [Cancel]. It doesn't promise esc while it
/// listens: with the keyboard as the Mac's only one, its Esc is a press to select.
struct SelectByPressCapsule: View {
    var model: LayoutWindowModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.selectByPressIsPaused ? "eye.slash" : "keyboard")
                .foregroundStyle(model.selectByPressIsPaused ? Color.secondary : Color.accentColor).accessibilityHidden(true)
            Text(model.selectByPressPrompt).lineLimit(1)
            Button("Cancel") { model.endSelectByPress() }.buttonStyle(.borderless)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .surface(Capsule(), interactive: true)
        .onChange(of: model.selectByPressIsPaused) { AccessibilityNotification.Announcement(model.selectByPressPrompt).post() }
    }
}
