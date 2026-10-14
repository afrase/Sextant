import Accessibility
import AppKit
import Observation
import SextantApplication
import SextantDomain
import SwiftUI

/// A board lens: a way of reading the same board (spec §2.2). Heatmap arrives in v1; Combos and Changes are board modes
/// of their destinations, not lenses, since every case is a View ▸ Lens item (ADR 0037).
public enum Lens: String, CaseIterable, Sendable {
    case keys, lighting

    var title: String {
        switch self {
        case .keys: String(localized: "Keys")
        case .lighting: String(localized: "Lighting")
        }
    }
}

/// The build commands (⌘B, ⌘R, ⌘., ⇧⌘B).
enum BuildCommand {
    case build, buildAndFlash, stop, showLog
}

/// The lens lane's status capsule, by priority: a failed save, restored edits, an error, then live (spec §3.7).
enum LaneStatus: Equatable {
    case issue(text: String, key: KeyRef)
    case live(text: String)
    /// The document came back from its recovery copy (ADR 0032).
    case recovered
    /// The last autosave failed; the edits wait in the recovery copy.
    case saveFailed(String)
}

/// Presentation state for one layout window. It owns the open `EditSession` and asks `Library` for layouts.
@MainActor
@Observable
public final class LayoutWindowModel {
    public let library: Library
    /// The open layout, once loaded.
    public internal(set) var session: EditSession?
    public private(set) var loadError: LibraryError?
    public var legendMode: LegendMode = .symbols
    public var lens: Lens = .keys
    public var columnVisibility: NavigationSplitViewVisibility = .all
    public var showsInspector = true
    /// The live view is on (ADR 0057): Sextant pairs with the keyboard and shows its layer and presses. App-wide, and only
    /// ever turned on by the user.
    public var isLive: Bool {
        get { live?.isLive ?? false }
        set { if newValue { live?.startLive() } else { live?.stopLive() } }
    }
    /// The displayed layer tracks the keyboard's (spec §8.2): the live session's Follow, shared by every window, or a
    /// stand-in where there is no live session (tests, snapshots). Only while a layer arrives: a keyboard held by
    /// Keymapp has Follow on but nothing to follow.
    public var isFollowing: Bool {
        get { live.map { $0.followedLayer != nil } ?? followsWithoutLive }
        set {
            guard let live else { return followsWithoutLive = newValue }
            if newValue { live.follow() } else { live.stopFollowing() }
        }
    }
    /// Device and build status for the toolbar capsule: derived from the live session and Build & Flash
    /// (``liveActivity``), or a fixed value where there is no live session (tests, snapshots).
    public var activity: ActivityState {
        get { live == nil ? fixedActivity : liveActivity }
        set {
            fixedActivity = newValue
            if !newValue.isKeyboardConnected { followsWithoutLive = false }
        }
    }
    /// Live presses; the live session feeds it.
    public let pressedKeys = PressedKeys()
    /// The kind the footer's kind key points at (hover or press).
    var highlightedKind: KeyKind?
    /// A layer whose deletion waits for confirmation because keys still switch to it (spec §6.1).
    var layerPendingDeletion: Int?
    /// App-wide keyboard presence and live state; nil in tests and snapshots without a keyboard.
    @ObservationIgnored let live: LiveSession?
    /// A fresh Import from Oryx flow per sheet; nil where importing is off (tests, snapshots).
    @ObservationIgnored let makeImport: (@MainActor () -> ImportFromOryx)?
    /// The Build & Flash state machine for the open layout; nil where building is off (tests, snapshots).
    @ObservationIgnored let makeBuildFlash: (@MainActor (EditSession) -> BuildFlashSession)?
    /// Which layout the keyboard runs, app-wide; nil in tests and snapshots without a keyboard.
    @ObservationIgnored let onKeyboard: OnKeyboard?
    // MARK: inspector
    /// A key inspector text field (the label or the tapping term) has focus, so ⌘⌫ and ⇧⌘⌫ edit its text rather than
    /// make the key transparent or disable it.
    var isEditingKeyLabel = false

