import AppKit
import ImageIO
import SextantUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - How snapshots work, and what they can't show
//
// Everything is rendered in-process. No screen capture, no ScreenCaptureKit, no CGWindowList, no
// Accessibility: nothing can trigger a TCC prompt. The app runs with activation policy `.prohibited`
// (no Dock icon, never activates) and snapshot windows are never ordered on screen; they sit at
// (-30000, -30000) and are only drawn into bitmaps.
//
// Paths (pick per scene with `SnapshotScene.Chrome`):
// - `.window`: a real titled NSWindow with full-size content hosting the SwiftUI view through
//   NSHostingController with `sceneBridgingOptions = [.toolbars, .title]`, so `.toolbar`, `.navigationTitle`,
//   NavigationSplitView and `.inspector` populate real AppKit chrome. Captured with
//   `cacheDisplay(in:to:)` on the window's frame view (NSThemeFrame), which includes the titlebar,
//   traffic lights and toolbar. Before capture the layer tree is flattened (LayerFlattener.swift).
// - `.content`: the same pipeline in a borderless window; just the view.
// - `.imageRenderer`: SwiftUI ImageRenderer; no window at all.
//
// Faithful in `.window` / `.content`:
// - Layout, text, SF Symbols, shapes, gradients, images, Canvas, colours and accent colour.
// - AppKit-backed controls (Toggle switches, TextField, Picker, segmented controls, Slider, List/outline
//   rows, Form, Table) drawn in their *active, key-window* state.
// - Titlebar, traffic lights, window title, toolbar items and their glass platters (as flat shapes).
// - Light and dark appearance; 2x (or any) scale.
//
// Approximated in `.window` / `.content` (offscreen there is no window server compositing):
// - Liquid Glass: flat translucent fill in the correct shape and corner radius with a hairline edge.
//   No blur, refraction, specular highlight or shadow. Sidebar and inspector glass panels become flat
//   panels. Prominent glass and any tinted glass use the accent colour (custom tints can't be read back).
// - Materials (`.regularMaterial`, NSVisualEffectView): flat fill of the material's base colour, no blur
//   of content behind.
// - Vibrancy: colours computed from the vibrant colour matrix without the backdrop, close to real.
// - Window shape: corners rounded to the frame view's radius (16 pt here) with a hairline edge; no
//   real window shadow (use `.shadowed(padding:)` for a drawn one).
// - Scroll-edge effects under the toolbar are omitted.
//
// Faithful in `.imageRenderer`:
// - Pure SwiftUI drawing, including SwiftUI's own software rendering of `.glassEffect`, glass buttons and
//   materials (closer to the real look than the flat substitute).
// Not rendered by `.imageRenderer`: every AppKit-backed control (switch-style Toggle, TextField, Picker,
// List, Table, Form rows, Menu, NSViewRepresentable) shows a yellow "unsupported" placeholder.
//
// Not capturable at all (both paths): real sheets, popovers, menus, alerts, tooltips, the menu bar and
// MenuBarExtra menus, drag images, focus rings in motion, animations mid-flight, cursor. Presenting a
// real sheet/popover/menu would put a window on screen, so don't. Instead:
// - Sheets: `SnapshotOverlay.sheet(size:)` renders the sheet content on its own and composites it over
//   the window (centred under the toolbar, parent dimmed, rounded corners, drop shadow).
// - Popovers: `SnapshotOverlay.popover(size:anchor:edge:)` composites content with an arrow at a window-space
//   anchor rect (e.g. a key's frame from BoardLayout plus the canvas origin).
// - Menus: `SnapshotOverlay.menu(size:at:)` composites a menu-coloured panel; build the rows yourself
//   (e.g. a VStack of Labels with keyboard-shortcut text). NSMenu rendering isn't available offscreen.
// - Menu bar extra / HUD: render the panel's SwiftUI content as a `.content` or `.imageRenderer` scene.
//
// Determinism: use fixed sample data and frozen states. Animations
// are disabled for snapshot views (`transaction.disablesAnimations`). `@Environment(\.isSnapshot)` is true.
//
// Setup for an app target:
// ```swift
// @main @MainActor enum Entry {
//     static func main() {
//         SnapshotRunner.handleCommandLine(MyScenes.all)   // exits if --snapshot <dir> was passed
//         MyApp.main()
//     }
// }
// ```
// Then: `swift run MyApp --snapshot ./snapshots` (optional `--only name1,name2`, `--scale 2`).
// Call it before anything touches NSApplication.shared so the snapshot app class can be installed;
// otherwise controls may draw in their inactive state.

/// Renders ``SnapshotScene``s to PNG files.
@MainActor
public enum SnapshotRunner {
    /// Errors from rendering.
    public enum Failure: Error, CustomStringConvertible {
        case renderFailed(String)
        case writeFailed(URL)
        public var description: String {
            switch self {
            case let .renderFailed(n): "Could not render scene \(n)"
            case let .writeFailed(u): "Could not write \(u.path)"
            }
        }
    }

