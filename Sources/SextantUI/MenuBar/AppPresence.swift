import AppKit
import Observation

/// Whether Sextant shows in the Dock (spec §2.1, ADR 0049). It is a regular app, and becomes a menu-bar-only one
/// (`.accessory`) only when the last layout window closes while both "Show in menu bar" and "Keep Sextant in the menu bar
/// when its windows are closed" are on. It turns regular again before anything opens a window and whenever either
/// setting is turned off, so it is never left with neither a Dock icon nor a menu bar item.
@MainActor
@Observable
public final class AppPresence {
    /// Layout windows open now.
    public private(set) var windowCount = 0
    public private(set) var policy = NSApplication.ActivationPolicy.regular

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let apply: @MainActor (NSApplication.ActivationPolicy) -> Void
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// - Parameter apply: sets the app's activation policy (`NSApplication.setActivationPolicy`).
    public init(
        defaults: UserDefaults = .standard,
        apply: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApplication.shared.setActivationPolicy($0) }
    ) {
        self.defaults = defaults
        self.apply = apply
        // Removing the extra from the menu bar (⌘-drag) clears "Show in menu bar" through the same default.
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    isolated deinit { observer.map(NotificationCenter.default.removeObserver) }

    var showsInMenuBar: Bool { defaults.object(forKey: SettingsKey.showsInMenuBar) as? Bool ?? true }
    var keepsInMenuBar: Bool { defaults.bool(forKey: SettingsKey.keepsInMenuBar) }

    /// A layout window appeared. One may open without ``prepareToOpen()`` (window restoration, File ▸ New Window).
    public func windowOpened() {
        windowCount += 1
        set(.regular)
    }

    /// A layout window closed: the last one leaves the Dock if both settings are on.
    public func windowClosed() {
        windowCount = max(windowCount - 1, 0)
        if windowCount == 0, showsInMenuBar, keepsInMenuBar { set(.accessory) }
    }

    /// Call before opening a window: the Dock icon and the menu bar come back first, so the window opens in a regular app.
    public func prepareToOpen() { set(.regular) }

    /// Turning either setting off brings the Dock icon back at once; turning them on waits for the last window to close.
    func settingsChanged() {
        if !showsInMenuBar || !keepsInMenuBar { set(.regular) }
    }

    private func set(_ next: NSApplication.ActivationPolicy) {
        guard next != policy else { return }
        policy = next
        apply(next)
    }
}