    // MARK: layers
    /// The layer whose name the sidebar is editing in place, by id (spec §6.1).
    var renamingLayerID: String?
    /// A layer waiting for Clear Layer's confirmation.
    var layerPendingClear: Int?
    /// A layer waiting for Clear Key Colours' confirmation (spec §6.2).
    var keyColoursPendingClear: Int?
    /// The layer whose Custom… colour sheet is open.
    var layerPendingColour: Int?
    /// The Lighting lens brush (spec §6.2): its colour, and whether it erases (no own colour) instead.
    var brushColor = KeyboardLayout.defaultSwatch.first ?? HexColor(red: 1, green: 0.58, blue: 0)
    var isErasing = false

    // MARK: picker
    /// The open command palette or keycode picker (spec §5.6, §5.7); nil when closed.
    var palette: Palette?
    /// Bumped when a closed panel hands keyboard focus back to the board.
    var boardFocusRequests = 0
    /// The mouse event number of the click that last closed the palette from outside it (the toolbar's Search toggles).
    var paletteDismissingClick: Int?
    /// Record Key while it listens for the next key on the Mac's keyboard (spec §5.8); nil when off.
    var recorder: KeyRecorder?
    /// A gesture that takes the board's key clicks instead of selection (choosing combo members, Assign to Key); nil
    /// when off.
    var boardPick: BoardPick?
    /// The Macros page's state (spec §6.3).
    let macros = MacrosModel()
    /// The Combos page's state (spec §6.4).
    let combos = CombosModel()
    /// Keycodes assigned from the picker and commands run from the palette, newest first (Suggested, Recent).
    var recentKeycodes: [KeyAction] = []
    var recentCommands: [String] = []

    // MARK: import
    /// The Import from Oryx sheet's flow while the sheet is open (spec §8.1).
    var importFlow: ImportFromOryx?
    /// The open layout's History page and Save Revision sheet (spec §8.7), made per layout.
    var history: HistoryModel?
    /// The sidebar's destination (spec §2.2). A layer is the session's selected layer, so Follow and undo move it too;
    /// choosing one leaves the page for its board.
    public var destination: Destination {
        get { page ?? .layer(session?.selection.layer ?? 0) }
        set {
            guard case let .layer(index) = newValue else {
                // A board pick left for another page would take a later click on the board: choosing a page drops it.
                if newValue != page { boardPick = nil }
                return page = newValue
            }
            page = nil
            session?.select(layer: index)
        }
    }
    /// The page shown instead of the board; nil on the board, never a layer. Views that mustn't depend on the
    /// selected layer read this rather than ``destination``.
    private(set) var page: Destination?
    /// The Firmware Settings section to scroll to (the inspector's Sections list).
    var settingsScrollTarget: String?
    /// The layout whose Rename… alert is showing.
    var layoutPendingRename: UUID?
    /// The layout whose Move to Trash… confirmation is showing.
    var layoutPendingTrash: UUID?
    /// A layout is loading (true until the first ``open(_:)`` finishes), so the empty states wait for it.
    var isOpening = true
    /// File ▸ Export's file waiting for its save panel, or why it couldn't be made or saved.
    var pendingExport: PendingExport?

    // MARK: device
    /// The open layout's Build & Flash, made per layout by `makeBuildFlash`; nil where building is off. Snapshots set
    /// one over fakes.
    public var buildFlash: BuildFlashSession?
    /// The Build & Flash sheet is up. Hide takes it down while the run goes on (spec §7.6).
    var showsBuildSheet = false
    /// The sheet's build log is expanded (⇧⌘B).
    var showsBuildLog = false
    /// Where the Device popover hangs while it is open (spec §8.2).
    var devicePopover: DevicePopoverAnchor?
    /// The layout of the latest import revision, which the keyboard's serial is matched against (ADR 0019).
    var importedLayout: KeyboardLayout?
    private var followsWithoutLive = false
    private var fixedActivity = ActivityState()

