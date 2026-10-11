import SextantApplication
import SwiftUI

/// Sextant's scenes (spec §2.1). The composition root passes in the use cases that outlive windows.
public struct SextantScenes: Scene {
    private let library: Library

    public init(library: Library) {
        self.library = library
    }

    public var body: some Scene {
        WindowGroup(id: "layout", for: UUID.self) { $layoutID in
            LayoutWindow(library: library, layoutID: $layoutID)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
    }
}