    /// Renders every scene into `outputDirectory` as `<name>.png` at `scale` (default 2x). Returns written files.
    @discardableResult
    public static func run(scenes: [SnapshotScene], outputDirectory: URL, scale: CGFloat = 2, log: Bool = true) throws -> [URL] {
        prepareApplication()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for scene in scenes {
            let image = try render(scene, scale: scale)
            let url = outputDirectory.appendingPathComponent("\(scene.name).png")
            try writePNG(image, to: url, scale: scale)
            urls.append(url)
            if log { print("snapshot: \(url.path) (\(image.width)×\(image.height) px)") }
        }
        return urls
    }

    /// If `arguments` contain `--snapshot <dir>`, renders `scenes` (filtered by `--only a,b`, scale from `--scale n`)
    /// and exits the process. Otherwise returns without doing anything.
    public static func handleCommandLine(_ scenes: @autoclosure () -> [SnapshotScene], arguments: [String] = CommandLine.arguments) {
        guard let i = arguments.firstIndex(of: "--snapshot") else { return }
        let dir = arguments.indices.contains(i + 1) ? arguments[i + 1] : "snapshots"
        var all = scenes()
        if let o = arguments.firstIndex(of: "--only"), arguments.indices.contains(o + 1) {
            let names = Set(arguments[o + 1].split(separator: ",").map(String.init))
            all = all.filter { names.contains($0.name) }
        }
        var scale: CGFloat = 2
        if let s = arguments.firstIndex(of: "--scale"), arguments.indices.contains(s + 1), let v = Double(arguments[s + 1]) { scale = v }
        do {
            try run(scenes: all, outputDirectory: URL(fileURLWithPath: dir, isDirectory: true), scale: scale)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Renders one scene to an image (overlays and window frame included).
    public static func render(_ scene: SnapshotScene, scale: CGFloat = 2) throws -> CGImage {
        prepareApplication()
        var base: CGImage
        var cornerRadius: CGFloat = 0
        switch scene.chrome {
        case let .window(title):
            let r = try SnapshotWindowRenderer.renderWindow(scene: scene, title: title, scale: scale)
            base = r.image
            cornerRadius = r.cornerRadius
        case .content:
            base = try SnapshotWindowRenderer.renderContent(
                size: scene.size, appearance: scene.appearance, background: scene.background,
                settle: scene.settleTime, scale: scale, view: scene.makeView)
        case .imageRenderer:
            base = try renderWithImageRenderer(
                size: scene.size, appearance: scene.appearance, background: scene.background, scale: scale,
                view: scene.makeView)
        }
        for var overlay in scene.overlays {
            overlay.size = SnapshotWindowRenderer.resolveSize(
                overlay.size, view: overlay.makeView, appearance: scene.appearance, name: "\(scene.name) overlay")
            let content: CGImage =
                overlay.usesImageRenderer
                ? try renderWithImageRenderer(
                    size: overlay.size, appearance: scene.appearance, background: SnapshotCompositor.background(for: overlay),
                    scale: scale, view: overlay.makeView)
                : try SnapshotWindowRenderer.renderContent(
                    size: overlay.size, appearance: scene.appearance,
                    background: SnapshotCompositor.background(for: overlay), settle: scene.settleTime,
                    scale: scale, view: overlay.makeView)
            base = SnapshotCompositor.composite(
                overlay, content: content, onto: base, windowSize: scene.size, scale: scale, appearance: scene.appearance)
        }
        if case .window = scene.chrome {
            base = SnapshotCompositor.frame(
                base, style: scene.windowFrame, cornerRadius: cornerRadius, scale: scale, appearance: scene.appearance)
        }
        return base
    }

    /// Renders a SwiftUI view with `ImageRenderer` (see the limitations above).
    public static func renderWithImageRenderer(
        size: CGSize, appearance: SnapshotAppearance, background: SnapshotScene.Background = .transparent,
        scale: CGFloat = 2, view: @MainActor () -> AnyView
    ) throws -> CGImage {
        let content = ZStack {
            SnapshotWindowRenderer.backgroundView(background)
            view()
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, appearance.colorScheme)
        .environment(\.isSnapshot, true)
        .environment(\.controlActiveState, .key)
        .transaction { $0.disablesAnimations = true }
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        var image: CGImage?
        appearance.nsAppearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
        guard let image else { throw Failure.renderFailed("ImageRenderer") }
        return image
    }

    /// Writes a PNG tagged with the right DPI (72 × scale) so viewers show it at point size.
    public static func writePNG(_ image: CGImage, to url: URL, scale: CGFloat = 2) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.writeFailed(url)
        }
        let dpi = 72 * scale
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.writeFailed(url) }
    }

    // MARK: App setup

    private static var prepared = false

    /// Installs ``SnapshotApplication`` (if no NSApplication exists yet), sets the `.prohibited` activation
    /// policy and finishes launching. Safe to call repeatedly.
    public static func prepareApplication() {
        guard !prepared else { return }
        prepared = true
        let app: NSApplication = (NSApp == nil) ? SnapshotApplication.shared : NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
    }
}

/// NSApplication subclass used during snapshots so controls draw as if the app were active and the
/// snapshot window were key (it never is: the app has activation policy `.prohibited`).
final class SnapshotApplication: NSApplication {
    nonisolated(unsafe) static weak var fakeKeyWindow: NSWindow?
    override var isActive: Bool { true }
    override var keyWindow: NSWindow? { Self.fakeKeyWindow ?? super.keyWindow }
    override var mainWindow: NSWindow? { Self.fakeKeyWindow ?? super.mainWindow }
}
