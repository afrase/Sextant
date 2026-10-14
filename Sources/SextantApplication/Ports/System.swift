import Foundation

/// An app on the Mac, as App Layers names it: its bundle id and its name, nothing else (ADR 0054).
public struct MacApp: Identifiable, Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Which app is frontmost (spec §8.6). The system reports it without asking for any permission (spec §13.2).
public protocol FrontmostAppWatcher: Sendable {
    /// The frontmost app now, then each app that comes forward. Ends when the consuming task is cancelled.
    func activations() -> AsyncStream<MacApp>
    /// The apps running now that have a Dock icon, by name, for Add App…, then again each time one launches or quits.
    /// Ends when the consuming task is cancelled.
    func runningApps() -> AsyncStream<[MacApp]>
    /// The app at `url` (Add App › Choose…); nil when it isn't an app with a bundle id.
    func app(at url: URL) async -> MacApp?
}