    public init(
        library: Library, live: LiveSession? = nil, makeImport: (@MainActor () -> ImportFromOryx)? = nil,
        makeBuildFlash: (@MainActor (EditSession) -> BuildFlashSession)? = nil, onKeyboard: OnKeyboard? = nil
    ) {
        self.library = library
        self.live = live
        self.makeImport = makeImport
        self.makeBuildFlash = makeBuildFlash
        self.onKeyboard = onKeyboard
    }

    /// A window over the composition root's use cases.
    public convenience init(services: SextantServices) {
        self.init(
            library: services.library, live: services.live, makeImport: services.makeImport, makeBuildFlash: services.makeBuildFlash,
            onKeyboard: services.onKeyboard)
    }

    /// Opens `id`, or the most recently modified layout no other window has open when `id` is nil, no longer in the
    /// library (a stale restored window) or open in another window (one window per layout). Leaves `session` nil
    /// when there is none. Returns the id actually opened.
    @discardableResult
    public func open(_ id: UUID?) async -> UUID? {
        isOpening = true
        defer { isOpening = false }
        await library.refresh()
        let known = library.entries.map(\.id)
        let free = { (candidate: UUID) in candidate == self.session?.id || !self.library.isOpen(candidate) }
        guard let target = id.flatMap({ known.contains($0) && free($0) ? $0 : nil }) ?? known.first(where: free) else { return nil }
        guard target != session?.id else { return target }
        do {
            let next = try await library.open(target)
            // A flash that is writing (it may have started during the load) can't be stopped; keep its layout until it
            // ends, so its progress stays in view.
            if buildFlash?.canStop == false {
                await library.close(next)
                return session?.id
            }
            if let old = session {
                // A waiting Build & Flash has no time limit; stop it so it can't flash the next keyboard in flash mode.
                buildFlash?.stop()
                await library.close(old)
                // Undo steps point at the old session; drop them so ⌘Z can't reach a released document.
                old.undoManager?.removeAllActions(withTarget: old)
            }
            session = next
            buildFlash = makeBuildFlash?(next)
            history = HistoryModel(session: next, onKeyboard: onKeyboard)
            loadError = nil
            // Choosing a layout is choosing a destination (spec §2.2): its board, not the last layout's settings page.
            page = nil
            // A pick or a panel's assign target edits the layout it was made for.
            cancelBoardPick()
            palette = nil
            settingsScrollTarget = nil
            if next.recoveredUnsavedChanges { AccessibilityNotification.Announcement(Self.recoveredNotice).post() }
            return target
        } catch {
            loadError = error
            return nil
        }
    }

    /// The window is closing: stops its layout's Build & Flash (see ``open(_:)``) and lets the layout go, so another
    /// window can open it.
    func close() async {
        guard let session else { return }
        buildFlash?.stop()
        await library.close(session)
    }

    // MARK: Derived text

    /// Window subtitle (spec §3.4): the layer, plus " · Edited" when there are edits since the last revision.
    var subtitle: String {
        guard let session else { return "" }
        let layer = session.currentLayer?.title ?? ""
        return session.isEditedSinceRevision ? String(localized: "\(layer) · Edited") : layer
    }

    var readout: String {
        guard let session else { return "" }
        return KeyText.readout(layout: session.layout, layer: session.selection.layer, isFollowing: isFollowing)
    }

    /// Live issues, keyed for the board's rings and badges.
    var issueMap: [KeyRef: LayoutIssue.Severity] {
        guard let session else { return [:] }
        var map: [KeyRef: LayoutIssue.Severity] = [:]
        for issue in LayoutIssues.check(session.layout) {
            guard let key = issue.key else { continue }
            let ref = KeyRef(layer: key.layer, index: key.index)
            if map[ref] != .error { map[ref] = issue.severity }
        }
        for key in compileErrorKeys { map[KeyRef(layer: key.layer, index: key.index)] = .error }
        return map
    }

