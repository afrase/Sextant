import Foundation
import Observation
import SextantApplication
import SextantDomain

/// Where the Device popover hangs (spec §8.2): the capsule's device segment or the sidebar's device card.
enum DevicePopoverAnchor { case capsule, card }

extension LayoutWindowModel {
    /// The capsule for a window with a live session (spec §3.5): a running or finished Build & Flash, then live
    /// issues, then a revision read from the keyboard to use (ADR 0061), then the keyboard against the open layout.
    var liveActivity: ActivityState {
        guard let live else { return ActivityState() }
        let match = firmwareMatch
        let errors = session.map { LayoutIssues.check($0.layout).filter { $0.severity == .error } } ?? []
        let pulled = keyboardRevision.map { ActivityState.Status.keyboardRunsRevision(number: $0.number) }
        let status =
            buildFlash.flatMap { ActivityState.Status($0.phase, usedBytes: $0.usedBytes, capacity: $0.capacity) }
            ?? flashingElsewhere.map { .flashingElsewhere(layout: $0) }
            ?? (errors.isEmpty ? nil : .issues(count: errors.count, firstKey: errors.first?.key?.index))
            ?? pulled
            ?? ActivityState.Status(
                live.connection, match: match, serial: live.firmwareSerial, edits: editsSinceImport,
                revisionDate: session?.revisions.last?.createdAt, layoutOpen: session != nil,
                runningTitle: onKeyboard?.running?.entry.title)
        let device = ActivityState.Device(live.connection, serial: live.firmwareSerial, match: match, layoutOpen: session != nil)
        return ActivityState(device: device, status: status)
    }

    /// The title of the layout another window is flashing (spec §7.6): this window's Build & Flash waits its turn.
    /// By run, not layout: a closed window's flash of the layout reopened here is still another window's.
    var flashingElsewhere: String? {
        guard let live, let id = live.flashingLayoutID, live.flashingOwner != buildFlash.map(ObjectIdentifier.init) else { return nil }
        return library.entries.first { $0.id == id }?.title ?? ""
    }

    /// Compile errors the source map placed on a key (spec §7.5): their caps ring until the next build.
    var compileErrorKeys: [KeyRef] { buildFlash?.diagnostics.filter { $0.severity == .error }.compactMap(\.key) ?? [] }

    /// The lens lane's capsule for the first compile error on a key: "Build error on Brd+Sys · key 45 · Tap".
    var compileErrorLane: LaneStatus? {
        guard let key = compileErrorKeys.first, let layout = session?.layout else { return nil }
        var parts = [
            String(localized: "Build error on \(layout.layers[safe: key.layer]?.title ?? "")"), String(localized: "key \(key.index)"),
        ]
        if let slot = key.slot { parts.append(slot.title) }
        return .issue(text: parts.joined(separator: " · "), key: key)
    }

    /// How the keyboard's firmware relates to the open layout; nil without a serial or an open layout.
    var firmwareMatch: FirmwareMatch? {
        guard let live, let session else { return nil }
        let aliases = library.entries.first { $0.id == session.id }?.aliases ?? []
        return live.match(session.layout, libraryID: session.id, aliases: aliases, importedLayout: device.importedLayout)
    }

    /// The keyboard's Oryx serial when no library layout came from that Oryx layout: the card offers [Import] (spec §3.6).
    var unknownOryxSerial: String? {
        let serial = Self.oryxSerial(live?.firmwareSerial)
        return Self.oryxLayoutInLibrary(serial, entries: library.entries) ? nil : serial
    }

    /// Whether `serial` is an Oryx serial (`layout/revision`) of an Oryx layout a library layout came from.
    static func oryxLayoutInLibrary(_ serial: String?, entries: [LibraryEntry]) -> Bool {
        guard let serial = oryxSerial(serial), let slash = serial.firstIndex(of: "/") else { return false }
        let layoutID = serial[..<slash]
        return entries.contains { if case let .oryx(id, _) = $0.origin { id == layoutID } else { false } }
    }

    /// What the card and the Device popover offer while the keyboard runs a layout Sextant doesn't have (ADR 0061): from
    /// the app's keyboard layout pull, or a fixed value where there is none (tests, snapshots).
    public var keyboardLayoutPrompt: KeyboardLayoutPrompt? {
        get {
            guard let keyboardLayout else { return device.fixedKeyboardLayoutPrompt }
            guard let live, let onKeyboard else { return nil }
            switch live.connection {
            case .connected, .liveOff:
                return KeyboardLayoutPrompt(keyboardLayout.status, live: live, onKeyboard: onKeyboard, entries: library.entries)
            case .noKeyboard, .bootloader, .heldByAnotherApp: return nil
            }
        }
        set { device.fixedKeyboardLayoutPrompt = newValue }
    }

