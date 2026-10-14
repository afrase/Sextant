import AppKit
import Observation
import SextantApplication
import SextantDomain
import UniformTypeIdentifiers

/// The App Layers page's state for one window (spec §8.6). The rules themselves are the app-wide switcher's, saved beside
/// the layout (ADR 0054); nil where there is none (tests, most snapshots), and the page then shows no rules.
@MainActor
@Observable
public final class AppLayersModel {
    let switcher: AppLayerSwitcher?
    /// The selected rule, by its app's bundle id.
    public var selection: String?
    /// The apps running now, for Add App….
    var runningApps: [MacApp] = []
    /// Add App › Choose… shows its open panel.
    var choosesApp = false
    /// The rule Remove Rule asks about, by its app's bundle id: removing one can't be undone (rule edits aren't on the
    /// window's undo stack, ADR 0054).
    var removing: String?
    /// Each app's icon, looked up once: the lookup asks Launch Services and reads the disk.
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(switcher: AppLayerSwitcher?) {
        self.switcher = switcher
    }

    func rules(_ id: UUID) -> AppLayerRules { switcher?.rules(for: id) ?? AppLayerRules() }

    /// Changes the layout's rules; they save at once. Rule edits aren't document edits, so they're not on the window's undo
    /// stack (ADR 0054).
    func edit(_ id: UUID, _ change: (inout AppLayerRules) -> Void) {
        guard let switcher else { return }
        var rules = switcher.rules(for: id)
        change(&rules)
        switcher.setRules(rules, for: id)
    }

    /// Adds a rule for `app`, on the first layer above the base one, and selects it. An app that has a rule is selected.
    func add(_ app: MacApp, to id: UUID, layout: KeyboardLayout) {
        guard let layer = layout.layers[safe: 1] ?? layout.layers.first else { return }
        edit(id) { $0.add(AppLayerRule(bundleID: app.bundleID, name: app.name, layerID: layer.id)) }
        selection = app.bundleID
    }

    func remove(_ bundleID: String, from id: UUID) {
        edit(id) { $0.remove(bundleID) }
        if selection == bundleID { selection = nil }
    }

    /// The app's icon from where the system finds it; the generic app icon when it isn't installed.
    func icon(for bundleID: String) -> NSImage {
        if let icon = icons[bundleID] { return icon }
        let workspace = NSWorkspace.shared
        let icon =
            workspace.urlForApplication(withBundleIdentifier: bundleID).map { workspace.icon(forFile: $0.path) }
            // `.application` draws a blank document; the bundle type draws the generic app icon.
            ?? workspace.icon(for: .applicationBundle)
        icons[bundleID] = icon
        return icon
    }

    /// Keeps ``runningApps`` current, as apps launch and quit, until the task is cancelled.
    func followRunningApps() async {
        guard let switcher else { return }
        for await apps in switcher.runningApps() { runningApps = apps }
    }

    /// Choose…'s app, added as a rule.
    func addApp(at url: URL, to id: UUID, layout: KeyboardLayout) async {
        guard let app = await switcher?.app(at: url) else { return }
        add(app, to: id, layout: layout)
    }

    /// The window's lens lane (spec §3.7): "Xcode is frontmost → keyboard on Sym+Num", while that holds.
    func laneText(_ id: UUID) -> String? {
        switcher?.applied(for: id).map { AppLayersText.applied($0) }
    }

    /// The lane's capsule in a narrow lane: "Xcode → Sym+Num", as the menu bar says it.
    func shortLaneText(_ id: UUID) -> String? {
        switcher?.applied(for: id).map { "\($0.app) → \($0.layerName)" }
    }
}

/// Words for App Layers (spec §8.6), Sextant's own.
enum AppLayersText {
    /// "Xcode is frontmost → keyboard on Sym+Num".
    static func applied(_ applied: AppLayerSwitcher.Applied) -> String {
        String(localized: "\(applied.app) is frontmost → keyboard on \(applied.layerName)")
    }

    /// "Xcode → Sym+Num", or "Left Xcode → Main" for a Return to Main.
    static func entry(_ entry: AppLayerSwitcher.Switch) -> String {
        if let left = entry.left { return String(localized: "Left \(left) → \(entry.layerName)") }
        return "\(entry.app) → \(entry.layerName)"
    }

    /// The When Leaving choice, naming the base layer: "Return to Main".
    static func leaving(_ leaving: AppLayerRule.Leaving, in layout: KeyboardLayout) -> String {
        switch leaving {
        case .returnToMain: String(localized: "Return to \(layout.layers.first?.title ?? String(localized: "Layer 0"))")
        case .stay: String(localized: "Stay")
        }
    }

    /// The footnote under the rules.
    static let footnote = String(
        localized: """
            Moves the keyboard to the layer, as a Go to (TO) key does: it also turns off layers turned on by a toggle, a \
            one-shot or the Navigator’s mouse layer. Holding a layer key still works on top.
            """)
}