    /// The restored-edits notice, in the lens lane and for VoiceOver.
    static var recoveredNotice: String { String(localized: "Restored edits that hadn’t been saved") }

    var laneStatus: LaneStatus? {
        guard let session else { return nil }
        // A failed save, then the restored-edits notice: once saved or dismissed, an error capsule comes back.
        if let error = session.saveError { return .saveFailed(error.localizedDescription) }
        if session.recoveredUnsavedChanges { return .recovered }
        if let issue = LayoutIssues.check(session.layout).first(where: { $0.severity == .error && $0.key != nil }), let key = issue.key {
            return .issue(text: KeyText.issueText(issue, layout: session.layout), key: key)
        }
        if let compileError = compileErrorLane { return compileError }
        guard isFollowing else { return nil }
        // Another layout's layers have other names: the keyboard's layer by number.
        if live != nil, !runsThisLayout { return .live(text: String(localized: "LIVE · Layer \(live?.activeLayer ?? 0)")) }
        let layer = session.selection.layer
        let name = session.currentLayer?.title ?? ""
        let held = layer == 0 ? nil : KeyText.activator(layout: session.layout, layer: layer)?.text
        return .live(text: [String(localized: "LIVE"), held.map { "\(name) \($0)" } ?? name].joined(separator: " · "))
    }

    /// Kinds on the shown layer, in kind-key order (spec §3.7). History shows a revision's layer (ADR 0043).
    var kindsOnLayer: [KeyKind] {
        let display = page == .history ? history?.display : nil
        guard let layer = display.map({ $0.layout.layers[safe: $0.layer] }) ?? session?.currentLayer else { return [] }
        let present = Set(layer.keys.map(\.kind))
        return KeyKind.allCases.filter(present.contains)
    }

    /// Honest window minimum (spec §3.2): the centre column's 640 plus each visible column's minimum.
    var minimumWidth: CGFloat {
        640 + (columnVisibility == .detailOnly ? 0 : 200) + (showsInspector ? 280 : 0)
    }

    // MARK: Command enablement

    /// Key commands are off on the pages, where the selected key isn't shown (the selection stays).
    var hasSelectedKey: Bool { page == nil && session?.selection.keyIndex != nil }
    /// A text field may have focus (key label, layer rename, palette, import, layout rename): ⌘⌫ and ⇧⌘⌫ reach the menu
    /// before the field, so they must not edit the selected key.
    var isEditingText: Bool {
        isEditingKeyLabel || renamingLayerID != nil || palette != nil || importFlow != nil || layoutPendingRename != nil
    }
    var canShowPreviousLayer: Bool { (session?.selection.layer ?? 0) > 0 }
    var canShowNextLayer: Bool { session.map { $0.selection.layer < $0.layout.layers.count - 1 } ?? false }
    var canDeleteLayer: Bool { (session?.layout.layers.count ?? 0) > 1 }
    var canOverrideKey: Bool {
        guard page == nil, let session, let index = session.selection.keyIndex else { return false }
        return session.layout.resolvedKey(layer: session.selection.layer, index: index).isInherited
    }
    /// Live View needs a keyboard plugged in (not in flash mode).
    var canGoLive: Bool { connectedKeyboard != nil }
    /// Follow needs a keyboard that reports its layer.
    var canFollow: Bool { session != nil && (live.map { $0.activeLayer != nil } ?? activity.isKeyboardConnected) }
    var canBuild: Bool { buildFlash != nil && session != nil && !activity.isBusy && flashingElsewhere == nil }
    /// Stop is for setting up, building and waiting only: flashing can't be interrupted once it writes (spec §7.4).
    var canStop: Bool {
        guard buildFlash != nil else { return false }
        switch activity.status {
        case .settingUp, .generating, .building, .linking, .waitingForFlashMode: return true
        default: return false
        }
    }

