import AppKit
import QuartzCore

/// Rewrites a window's layer tree so in-process rendering (`cacheDisplay`) shows what the window server
/// would composite. Only ever applied to throwaway snapshot windows.
///
/// What the window server does that in-process rendering can't, and the substitute used here:
/// - **Liquid Glass** (`CABackdropLayer` with the `glassBackground` filter, inside `NSGlassEffectView` and SwiftUI
///   `.glassEffect` / `.buttonStyle(.glass)`): drawn as a flat translucent fill in the glass's real shape (read from
///   its `CASDFElementLayer`: frame, corner radius) with a hairline edge. Prominent glass (`.glassProminent`) is
///   filled with the accent colour; custom glass tints are not recoverable and also come out as the accent colour.
/// - **Portals** (`CAPortalLayer`; glass shows its content through one, and hides the source): hidden, so the
///   source content renders directly. Without this sidebars, inspectors and glass-hosted toolbar items are blank.
/// - **Mask layers** with `destIn` / `destOut` compositing (scroll-edge effects): hidden; otherwise they erase content.
/// - **Vibrancy** (`vibrantColorMatrix` filter): the filter's colour matrix is applied to the layer's bitmap
///   (text, symbols). A vibrant fill (a bordered button's bezel, a field's background) is different: the window server
///   applies the matrix to what lies *behind* it, not to its own colour, so the window is rendered once without those
///   fills, the colour behind each is sampled, and the fill becomes the matrix applied to it. A bordered button in a
///   dark inspector is two such fills (matrices "+0.08" and "×0.31 +0.94, alpha ×0.03") that lift the grey behind it
///   (0.26 → about 0.36); applying them to their own white made those buttons white. Hairline vibrant separators use
///   `NSColor.separatorColor`.
/// - **Selection material** (`NSVisualEffectView.material == .selection`): filled with the selected-content colour.
@MainActor
enum LayerFlattener {
    static func flatten(window: NSWindow) {
        guard let root = window.contentView?.superview ?? window.contentView else { return }
        let dark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            fixSelectionMaterials(in: root)
            if let layer = root.layer { flatten(root: layer, dark: dark) }
        }
    }

    // MARK: Views

    static func fixSelectionMaterials(in view: NSView) {
        if let e = view as? NSVisualEffectView, e.material == .selection, let layer = e.layer {
            let own = (layer.sublayers ?? []).filter { s in !e.subviews.contains { $0.layer === s } }
            own.forEach { $0.isHidden = true }
            layer.backgroundColor =
                (e.isEmphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).cgColor
            layer.cornerRadius = max(layer.cornerRadius, 8)
            layer.cornerCurve = .continuous
        }
        for s in view.subviews { fixSelectionMaterials(in: s) }
    }

    // MARK: Layers

    static func className(_ l: CALayer) -> String { NSStringFromClass(type(of: l)) }

    static func descendants(_ l: CALayer) -> [CALayer] {
        var out: [CALayer] = []
        for s in l.sublayers ?? [] { out.append(s); out += descendants(s) }
        return out
    }

    static func filterNames(_ l: CALayer) -> [String] {
        (l.filters ?? []).compactMap { f in
            guard let o = f as? NSObject, o.responds(to: NSSelectorFromString("type")) else { return nil }
            return o.value(forKey: "type") as? String
        }
    }

    static func flatten(root: CALayer, dark: Bool) {
        let all = [root] + descendants(root)
        var fills: [(layer: CALayer, matrix: [Float])] = []

        // 1. Liquid Glass → flat shape.
        for backdrop in all where className(backdrop).contains("Backdrop") && filterNames(backdrop).contains("glassBackground") {
            substituteGlass(backdrop, dark: dark)
        }

        // 2. Portals, masks, vibrancy, SDF effect layers.
        for l in all {
            let name = className(l)
            if name.contains("Portal") { l.isHidden = true; continue }
            if let c = l.compositingFilter.map({ String(describing: $0) }), c.contains("destIn") || c.contains("destOut") {
                l.isHidden = true
                continue
            }
            if name.contains("CASDFLayer"), !(l.superlayer.map { className($0).contains("Backdrop") } ?? false) {
                l.isHidden = true
                continue
            }
            if let m = vibrantMatrix(l), (l.sublayers ?? []).isEmpty {
                if l.contents != nil {
                    recolorContents(l, matrix: m)
                } else if l.backgroundColor != nil {
                    if l.bounds.height <= 1.01 || l.bounds.width <= 1.01 {
                        l.backgroundColor = NSColor.separatorColor.cgColor
                    } else {
                        fills.append((l, m))
                    }
                }
                l.filters = nil
            }
        }

        // 3. Vibrant fills, from what lies behind them.
        recolorFills(fills, in: root)
    }

    /// Gives each vibrant fill the colour its matrix makes of what lies behind it: the window is rendered once without
    /// them and sampled under each, back to front, so a fill stacked on another (a bezel's two layers) builds on it.
    static func recolorFills(_ fills: [(layer: CALayer, matrix: [Float])], in root: CALayer) {
        guard !fills.isEmpty else { return }
        fills.forEach { $0.layer.isHidden = true }
        let behind = render(root)
        var made: [CGRect: CGColor] = [:]
        for (layer, matrix) in fills {
            let rect = root.convert(layer.bounds, from: layer).integral
            let own = NSColor(cgColor: layer.backgroundColor ?? .white)?.usingColorSpace(.sRGB)?.alphaComponent ?? 1
            let backdrop = made[rect] ?? behind.flatMap { sample($0, under: rect, in: root) } ?? NSColor.windowBackgroundColor.cgColor
            let color = blend(apply(matrix, to: backdrop), over: backdrop, coverage: own)
            made[rect] = color
            layer.backgroundColor = color
            layer.isHidden = false
        }
    }

    /// The root layer drawn into a bitmap, top row first.
    static func render(_ root: CALayer) -> CGImage? {
        let w = Int(root.bounds.width.rounded(.up)), h = Int(root.bounds.height.rounded(.up))
        guard w > 0, h > 0,
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if root.contentsAreFlipped() || root.isGeometryFlipped { ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1) }
        root.render(in: ctx)
        return ctx.makeImage()
    }

    /// The colour behind `rect` (root coordinates): the median of four points just inside its edges, where a button's
    /// title rarely reaches.
    static func sample(_ image: CGImage, under rect: CGRect, in root: CALayer) -> CGColor? {
        let flipped = root.contentsAreFlipped() || root.isGeometryFlipped
        let inset = min(2, rect.width / 4, rect.height / 4)
        let points = [
            CGPoint(x: rect.minX + inset, y: rect.midY), CGPoint(x: rect.maxX - inset, y: rect.midY),
            CGPoint(x: rect.minX + inset, y: rect.minY + inset), CGPoint(x: rect.maxX - inset, y: rect.maxY - inset),
        ]
        let colors = points.compactMap { p in
            pixel(image, x: Int(p.x), y: flipped ? Int(p.y) : image.height - 1 - Int(p.y))
        }
        guard !colors.isEmpty else { return nil }
        let sorted = colors.sorted { luminance($0) < luminance($1) }
        return sorted[sorted.count / 2]
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> CGColor? {
        guard (0..<image.width).contains(x), (0..<image.height).contains(y),
            let cropped = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard
            let ctx = CGContext(
                data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let a = CGFloat(px[3]) / 255
        guard a > 0 else { return nil }
        return CGColor(srgbRed: CGFloat(px[0]) / 255 / a, green: CGFloat(px[1]) / 255 / a, blue: CGFloat(px[2]) / 255 / a, alpha: 1)
    }

    static func luminance(_ c: CGColor) -> CGFloat {
        let rgb = NSColor(cgColor: c)?.usingColorSpace(.sRGB) ?? .black
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }

    /// `top` (with its own alpha) over an opaque `bottom`, scaled by the fill's `coverage`; opaque.
    static func blend(_ top: CGColor, over bottom: CGColor, coverage: CGFloat) -> CGColor {
        let t = NSColor(cgColor: top)?.usingColorSpace(.sRGB) ?? .white
        let b = NSColor(cgColor: bottom)?.usingColorSpace(.sRGB) ?? .black
        let a = t.alphaComponent * coverage
        return CGColor(
            srgbRed: t.redComponent * a + b.redComponent * (1 - a), green: t.greenComponent * a + b.greenComponent * (1 - a),
            blue: t.blueComponent * a + b.blueComponent * (1 - a), alpha: 1)
    }

    static func substituteGlass(_ backdrop: CALayer, dark: Bool) {
        // Host: the NSGlassEffectView's layer (substitute goes under its content), else the SwiftUI SDF container.
        var ancestors: [CALayer] = []
        var p = backdrop.superlayer
        while let x = p { ancestors.append(x); p = x.superlayer }
        let glassView = ancestors.first { ($0.delegate as? NSView) is NSGlassEffectView }
        let host =
            glassView ?? ancestors.first { className($0).hasSuffix("SDFLayer") && !className($0).hasPrefix("CASDF") } ?? backdrop.superlayer
        guard let host else { return }

        let element = descendants(backdrop).first { className($0).contains("SDFElement") }
        let shape = element ?? backdrop
        var frame = host.convert(shape.bounds, from: shape)
        if frame.isEmpty || !frame.width.isFinite { frame = host.convert(backdrop.bounds, from: backdrop) }

        var tint: NSColor?
        if let parent = backdrop.superlayer {
            for d in descendants(parent) where className(d).contains("CASDFLayer") {
                guard d.responds(to: NSSelectorFromString("effect")), let e = d.value(forKey: "effect") as? NSObject else { continue }
                if NSStringFromClass(type(of: e)).contains("Gradient") { tint = .controlAccentColor }
            }
        }
        if let gv = glassView?.delegate as? NSGlassEffectView, let t = gv.tintColor { tint = t }

        let sub = CALayer()
        sub.name = "snapshot.glass"
        sub.frame = frame
        sub.cornerRadius = shape.cornerRadius
        sub.cornerCurve = .continuous
        if let tint {
            sub.backgroundColor = tint.withAlphaComponent(max(0.85, tint.alphaComponent)).cgColor
        } else {
            sub.backgroundColor = (dark ? NSColor(white: 0.24, alpha: 0.62) : NSColor(white: 1, alpha: 0.62)).cgColor
        }
        sub.borderWidth = 0.5
        sub.borderColor = (dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.10)).cgColor
        host.insertSublayer(sub, at: 0)
        backdrop.isHidden = true
    }

    // MARK: Vibrancy

    /// The 4×5 colour matrix of a `vibrantColorMatrix` filter, row-major.
    static func vibrantMatrix(_ l: CALayer) -> [Float]? {
        for f in l.filters ?? [] {
            guard let o = f as? NSObject, o.responds(to: NSSelectorFromString("type")),
                (o.value(forKey: "type") as? String) == "vibrantColorMatrix",
                o.responds(to: NSSelectorFromString("inputKeys")),
                let keys = o.value(forKey: "inputKeys") as? [String], keys.contains("inputColorMatrix"),
                let nv = o.value(forKey: "inputColorMatrix") as? NSValue
            else { continue }
            var size = 0, align = 0
            NSGetSizeAndAlignment(nv.objCType, &size, &align)
            guard size == 80 else { return nil }
            var m = [Float](repeating: 0, count: 20)
            m.withUnsafeMutableBytes { buffer in if let base = buffer.baseAddress { nv.getValue(base, size: 80) } }
            return m
        }
        return nil
    }

    static func apply(_ m: [Float], to c: CGColor) -> CGColor {
        let rgb = NSColor(cgColor: c)?.usingColorSpace(.sRGB) ?? .white
        let i = [Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), Float(rgb.alphaComponent)]
        var o = [Float](repeating: 0, count: 4)
        for r in 0..<4 {
            o[r] = min(1, max(0, m[r * 5] * i[0] + m[r * 5 + 1] * i[1] + m[r * 5 + 2] * i[2] + m[r * 5 + 3] * i[3] + m[r * 5 + 4]))
        }
        return CGColor(srgbRed: CGFloat(o[0]), green: CGFloat(o[1]), blue: CGFloat(o[2]), alpha: CGFloat(o[3]))
    }

    static func recolorContents(_ l: CALayer, matrix m: [Float]) {
        let scale = max(l.contentsScale, 1)
        let w = Int((l.bounds.width * scale).rounded(.up)), h = Int((l.bounds.height * scale).rounded(.up))
        guard w > 0, h > 0, w * h < 16_000_000,
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        if l.contentsAreFlipped() { ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1) }
        ctx.scaleBy(x: scale, y: scale)
        let opacity = l.opacity, filters = l.filters
        l.opacity = 1
        l.filters = nil
        l.render(in: ctx)
        l.opacity = opacity
        guard let data = ctx.data else { l.filters = filters; return }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let a = Float(px[i + 3]) / 255
            if a == 0 { continue }
            let r = Float(px[i]) / 255 / a, g = Float(px[i + 1]) / 255 / a, b = Float(px[i + 2]) / 255 / a
            var o: (Float, Float, Float, Float) = (0, 0, 0, 0)
            func row(_ k: Int) -> Float {
                min(1, max(0, m[k * 5] * r + m[k * 5 + 1] * g + m[k * 5 + 2] * b + m[k * 5 + 3] * a + m[k * 5 + 4]))
            }
            o = (row(0), row(1), row(2), row(3))
            px[i] = UInt8(o.0 * o.3 * 255)
            px[i + 1] = UInt8(o.1 * o.3 * 255)
            px[i + 2] = UInt8(o.2 * o.3 * 255)
            px[i + 3] = UInt8(o.3 * 255)
        }
        guard let img = ctx.makeImage(), let superlayer = l.superlayer else { l.filters = filters; return }
        // Draw the recoloured bitmap on a plain sibling layer: SwiftUI's own layers (e.g. ImageLayer)
        // restore their contents on the next display pass, a plain CALayer doesn't.
        let copy = CALayer()
        copy.name = "snapshot.vibrant"
        copy.bounds = l.bounds
        copy.position = l.position
        copy.anchorPoint = l.anchorPoint
        copy.transform = l.transform
        copy.zPosition = l.zPosition
        copy.opacity = opacity
        copy.contents = img
        copy.contentsScale = scale
        copy.contentsGravity = .resize
        copy.isGeometryFlipped = l.isGeometryFlipped
        superlayer.insertSublayer(copy, above: l)
        l.isHidden = true
    }
}
