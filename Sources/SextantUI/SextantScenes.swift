import SextantApplication
import SwiftUI

/// Sextant's scenes (spec §2.1). The composition root passes in the use cases that outlive windows.
public struct SextantScenes: Scene {
    private let services: SextantServices
    private let buildToolsStatus: BuildToolsStatus?
    private let firmwareSource: FirmwareSource?
    private let layerShortcutRecorder: LayerShortcutRecorder?
    private let windows: WindowRouter
    /// Settings › General's "Show in menu bar"; removing the extra from the menu bar turns it off.
    @AppStorage(SettingsKey.showsInMenuBar) private var showsInMenuBar = true

    /// `buildToolsStatus` fills Settings › Build's status line, `firmwareSource` its pinned commits, and
    /// `layerShortcutRecorder` Settings › Keyboard's layer shortcuts. `windows` opens windows for the menu bar extra and
    /// Window ▸ Main Window, and keeps the Dock icon in step with them; build it once, as it outlives every window.
    public init(
        services: SextantServices, windows: WindowRouter, buildToolsStatus: BuildToolsStatus? = nil,
        firmwareSource: FirmwareSource? = nil, layerShortcutRecorder: LayerShortcutRecorder? = nil
    ) {
        self.windows = windows
        self.services = services
        self.buildToolsStatus = buildToolsStatus
        self.firmwareSource = firmwareSource
        self.layerShortcutRecorder = layerShortcutRecorder
    }

    public var body: some Scene {
        WindowGroup(id: "layout", for: UUID.self) { $layoutID in
            // The Device popover shows the raw-HID log; Record Key pauses the layer shortcuts; the overlay HUD stays out
            // of the way of a key window that shows the same layer.
            LayoutWindow(services: services, layoutID: $layoutID).environment(services.trace)
                .environment(services.layerShortcuts).environment(services.overlay.model).environment(windows)
        }
        // 1440×900, or 1600×1000 on displays at least 1728 pt wide, clamped to the screen (spec §3.2).
        .defaultWindowPlacement { _, context in
            let screen = context.defaultDisplay.visibleRect.size
            let size = screen.width >= 1728 ? CGSize(width: 1600, height: 1000) : CGSize(width: 1440, height: 900)
            return WindowPlacement(size: CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height)))
        }
        .windowResizability(.contentMinSize)
        .commands {
            SextantCommands(
                library: services.library, onKeyboard: services.onKeyboard, live: services.live,
                layerShortcuts: services.layerShortcuts, windows: windows)
        }

        Settings {
            SettingsView(
                buildToolsStatus: buildToolsStatus, firmwareSource: firmwareSource, trace: services.trace,
                layerShortcuts: services.layerShortcuts, layerShortcutRecorder: layerShortcutRecorder, heatmap: services.heatmap)
        }

        // The label is an image the panel's state draws, since a menu bar extra's label shows only an Image and a Text
        // (spec §8.3, ADR 0049).
        MenuBarExtra(isInserted: $showsInMenuBar) {
            MenuBarPanel(services: services, windows: windows)
        } label: {
            MenuBarLabel(live: services.live, onKeyboard: services.onKeyboard)
        }
        .menuBarExtraStyle(.window)
    }
}