    // MARK: Actions

    /// Returns from a page that hides the board to the shown layer's board. Combos and History show the board, so they
    /// stay while their layer changes.
    func showBoard() { if page?.showsBoard == false { page = nil } }

    // Layer commands act on the shown layer: from a page that hides it, they show the board first.
    func showAdjacentLayer(_ step: Int) {
        guard let session else { return }
        showBoard()
        session.select(layer: session.selection.layer + step)
    }

    func moveLayer(by step: Int) {
        guard let session else { return }
        showBoard()
        session.moveLayer(from: session.selection.layer, to: session.selection.layer + step)
    }

    /// Deletes the shown layer, asking first when keys still switch to it (spec §6.1).
    func requestDeleteLayer() {
        guard let session, canDeleteLayer else { return }
        showBoard()
        let layer = session.selection.layer
        if session.layout.keysActivating(layer: layer).isEmpty {
            session.deleteLayer(layer)
        } else {
            layerPendingDeletion = layer
        }
    }

    /// The alert's message: "3 keys switch to Brd+Sys: key 51 on Main…".
    func deletionMessage(for layer: Int) -> String {
        guard let session else { return "" }
        var seen = Set<KeyRef>()
        let refs = session.layout.keysActivating(layer: layer).filter { seen.insert(KeyRef(layer: $0.layer, index: $0.index)).inserted }
        let name = session.layout.layers[safe: layer]?.title ?? ""
        let list = refs.prefix(3).map { String(localized: "key \($0.index) on \(session.layout.layers[safe: $0.layer]?.title ?? "")") }
        let more = refs.count > 3 ? "…" : ""
        let keys = "\(list.joined(separator: ", "))\(more)"
        return refs.count == 1
            ? String(localized: "1 key switches to \(name): \(keys). It will do nothing.")
            : String(localized: "\(refs.count) keys switch to \(name): \(keys). They will do nothing.")
    }

    /// ⌘B builds quietly, the capsule showing progress; ⌘R also brings up the sheet (spec §7.1).
    func build(_ command: BuildCommand) {
        guard let buildFlash else { return }
        switch command {
        case .build:
            buildFlash.build()
            // Live errors block it; the sheet lists them, or ⌘B would seem to do nothing (spec §7.5).
            if session.map({ LayoutIssues.check($0.layout).contains { $0.severity == .error } }) == true { showsBuildSheet = true }
        case .buildAndFlash:
            buildFlash.buildAndFlash(connectedKeyboard: connectedKeyboard)
            showsBuildSheet = true
        case .stop: buildFlash.stop()
        case .showLog:
            showsBuildLog = true
            showsBuildSheet = true
        }
    }

    func showIssue(_ key: KeyRef) {
        if showMacroIssue(key) { return }
        destination = .layer(key.layer)
        session?.select(key: key.index, slot: key.slot)
    }

    /// A click on a board key, VoiceOver's activate, or ⏎ during a pick: a pick takes the key and ends when it says it is
    /// done; otherwise the key is selected.
    func click(key index: Int) {
        if let pick = boardPick {
            if pick.onPick(index) { boardPick = nil }
        } else {
            session?.select(key: index)
        }
    }

    /// Ends the pick without finishing it (esc, its Cancel button).
    func cancelBoardPick() {
        let pick = boardPick
        boardPick = nil
        pick?.onCancel()
    }

    /// Esc on the board steps back one level (spec §9.3): a pick ends first (step 4), then the key is deselected (step 5).
    func escapeBoard() {
        if boardPick != nil { cancelBoardPick() } else { session?.select(key: nil) }
    }

    /// Opens the layout's package in Finder (File ▸ Show in Finder).
    func showInFinder() async {
        guard let id = session?.id, let url = await library.location(of: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
