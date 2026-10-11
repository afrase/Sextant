import SextantApplication
import SwiftUI

/// Sextant's scenes (spec §2.1). The composition root passes in the use cases that outlive windows.
public struct SextantScenes: Scene {
    private let services: SextantServices
    private let onBuild: BuildHandler?

    /// `onBuild` runs the build commands; until Build & Flash is presented it is nil and they stay disabled.
    public init(services: SextantServices, onBuild: BuildHandler? = nil) {
        self.services = services
        self.onBuild = onBuild
    }

    public var body: some Scene {
        WindowGroup(id: "layout", for: UUID.self) { $layoutID in
            LayoutWindow(library: services.library, layoutID: $layoutID, onBuild: onBuild)
        }
        // 1440×900, or 1600×1000 on displays at least 1728 pt wide, clamped to the screen (spec §3.2).
        .defaultWindowPlacement { _, context in
            let screen = context.defaultDisplay.visibleRect.size
            let size = screen.width >= 1728 ? CGSize(width: 1600, height: 1000) : CGSize(width: 1440, height: 900)
            return WindowPlacement(size: CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height)))
        }
        .windowResizability(.contentMinSize)
        .commands { SextantCommands() }
    }
}
