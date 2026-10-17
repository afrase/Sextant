import AppKit
import Foundation
import Observation
import SextantApplication
import SwiftUI

/// App-wide window requests from places with no window of their own: the menu bar extra and Window ▸ Main Window (⌘0).
/// Each opens or brings forward the window of the keyboard's layout, with the Dock icon back first (``AppPresence``), then
/// activates Sextant (spec §13.2: `openWindow`, then `NSApp.activate()`). A Build & Flash asked for here waits for that
/// window, which runs it when it shows the layout (ADR 0049).
@MainActor
@Observable
public final class WindowRouter {
    /// A Build & Flash for a layout's window to run.
    struct BuildRequest: Equatable {
        var layout: UUID
        var date: Date
    }

    /// Opens the layout window for a library id, or an empty one (the Welcome) for nil: `openWindow(id:value:)`.
    public typealias OpenWindow = @MainActor (UUID?) -> Void

    public let presence: AppPresence
    private(set) var pendingBuild: BuildRequest?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let onKeyboard: OnKeyboard?
    @ObservationIgnored private let live: LiveSession?
    @ObservationIgnored private let activate: @MainActor () -> Void
    @ObservationIgnored private let now: @MainActor () -> Date

    /// A request no window took this long after it was made is dropped: its window never showed the layout (it was
    /// trashed, or failed to open), and a build must not start the next time that layout opens.
    static let requestLifetime: TimeInterval = 10

    public init(
        library: Library, onKeyboard: OnKeyboard?, live: LiveSession?, presence: AppPresence,
        activate: @escaping @MainActor () -> Void = { NSApplication.shared.activate() }, now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.library = library
        self.onKeyboard = onKeyboard
        self.live = live
        self.presence = presence
        self.activate = activate
        self.now = now
    }

    /// The layout the menu bar acts on: the one a Build & Flash is flashing, the keyboard's, one open in a window, or the
    /// most recently modified. Nil with an empty library.
    var target: UUID? {
        live?.flashingLayoutID ?? onKeyboard?.running?.entry.id ?? library.entries.first { library.isOpen($0.id) }?.id
            ?? library.entries.first?.id
    }

    /// Open Sextant (⌘0): the target layout's window. With an empty library, the Welcome, unless a window is already open.
    public func showMainWindow(_ openWindow: OpenWindow) {
        presence.prepareToOpen()
        if let target {
            openWindow(target)
        } else if presence.windowCount == 0 {
            openWindow(nil)
        }
        activate()
    }

    /// Build & Flash… from the menu bar: the target layout's window, which then starts it. A flash already under way is
    /// only brought forward.
    public func buildAndFlash(_ openWindow: OpenWindow) {
        if live?.flashingLayoutID == nil, let target { pendingBuild = BuildRequest(layout: target, date: now()) }
        showMainWindow(openWindow)
    }

    /// Settings… from the menu bar.
    public func showSettings(_ openSettings: @MainActor () -> Void) {
        presence.prepareToOpen()
        openSettings()
        activate()
    }

    /// Another window from a place that may have none of its own: the Layout on the Keyboard window, or the layout it
    /// added (ADR 0061). The Dock icon comes back first and Sextant comes forward, so it works from the menu bar alone.
    public func showWindow(_ open: @MainActor () -> Void) {
        presence.prepareToOpen()
        open()
        activate()
    }

    /// The window showing `layout` asks whether to start a Build & Flash; true once, for a request still fresh.
    func takeBuild(for layout: UUID) -> Bool {
        guard let pendingBuild else { return false }
        if now().timeIntervalSince(pendingBuild.date) > Self.requestLifetime {
            self.pendingBuild = nil
            return false
        }
        guard pendingBuild.layout == layout else { return false }
        self.pendingBuild = nil
        return true
    }
}

extension OpenWindowAction {
    /// The layout window for a library id, or an empty one for nil: what ``WindowRouter`` opens.
    @MainActor func layout(_ id: UUID?) {
        if let id { self(id: "layout", value: id) } else { self(id: "layout") }
    }
}
