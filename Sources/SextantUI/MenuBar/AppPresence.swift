import AppKit
import Observation

/// Whether Sextant shows in the Dock (spec §2.1, ADR 0049). It is a regular app, and becomes a menu-bar-only one
/// (`.accessory`) only when its last window closes while both "Show in menu bar" and "Keep Sextant in the menu bar when
/// its windows are closed" are on (both are, by default). Its last window can be a layout window or one a menu bar request
/// opened, such as Settings. It turns regular again before anything opens a window and whenever either setting is turned
/// off, so it is never left with neither a Dock icon nor a menu bar item.
@MainActor
@Observable
public final class AppPresence {
    /// Layout windows open now.
    public private(set) var windowCount = 0
    public private(set) var policy = NSApplication.ActivationPolicy.regular

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let openWindows: @MainActor () -> Int
    @ObservationIgnored private let apply: @MainActor (NSApplication.ActivationPolicy) -> Void
    @ObservationIgnored private let windowNotifications: NotificationCenter
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var windowObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - windowNotifications: where windows say they close (`NSWindow.willCloseNotification`).
    ///   - openWindows: how many of Sextant's windows are open, any kind (``windowsOnScreen()``).
    ///   - apply: sets the app's activation policy (`NSApplication.setActivationPolicy`).
    public init(
        defaults: UserDefaults = .standard,
        windowNotifications: NotificationCenter = .default,
        openWindows: @escaping @MainActor () -> Int = { AppPresence.windowsOnScreen() },
        apply: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApplication.shared.setActivationPolicy($0) }
    ) {
        self.defaults = defaults
        self.windowNotifications = windowNotifications
        self.openWindows = openWindows
        self.apply = apply
        let center = NotificationCenter.default
        observers = [
            // Removing the extra from the menu bar (⌘-drag) clears "Show in menu bar" through the same default.
            center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settingsChanged() }
            }
        ]
        // Settings, or another window a menu bar request brought the Dock icon back for, can be the last one to close. A
        // panel's close is ignored: the menu bar panel closes as Open Sextant or Settings… opens a window, which may not
        // count as open yet.
        windowObserver = windowNotifications.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
            [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if window.map({ Self.counts($0) }) ?? true { self?.leaveDockIfIdle() }
            }
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        windowObserver.map(windowNotifications.removeObserver)
    }

    var showsInMenuBar: Bool { defaults.object(forKey: SettingsKey.showsInMenuBar) as? Bool ?? true }
    var keepsInMenuBar: Bool { defaults.object(forKey: SettingsKey.keepsInMenuBar) as? Bool ?? true }

    /// Sextant's windows on screen or in the Dock: titled windows, so not the overlay, the menu bar extra's panel, popovers
    /// or open and save panels.
    public static func windowsOnScreen() -> Int {
        NSApplication.shared.windows.filter { ($0.isVisible || $0.isMiniaturized) && counts($0) }.count
    }

    /// Whether a window is one of Sextant's windows for the Dock: titled, and not a panel.
    static func counts(_ window: NSWindow) -> Bool { window.styleMask.contains(.titled) && !(window is NSPanel) }

    /// A layout window appeared. One may open without ``prepareToOpen()`` (window restoration, File ▸ New Window).
    public func windowOpened() {
        windowCount += 1
        set(.regular)
    }

    /// A layout window closed: the last of Sextant's windows leaves the Dock if both settings are on.
    public func windowClosed() {
        windowCount = max(windowCount - 1, 0)
        leaveDockIfIdle()
    }

    /// Call before opening a window: the Dock icon and the menu bar come back first, so the window opens in a regular app.
    public func prepareToOpen() { set(.regular) }

    /// Turning either setting off brings the Dock icon back at once; turning them on waits for the last window to close.
    func settingsChanged() {
        if !showsInMenuBar || !keepsInMenuBar { set(.regular) }
    }

    /// Leaves the Dock when no window is left and both settings are on. A closing window can still count as open while it
    /// goes, so with one left this looks once more after it has gone.
    private func leaveDockIfIdle(lookingAgain: Bool = true) {
        guard windowCount == 0, showsInMenuBar, keepsInMenuBar else { return }
        guard openWindows() == 0 else {
            if lookingAgain { Task { [weak self] in self?.leaveDockIfIdle(lookingAgain: false) } }
            return
        }
        set(.accessory)
    }

    private func set(_ next: NSApplication.ActivationPolicy) {
        guard next != policy else { return }
        policy = next
        apply(next)
    }
}
