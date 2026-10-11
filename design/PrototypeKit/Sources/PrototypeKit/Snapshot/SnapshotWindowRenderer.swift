import AppKit
import SwiftUI

/// Offscreen window that reports itself key/main so controls draw in their active state. Never ordered in.
final class SnapshotWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // AppKit asks these (private) questions when choosing active vs inactive control artwork.
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func hasKeyAppearance() -> Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func hasMainAppearance() -> Bool { true }
    @objc func _hasMainAppearance() -> Bool { true }
}

@MainActor
enum SnapshotWindowRenderer {
    static let offscreenOrigin = NSPoint(x: -30_000, y: -30_000)

    static func backgroundView(_ background: SnapshotScene.Background) -> AnyView {
        switch background {
        case .transparent: AnyView(Color.clear)
        case .windowBackground: AnyView(Color(nsColor: .windowBackgroundColor))
        case let .color(c): AnyView(c.color)
        }
    }

    static func decorate(_ view: AnyView, appearance: SnapshotAppearance) -> AnyView {
        AnyView(view
            .environment(\.isSnapshot, true)
            .environment(\.controlActiveState, .key)
            .transaction { $0.disablesAnimations = true })
    }

    /// Lets SwiftUI and AppKit settle without ever showing the window.
    static func settle(_ window: NSWindow, seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(max(0.05, seconds))
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.02)))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }

    static func makeWindow(size: CGSize, styleMask: NSWindow.StyleMask, appearance: SnapshotAppearance) -> SnapshotWindow {
        let w = SnapshotWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: styleMask, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = appearance.nsAppearance
        w.animationBehavior = .none
        w.setFrameOrigin(offscreenOrigin)
        w.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        w.ignoresMouseEvents = true
        w.alphaValue = 0 // belt and braces: the window is never ordered in anyway
        return w
    }

    static func capture(_ view: NSView, size: CGSize, scale: CGFloat) throws -> CGImage {
        let bounds = CGRect(origin: .zero, size: size)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded()), pixelsHigh: Int((size.height * scale).rounded()),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw SnapshotRunner.Failure.renderFailed("bitmap")
        }
        rep.size = size
        view.cacheDisplay(in: bounds, to: rep)
        guard let image = rep.cgImage else { throw SnapshotRunner.Failure.renderFailed("cgImage") }
        return image
    }

    static func tearDown(_ window: NSWindow) {
        SnapshotApplication.fakeKeyWindow = nil
        window.contentViewController = nil
        window.contentView = nil
        window.close()
    }

    /// Full window with titlebar, toolbar, sidebar and inspector.
    static func renderWindow(scene: SnapshotScene, title: String?, scale: CGFloat) throws -> (image: CGImage, cornerRadius: CGFloat) {
        let window = makeWindow(size: scene.size, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                appearance: scene.appearance)
        if let title { window.title = title }
        SnapshotApplication.fakeKeyWindow = window
        let controller = NSHostingController(rootView: decorate(scene.makeView(), appearance: scene.appearance))
        controller.sceneBridgingOptions = [.toolbars, .title]
        // Keep NSHostingController's default sizing options. With `[]` a NavigationSplitView whose columns
        // need more width than the window has loops on constraint updates and AppKit throws.
        window.contentViewController = controller
        window.setContentSize(scene.size)
        window.setFrameOrigin(offscreenOrigin)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: window)
        settle(window, seconds: scene.settleTime)
        guard let frameView = window.contentView?.superview else { throw SnapshotRunner.Failure.renderFailed(scene.name) }
        if frameView.bounds.size != scene.size {
            // AppKit won't make a window smaller than its content's minimum size (toolbar items, split-view columns).
            print("snapshot: note: \(scene.name) is \(Int(frameView.bounds.width))×\(Int(frameView.bounds.height)) pt, not \(Int(scene.size.width))×\(Int(scene.size.height)), because the content's minimum size is larger")
        }
        LayerFlattener.flatten(window: window)
        let radius: CGFloat = frameView.responds(to: NSSelectorFromString("cornerRadius")) ? (frameView.value(forKey: "cornerRadius") as? CGFloat ?? 16) : 16
        let image = try capture(frameView, size: frameView.bounds.size, scale: scale)
        tearDown(window)
        return (image, radius)
    }

    /// Fills a zero width or height from the view's fitting size, and notes content that won't fit.
    static func resolveSize(_ size: CGSize, view: @MainActor () -> AnyView, appearance: SnapshotAppearance, name: String) -> CGSize {
        let probe = size.width > 0 ? AnyView(view().frame(width: size.width)) : view()
        let host = NSHostingView(rootView: decorate(probe, appearance: appearance))
        host.appearance = appearance.nsAppearance
        let natural = host.fittingSize
        var out = size
        if out.width <= 0 { out.width = ceil(natural.width) }
        if out.height <= 0 { out.height = ceil(natural.height) }
        if natural.height > out.height + 1 || natural.width > out.width + 1 {
            print("snapshot: note: \(name) content wants \(Int(natural.width))×\(Int(natural.height)) pt but has \(Int(out.width))×\(Int(out.height)); it will be clipped (pass 0 for a dimension to fit)")
        }
        return out
    }

    /// The view alone in a borderless window.
    static func renderContent(size: CGSize, appearance: SnapshotAppearance, background: SnapshotScene.Background, settle settleTime: TimeInterval,
                              scale: CGFloat, view: @MainActor () -> AnyView) throws -> CGImage {
        let window = makeWindow(size: size, styleMask: [.borderless], appearance: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        SnapshotApplication.fakeKeyWindow = window
        let root = ZStack {
            backgroundView(background)
            view()
        }
        .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: decorate(AnyView(root), appearance: appearance))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.setContentSize(size)
        window.setFrameOrigin(offscreenOrigin)
        settle(window, seconds: settleTime)
        LayerFlattener.flatten(window: window)
        let image = try capture(hosting, size: size, scale: scale)
        tearDown(window)
        return image
    }
}
