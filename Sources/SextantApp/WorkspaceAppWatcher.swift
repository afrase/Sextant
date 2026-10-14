// App Layers' frontmost-app adapter (ADR 0054): NSWorkspace's activation notifications, which need no permission (spec
// §13.2). Only an app's bundle id and name leave it. It lives in the composition root beside the hot-key adapter.

import AppKit
import SextantApplication

struct WorkspaceAppWatcher: FrontmostAppWatcher {
    func activations() -> AsyncStream<MacApp> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                if let app = NSWorkspace.shared.frontmostApplication.flatMap(Self.app) { continuation.yield(app) }
                let center = NSWorkspace.shared.notificationCenter
                for await note in center.notifications(named: NSWorkspace.didActivateApplicationNotification) {
                    let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    if let app = running.flatMap(Self.app) { continuation.yield(app) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @MainActor
    func runningApps() -> [MacApp] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(Self.app)
        return Dictionary(apps.map { ($0.bundleID, $0) }) { first, _ in first }.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func app(at url: URL) -> MacApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? FileManager.default.displayName(atPath: url.path)
        return MacApp(bundleID: id, name: name)
    }

    @MainActor
    private static func app(_ running: NSRunningApplication) -> MacApp? {
        guard let id = running.bundleIdentifier else { return nil }
        return MacApp(bundleID: id, name: running.localizedName ?? id)
    }
}
