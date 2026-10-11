import AppKit
import SextantDomain
import SextantUI
import SwiftUI

/// Light or dark rendering.
public enum SnapshotAppearance: String, Sendable, CaseIterable, Hashable {
    case light, dark

    public var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    public var nsAppearance: NSAppearance { NSAppearance(named: self == .dark ? .darkAqua : .aqua)! }
}

/// One image to render: a named view at a size and appearance, optionally inside a full window, with
/// optional composited overlays (sheets, popovers, menus).
@MainActor
public struct SnapshotScene {
    /// How the view is hosted.
    public enum Chrome {
        /// A real titled `NSWindow` (full-size content): traffic lights, title, SwiftUI `.toolbar` items,
        /// `NavigationSplitView` sidebars and `.inspector` columns render. `title` sets the window title if the
        /// view doesn't set `.navigationTitle`.
        case window(title: String? = nil)
        /// The view alone in a borderless offscreen window. AppKit-backed controls render correctly.
        case content
        /// SwiftUI `ImageRenderer`. Draws SwiftUI's own Liquid Glass and material approximations, but every
        /// AppKit-backed control (Toggle switch, TextField, Picker, List, Table, Menu…) becomes a yellow
        /// placeholder. Use for pure-SwiftUI drawings such as a board render or a HUD.
        case imageRenderer
    }

    /// Background behind `.content` and `.imageRenderer` scenes.
    public enum Background {
        case transparent
        /// `NSColor.windowBackgroundColor` in the scene's appearance.
        case windowBackground
        case color(HexColor)
    }

    /// Outline of `.window` scenes.
    public enum WindowFrame {
        /// The window rectangle as rendered (square corners).
        case square
        /// Rounded corners (the window's real corner radius) and a hairline edge, transparent outside.
        case rounded
        /// Rounded, plus a soft drop shadow on a transparent canvas with `padding` points on each side.
        case shadowed(padding: CGFloat)
    }

    /// File name without extension.
    public var name: String
    /// Window content size (or view size), in points.
    public var size: CGSize
    public var appearance: SnapshotAppearance
    public var chrome: Chrome
    public var background: Background
    public var windowFrame: WindowFrame
    /// Seconds to let SwiftUI settle (layout, `onAppear`, `task`) before capture.
    public var settleTime: TimeInterval
    public var overlays: [SnapshotOverlay]
    let makeView: @MainActor () -> AnyView

    public init<V: View>(
        _ name: String, size: CGSize, appearance: SnapshotAppearance = .light, chrome: Chrome = .window(),
        background: Background = .windowBackground, windowFrame: WindowFrame = .rounded,
        settleTime: TimeInterval = 0.35, overlays: [SnapshotOverlay] = [],
        @ViewBuilder view: @escaping @MainActor () -> V
    ) {
        self.name = name
        self.size = size
        self.appearance = appearance
        self.chrome = chrome
        self.background = background
        self.windowFrame = windowFrame
        self.settleTime = settleTime
        self.overlays = overlays
        self.makeView = { AnyView(view()) }
    }

    /// The same scene in light and dark, named `<name>-light` and `<name>-dark`.
    public static func pair<V: View>(
        _ name: String, size: CGSize, chrome: Chrome = .window(), background: Background = .windowBackground,
        windowFrame: WindowFrame = .rounded, overlays: [SnapshotOverlay] = [],
        @ViewBuilder view: @escaping @MainActor () -> V
    ) -> [SnapshotScene] {
        SnapshotAppearance.allCases.map { a in
            SnapshotScene(
                "\(name)-\(a.rawValue)", size: size, appearance: a, chrome: chrome, background: background,
                windowFrame: windowFrame, overlays: overlays, view: view)
        }
    }
}

/// Something drawn on top of a rendered window: real sheets, popovers and menus can't be presented
/// offscreen without showing a window, so the runner renders their content separately and composites it.
///
/// Positions are in the window's points with a top-left origin. The content view gets the system
/// background for its kind (window background for sheets and popovers, a menu-like fill for menus);
/// put your own `.background` on it to override.
@MainActor
public struct SnapshotOverlay {
    public enum Placement {
        /// Centred horizontally, `top` points below the window's top edge (default: under a toolbar).
        case sheet(top: CGFloat = 64)
        /// A popover on `edge` of `anchor` (e.g. `.bottom` hangs below it), with an arrow.
        case popover(anchor: CGRect, edge: Edge)
        /// A menu with its top-left corner at `origin`.
        case menu(origin: CGPoint)
        /// Exact frame, no arrow.
        case frame(CGRect)
    }

    public var placement: Placement
    /// Content size in points. A width or height of 0 is filled from the content's fitting size.
    public var size: CGSize
    /// Darken the window underneath (sheets do by default).
    public var dimsBackground: Bool
    public var cornerRadius: CGFloat
    /// Host the content as `.content` (AppKit controls work) or `.imageRenderer`.
    public var usesImageRenderer: Bool
    let makeView: @MainActor () -> AnyView

    public init<V: View>(
        _ placement: Placement, size: CGSize, dimsBackground: Bool? = nil, cornerRadius: CGFloat? = nil,
        usesImageRenderer: Bool = false, @ViewBuilder view: @escaping @MainActor () -> V
    ) {
        self.placement = placement
        self.size = size
        switch placement {
        case .sheet: self.dimsBackground = dimsBackground ?? true; self.cornerRadius = cornerRadius ?? 20
        case .popover: self.dimsBackground = dimsBackground ?? false; self.cornerRadius = cornerRadius ?? 14
        case .menu: self.dimsBackground = dimsBackground ?? false; self.cornerRadius = cornerRadius ?? 10
        case .frame: self.dimsBackground = dimsBackground ?? false; self.cornerRadius = cornerRadius ?? 12
        }
        self.usesImageRenderer = usesImageRenderer
        self.makeView = { AnyView(view()) }
    }

    /// A sheet `width` points wide whose height fits its content, centred under the toolbar.
    public static func sheet<V: View>(width: CGFloat, top: CGFloat = 64, @ViewBuilder view: @escaping @MainActor () -> V) -> SnapshotOverlay
    {
        SnapshotOverlay(.sheet(top: top), size: CGSize(width: width, height: 0), view: view)
    }

    /// A sheet of `size`, centred under the toolbar.
    public static func sheet<V: View>(size: CGSize, top: CGFloat = 64, @ViewBuilder view: @escaping @MainActor () -> V) -> SnapshotOverlay {
        SnapshotOverlay(.sheet(top: top), size: size, view: view)
    }

    /// A popover of `size` attached to `anchor` (window points) on `edge`.
    public static func popover<V: View>(size: CGSize, anchor: CGRect, edge: Edge = .bottom, @ViewBuilder view: @escaping @MainActor () -> V)
        -> SnapshotOverlay
    {
        SnapshotOverlay(.popover(anchor: anchor, edge: edge), size: size, view: view)
    }

    /// A menu of `size` with its top-left at `origin`.
    public static func menu<V: View>(size: CGSize, at origin: CGPoint, @ViewBuilder view: @escaping @MainActor () -> V) -> SnapshotOverlay {
        SnapshotOverlay(.menu(origin: origin), size: size, view: view)
    }
}
