import AppKit
import SextantUI
import SwiftUI

/// Image-level compositing: window outline/shadow, and overlays (sheets, popovers, menus).
/// All maths is in points (top-left origin) converted to pixels with `scale`.
@MainActor
enum SnapshotCompositor {
    static func background(for overlay: SnapshotOverlay) -> SnapshotScene.Background {
        switch overlay.placement {
        case .menu: .transparent  // menu fill is drawn by the compositor
        default: .windowBackground
        }
    }

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Converts a top-left-origin rect in points to a bottom-left-origin rect in pixels.
    static func pixelRect(_ r: CGRect, canvasHeight: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(x: r.minX * scale, y: canvasHeight - r.maxY * scale, width: r.width * scale, height: r.height * scale)
    }

    // MARK: Window frame

    static func frame(
        _ image: CGImage, style: SnapshotScene.WindowFrame, cornerRadius: CGFloat, scale: CGFloat, appearance: SnapshotAppearance
    ) -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let radius = max(cornerRadius, 0) * scale
        switch style {
        case .square:
            return image
        case .rounded:
            guard let ctx = context(width: image.width, height: image.height) else { return image }
            drawRoundedWindow(
                image, in: ctx, rect: CGRect(x: 0, y: 0, width: w, height: h), radius: radius, scale: scale, appearance: appearance)
            return ctx.makeImage() ?? image
        case let .shadowed(padding):
            let p = padding * scale
            guard let ctx = context(width: Int(w + p * 2), height: Int(h + p * 2)) else { return image }
            let rect = CGRect(x: p, y: p, width: w, height: h)
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale,
                color: NSColor.black.withAlphaComponent(appearance == .dark ? 0.55 : 0.28).cgColor)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            drawRoundedWindow(image, in: ctx, rect: rect, radius: radius, scale: scale, appearance: appearance)
            return ctx.makeImage() ?? image
        }
    }

    static func drawRoundedWindow(
        _ image: CGImage, in ctx: CGContext, rect: CGRect, radius: CGFloat, scale: CGFloat, appearance: SnapshotAppearance
    ) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(image, in: rect)
        ctx.restoreGState()
        // Hairline edge like a real window.
        let inset = rect.insetBy(dx: scale * 0.25, dy: scale * 0.25)
        ctx.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setLineWidth(scale * 0.5)
        ctx.setStrokeColor((appearance == .dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.16)).cgColor)
        ctx.strokePath()
    }

    // MARK: Overlays

    static func composite(
        _ overlay: SnapshotOverlay, content: CGImage, onto base: CGImage, windowSize: CGSize, scale: CGFloat,
        appearance: SnapshotAppearance
    ) -> CGImage {
        guard let ctx = context(width: base.width, height: base.height) else { return base }
        let baseHeight = CGFloat(base.height)
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        if overlay.dimsBackground {
            ctx.setFillColor(NSColor.black.withAlphaComponent(appearance == .dark ? 0.32 : 0.16).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        }
        let size = overlay.size
        var frame: CGRect
        var arrow: (tip: CGPoint, edge: Edge)?
        switch overlay.placement {
        case let .sheet(top):
            frame = CGRect(x: (windowSize.width - size.width) / 2, y: top, width: size.width, height: size.height)
        case let .menu(origin):
            frame = CGRect(origin: origin, size: size)
        case let .frame(r):
            frame = r
        case let .popover(anchor, edge):
            let gap: CGFloat = 10
            switch edge {
            case .bottom:
                frame = CGRect(x: anchor.midX - size.width / 2, y: anchor.maxY + gap, width: size.width, height: size.height)
                arrow = (CGPoint(x: anchor.midX, y: anchor.maxY + 1), .bottom)
            case .top:
                frame = CGRect(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height, width: size.width, height: size.height)
                arrow = (CGPoint(x: anchor.midX, y: anchor.minY - 1), .top)
            case .leading:
                frame = CGRect(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2, width: size.width, height: size.height)
                arrow = (CGPoint(x: anchor.minX - 1, y: anchor.midY), .leading)
            case .trailing:
                frame = CGRect(x: anchor.maxX + gap, y: anchor.midY - size.height / 2, width: size.width, height: size.height)
                arrow = (CGPoint(x: anchor.maxX + 1, y: anchor.midY), .trailing)
            }
            // Keep the bubble inside the window.
            frame.origin.x = min(max(8, frame.origin.x), windowSize.width - size.width - 8)
            frame.origin.y = min(max(8, frame.origin.y), windowSize.height - size.height - 8)
        }

        let px = pixelRect(frame, canvasHeight: baseHeight, scale: scale)
        let radius = overlay.cornerRadius * scale
        let body = CGMutablePath()
        body.addRoundedRect(in: px, cornerWidth: radius, cornerHeight: radius)
        if let arrow {
            let tip = CGPoint(x: arrow.tip.x * scale, y: baseHeight - arrow.tip.y * scale)
            let half: CGFloat = 11 * scale
            switch arrow.edge {
            case .bottom: body.addLines(between: [CGPoint(x: tip.x - half, y: px.maxY - 1), tip, CGPoint(x: tip.x + half, y: px.maxY - 1)])
            case .top: body.addLines(between: [CGPoint(x: tip.x - half, y: px.minY + 1), tip, CGPoint(x: tip.x + half, y: px.minY + 1)])
            case .leading:
                body.addLines(between: [CGPoint(x: px.maxX - 1, y: tip.y - half), tip, CGPoint(x: px.maxX - 1, y: tip.y + half)])
            case .trailing:
                body.addLines(between: [CGPoint(x: px.minX + 1, y: tip.y - half), tip, CGPoint(x: px.minX + 1, y: tip.y + half)])
            }
            body.closeSubpath()
        }

        let fill: NSColor = {
            var c: NSColor = .windowBackgroundColor
            if case .menu = overlay.placement {
                c = appearance == .dark ? NSColor(white: 0.17, alpha: 0.97) : NSColor(white: 0.985, alpha: 0.97)
            }
            var cg = c.cgColor
            appearance.nsAppearance.performAsCurrentDrawingAppearance { cg = c.cgColor }
            return NSColor(cgColor: cg) ?? c
        }()

        // Shadow + fill (including the arrow), then the content clipped to the bubble.
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -8 * scale), blur: 24 * scale,
            color: NSColor.black.withAlphaComponent(appearance == .dark ? 0.5 : 0.22).cgColor)
        ctx.addPath(body)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: px, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(content, in: px)
        ctx.restoreGState()

        ctx.addPath(body)
        ctx.setLineWidth(scale * 0.5)
        ctx.setStrokeColor((appearance == .dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.12)).cgColor)
        ctx.strokePath()
        return ctx.makeImage() ?? base
    }
}
