import SextantApplication
import SwiftUI

/// Sextant's scenes (spec §2.1). The composition root passes in the use cases that outlive windows.
public struct SextantScenes: Scene {
    private let services: SextantServices
    private let buildToolsStatus: BuildToolsStatus?
    private let firmwareSource: FirmwareSource?
    private let layerShortcutRecorder: LayerShortcutRecorder?

    /// `buildToolsStatus` fills Settings › Build's status line, `firmwareSource` its pinned commits, and
    /// `layerShortcutRecorder` Settings › Keyboard's layer shortcuts.
    public init(
        services: SextantServices, buildToolsStatus: BuildToolsStatus? = nil, firmwareSource: FirmwareSource? = nil,
        layerShortcutRecorder: LayerShortcutRecorder? = nil
    ) {
        self.services = services
        self.buildToolsStatus = buildToolsStatus
        self.firmwareSource = firmwareSource
        self.layerShortcutRecorder = layerShortcutRecorder
    }

    public var body: some Scene {
        WindowGroup(id: "layout", for: UUID.self) { $layoutID in
            // The Device popover shows the raw-HID log.
            LayoutWindow(services: services, layoutID: $layoutID).environment(services.trace)
        }
        // 1440×900, or 1600×1000 on displays at least 1728 pt wide, clamped to the screen (spec §3.2).
        .defaultWindowPlacement { _, context in
            let screen = context.defaultDisplay.visibleRect.size
            let size = screen.width >= 1728 ? CGSize(width: 1600, height: 1000) : CGSize(width: 1440, height: 900)
            return WindowPlacement(size: CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height)))
        }
        .windowResizability(.contentMinSize)
        .commands { SextantCommands(library: services.library, layerShortcuts: services.layerShortcuts) }

        Settings {
            SettingsView(
                buildToolsStatus: buildToolsStatus, firmwareSource: firmwareSource, trace: services.trace,
                layerShortcuts: services.layerShortcuts, layerShortcutRecorder: layerShortcutRecorder)
        }
    }
}