    /// Get Layout and Try Again: reads the layout the keyboard's firmware stores, turning on Live View first. The click is
    /// the consent (ADR 0057).
    func getKeyboardLayout() {
        guard let keyboardLayout else { return }
        Task { await keyboardLayout.read(startingLiveView: true) }
    }

    /// The revision [Use It] restores (ADR 0061): Sextant read the keyboard's layout and added it to this layout's History
    /// without making it the working copy, the keyboard still runs it, and the working copy differs from it. Not while
    /// another app holds the keyboard: the capsule says Keymapp has it instead.
    var keyboardRevision: RevisionSummary? {
        switch live?.connection {
        case .connected, .liveOff: break
        default: return nil
        }
        guard let session, case let .added(added)? = keyboardLayout?.status, added.entryID == session.id, !added.adopted,
            let revision = added.revision, let running = onKeyboard?.running, running.entry.id == session.id,
            running.revision?.id == revision.id
        else { return nil }
        return Self.differs(session.layout, from: running.layout) ? revision : nil
    }

    /// Whether Use It would change the working copy. Its title counts, since Use It takes the keyboard's, which is part of
    /// the fingerprint; its macro drafts don't, since they never reach the keyboard (ADR 0042) and Use It keeps them.
    static func differs(_ working: KeyboardLayout, from keyboard: KeyboardLayout) -> Bool {
        var keyboard = keyboard
        keyboard.macroDrafts = working.macroDrafts
        return keyboard != working
    }

    /// [Use It]: makes the revision the keyboard runs the working copy exactly, title included, as one undoable edit that
    /// records unsaved edits in History first. Then the offer ends, so later edits don't bring it back. A failure shows on
    /// the History page, and the offer stays.
    func useKeyboardRevision() {
        guard let history, !history.isRestoring, let revision = keyboardRevision else { return }
        let (pull, offer) = (keyboardLayout, keyboardLayout?.status)
        Task {
            await history.restore(revision, asOnKeyboard: true)
            if history.error != nil {
                self.destination = .history
            } else if let pull, pull.status == offer {
                pull.dismiss()
            }
        }
    }

    /// The keyboard in normal mode, for Build & Flash's "replace the layout on this keyboard?" check.
    var connectedKeyboard: KeyboardDevice? {
        switch live?.connection {
        case let .connected(keyboard), let .heldByAnotherApp(keyboard), let .liveOff(keyboard): keyboard
        default: nil
        }
    }

    /// Key edits since the import, when the keyboard runs that import's Oryx build; otherwise (or when only layers or
    /// settings changed) Sextant can't count them.
    private var editsSinceImport: Int? {
        guard let session, let imported = device.importedLayout, let serial = imported.oryx?.serial, serial == live?.firmwareSerial else {
            return nil
        }
        let count = session.layout.diff(from: imported).keyChanges.count
        return count > 0 ? count : nil
    }

    /// Feeds the window from the keyboard for its lifetime (spec §8.2): presses light the board unless Settings ›
    /// Keyboard turns them off, the shown layer tracks the keyboard's while following, and choosing a layer by hand
    /// (sidebar, ⌘1–9, the jump menu, Show Key) stops following. Also loads the import the serial is matched against. The
    /// window runs it; snapshots run it for views shown without a window.
    public func followKeyboard(settings: UserDefaults = .standard) async {
        guard let live else { return }
        let showsPresses = ObservedSetting(SettingsKey.showsKeyPresses, default: true, in: settings)
        var last: LiveInputs?
        for await now in Observations({ LiveInputs(live: live, session: self.session, showsPresses: showsPresses.isOn) }) {
            pressedKeys.update(now.pressed)
            if now.document != last?.document { device.importedLayout = await buildFlash?.importedLayout() }
            if now.followed != last?.followed || now.document?.id != last?.document?.id {
                // Another layout's layer numbers mean other layers: leave the shown one alone.
                if let layer = now.followed, runsThisLayout { session?.select(layer: layer) }
            } else if live.isFollowing, now.layer != last?.layer {
                live.stopFollowing()
            }
            last = now
            last?.layer = session?.selection.layer  // the layer as Follow left it, so its own choice isn't taken for a hand's
        }
    }
}

/// What ``LayoutWindowModel/followKeyboard()`` reacts to.
private struct LiveInputs: Equatable, Sendable {
    struct Document: Equatable, Sendable {
        var id: UUID
        /// The latest import revision: a new import changes what the serial is matched against.
        var importID: String?
    }

