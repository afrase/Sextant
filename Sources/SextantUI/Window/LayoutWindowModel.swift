import AppKit
import Observation
import SextantApplication
import SextantDomain
import SwiftUI

/// A board lens: a way of reading the same board (spec §2.2). Heatmap, Combos and Changes arrive in v1.
public enum Lens: String, CaseIterable, Sendable {
    case keys, lighting

    var title: String {
        switch self {
        case .keys: String(localized: "Keys")
        case .lighting: String(localized: "Lighting")
        }
    }
}

/// What the build commands ask the composition root to do (⌘B, ⌘R, ⌘., ⇧⌘B).
public enum BuildCommand: Sendable {
    case build, buildAndFlash, stop, showLog
}

/// Runs a build command for a window's layout. The composition root wires it when Build & Flash exists.
/// `.stop` also arrives, idle or not, when the window switches away from a layout or closes.
public typealias BuildHandler = @MainActor (BuildCommand, EditSession) -> Void

/// The lens lane's status capsule, by priority: error, then live (spec §3.7).
enum LaneStatus: Equatable {
    case issue(text: String, key: KeyRef)
    case live(text: String)
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
    /// The displayed layer tracks the keyboard's (spec §8.2). Only meaningful with a keyboard connected.
    public var isFollowing = false
    /// Device and build status for the toolbar capsule; the device and build steps feed it.
    public var activity = ActivityState() {
        didSet { if !activity.isKeyboardConnected { isFollowing = false } }
    }
    /// Live presses; the live session feeds it.
    public let pressedKeys = PressedKeys()
    /// The kind the footer's kind key points at (hover or press).
    var highlightedKind: KeyKind?
    /// A layer whose deletion waits for confirmation because keys still switch to it (spec §6.1).
    var layerPendingDeletion: Int?
    /// Runs the build commands; nil until the composition root wires Build & Flash.
    @ObservationIgnored public var onBuild: BuildHandler?
    /// App-wide keyboard presence and live state; nil in tests and snapshots without a keyboard.
    @ObservationIgnored let live: LiveSession?
    /// A fresh Import from Oryx flow per sheet; nil where importing is off (tests, snapshots).
    @ObservationIgnored let makeImport: (@MainActor () -> ImportFromOryx)?
    /// The Build & Flash state machine for the open layout; nil where building is off (tests, snapshots).
    @ObservationIgnored let makeBuildFlash: (@MainActor (EditSession) -> BuildFlashSession)?

    // MARK: import
    /// The Import from Oryx sheet's flow while the sheet is open (spec §8.1).
    var importFlow: ImportFromOryx?
    /// The sidebar's destination is Firmware Settings rather than a layer (spec §2.2).
    public var showsFirmwareSettings = false
    /// The Firmware Settings section to scroll to (the inspector's Sections list).
    var settingsScrollTarget: String?
    /// The layout whose Rename… alert is showing.
    var layoutPendingRename: UUID?
    /// A layout is loading (true until the first ``open(_:)`` finishes), so the empty states wait for it.
    var isOpening = true

    public init(
        library: Library, onBuild: BuildHandler? = nil, live: LiveSession? = nil,
        makeImport: (@MainActor () -> ImportFromOryx)? = nil,
        makeBuildFlash: (@MainActor (EditSession) -> BuildFlashSession)? = nil
    ) {
        self.library = library
        self.onBuild = onBuild
        self.live = live
        self.makeImport = makeImport
        self.makeBuildFlash = makeBuildFlash
    }

    /// A window over the composition root's use cases.
    public convenience init(services: SextantServices, onBuild: BuildHandler? = nil) {
        self.init(
            library: services.library, onBuild: onBuild, live: services.live, makeImport: services.makeImport,
            makeBuildFlash: services.makeBuildFlash)
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
            if let old = session {
                // A waiting Build & Flash has no time limit; stop it so it can't flash the next keyboard in flash mode.
                onBuild?(.stop, old)
                await library.close(old)
                // Undo steps point at the old session; drop them so ⌘Z can't reach a released document.
                old.undoManager?.removeAllActions(withTarget: old)
            }
            session = next
            loadError = nil
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
        onBuild?(.stop, session)
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
        return map
    }

    var laneStatus: LaneStatus? {
        guard let session else { return nil }
        if let issue = LayoutIssues.check(session.layout).first(where: { $0.severity == .error && $0.key != nil }), let key = issue.key {
            return .issue(text: KeyText.issueText(issue, layout: session.layout), key: key)
        }
        guard isFollowing else { return nil }
        let layer = session.selection.layer
        let name = session.currentLayer?.title ?? ""
        let held = layer == 0 ? nil : KeyText.activator(layout: session.layout, layer: layer)?.text
        return .live(text: [String(localized: "LIVE"), held.map { "\(name) \($0)" } ?? name].joined(separator: " · "))
    }

    /// Kinds on the shown layer, in kind-key order (spec §3.7).
    var kindsOnLayer: [KeyKind] {
        guard let layer = session?.currentLayer else { return [] }
        let present = Set(layer.keys.map(\.kind))
        return KeyKind.allCases.filter(present.contains)
    }

    /// Honest window minimum (spec §3.2): the centre column's 640 plus each visible column's minimum.
    var minimumWidth: CGFloat {
        640 + (columnVisibility == .detailOnly ? 0 : 200) + (showsInspector ? 280 : 0)
    }

    // MARK: Command enablement

    /// Key commands are off on the Firmware Settings page, where the selected key isn't shown (the selection stays).
    var hasSelectedKey: Bool { !showsFirmwareSettings && session?.selection.keyIndex != nil }
    var canShowPreviousLayer: Bool { (session?.selection.layer ?? 0) > 0 }
    var canShowNextLayer: Bool { session.map { $0.selection.layer < $0.layout.layers.count - 1 } ?? false }
    var canDeleteLayer: Bool { (session?.layout.layers.count ?? 0) > 1 }
    var canOverrideKey: Bool {
        guard !showsFirmwareSettings, let session, let index = session.selection.keyIndex else { return false }
        return session.layout.resolvedKey(layer: session.selection.layer, index: index).isInherited
    }
    var canFollow: Bool { session != nil && activity.isKeyboardConnected }
    var canBuild: Bool { onBuild != nil && session != nil && !activity.isBusy }
    /// Stop is for building and waiting only: flashing can't be interrupted once it writes (spec §7.4).
    var canStop: Bool {
        guard onBuild != nil else { return false }
        switch activity.status {
        case .building, .waitingForFlashMode: return true
        default: return false
        }
    }

    // MARK: Actions

    func showAdjacentLayer(_ step: Int) {
        guard let session else { return }
        session.select(layer: session.selection.layer + step)
    }

    func moveLayer(by step: Int) {
        guard let session else { return }
        session.moveLayer(from: session.selection.layer, to: session.selection.layer + step)
    }

    /// Deletes the shown layer, asking first when keys still switch to it (spec §6.1).
    func requestDeleteLayer() {
        guard let session, canDeleteLayer else { return }
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

    func build(_ command: BuildCommand) {
        guard let session else { return }
        onBuild?(command, session)
    }

    func showIssue(_ key: KeyRef) {
        showsFirmwareSettings = false
        session?.select(layer: key.layer)
        session?.select(key: key.index, slot: key.slot)
    }

    /// Opens the layout's package in Finder (File ▸ Show in Finder).
    func showInFinder() async {
        guard let id = session?.id, let url = await library.location(of: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