    var followed: Int?
    var pressed: Set<Int>
    var layer: Int?
    var document: Document?

    @MainActor
    init(live: LiveSession, session: EditSession?, showsPresses: Bool) {
        followed = live.followedLayer
        pressed = showsPresses ? live.pressedKeys : []
        layer = session?.selection.layer
        document = session.map { Document(id: $0.id, importID: $0.revisions.last { $0.source == .import }?.id) }
    }
}

/// A Bool setting as observable state, so ``LayoutWindowModel/followKeyboard(settings:)`` reacts the moment it changes
/// (Settings or the Device popover), not at the next press.
@MainActor
@Observable
private final class ObservedSetting {
    private(set) var isOn = false
    @ObservationIgnored private let read: () -> Bool
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(_ key: String, default value: Bool, in defaults: UserDefaults) {
        read = { defaults.object(forKey: key) as? Bool ?? value }
        isOn = read()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                if let self, self.isOn != self.read() { self.isOn.toggle() }
            }
        }
    }

    isolated deinit { observer.map(NotificationCenter.default.removeObserver) }
}

extension ActivityState.Device {
    /// With no layout open, there is nothing for the keyboard to differ from.
    init(_ connection: LiveSession.Connection, serial: String?, match: FirmwareMatch?, layoutOpen: Bool = true) {
        switch connection {
        case .noKeyboard: self = .absent
        case .bootloader: self = .flashMode
        case .connected, .heldByAnotherApp, .liveOff:
            self = .connected(serial: serial, matchesLayout: !layoutOpen || match == .current || match == .thisLayout)
        }
    }
}

extension ActivityState.Status {
    /// What a Build & Flash phase shows; nil where the keyboard's status shows instead (idle, a question on the sheet,
    /// blocked, whose issues the live issues already show, or turned away because another window is flashing).
    init?(_ phase: BuildFlashSession.Phase, usedBytes: Int?, capacity: Int) {
        func fraction(_ done: Int, _ total: Int) -> Double { total > 0 ? Double(done) / Double(total) : 0 }
        switch phase {
        case .idle, .blocked, .confirmingReplace, .failed(.flashingElsewhere): return nil
        case .needsSetup: self = .needsSetup
        case let .settingUp(received, total): self = .settingUp(fraction: total > 0 ? Double(received) / Double(total) : 0)
        case .generating: self = .generating
        case let .compiling(file, done, total): self = .building(file: file, done: done, total: total)
        case .linking: self = .linking
        case .built:
            let used = usedBytes ?? 0
            self = .built(bytes: used, percentOfFlash: Int((fraction(used, capacity) * 100).rounded()))
        case .waitingForFlashMode: self = .waitingForFlashMode
        case .validating: self = .erasing(fraction: 0)
        case let .erasing(done, total): self = .erasing(fraction: fraction(done, total))
        case let .writing(done, total): self = .writing(fraction: fraction(done, total), bytes: done)
        case .verifying: self = .verifying
        case let .done(revision?, nil): self = .flashed(revision: String(localized: "revision \(revision.number)"))
        case .done: self = .flashedNotSaved
        case let .failed(.toolchain(.compileFailed(diagnostics))):
            let errors = diagnostics.filter { $0.severity == .error }
            self = .buildFailed(errors: max(errors.count, 1), key: errors.lazy.compactMap(\.key).first?.index)
        case let .failed(.generator(.unsupported(_, key))): self = .buildFailed(errors: 1, key: key?.index)
        case .failed(.generator), .failed(.toolchain): self = .buildFailed(errors: 1, key: nil)
        // Try Again goes back through the setup question.
        case .failed(.setup): self = .needsSetup
        case .failed: self = .flashFailed
        }
    }

    /// The keyboard against the open layout (spec §3.5). Without a serial Sextant can't tell, so it says another layout;
    /// with no layout open (first launch, §12.1) there is nothing to differ from.
    init(
        _ connection: LiveSession.Connection, match: FirmwareMatch?, serial: String?, edits: Int?, revisionDate: Date?,
        layoutOpen: Bool = true, runningTitle: String? = nil
    ) {
        switch connection {
        case .noKeyboard: self = .noKeyboard
        case .bootloader: self = .inFlashMode
        case .heldByAnotherApp: self = .heldByAnotherApp("Keymapp")
        case .connected, .liveOff:
            switch match {
            case _ where !layoutOpen: self = .keyboardConnected
            case .current: self = .onKeyboard(revisionDate: revisionDate ?? .now)
            case .thisLayout: self = .notOnKeyboard(edits: edits)
            case .otherLayout, nil: self = .otherLayout(name: runningTitle)
            }
        }
    }
}
