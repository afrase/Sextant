import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

extension SettingsKey {
    /// The menu bar extra is in the menu bar (Settings › General, on by default; ADR 0049).
    static let showsInMenuBar = "showsInMenuBar"
    /// With no layout window open, Sextant leaves the Dock and stays in the menu bar (off by default).
    static let keepsInMenuBar = "keepsInMenuBar"
    /// A dot in the layer's color after the menu bar's layer number (off by default).
    static let showsMenuBarLayerColor = "showsMenuBarLayerColor"
}

/// What the menu bar extra's label shows (spec §8.3): the mark, then the keyboard's layer number. The mark is at half
/// strength with no number when no keyboard is connected, and its arc fills while a flash writes.
public struct MenuBarLabelState: Equatable {
    /// The number after the mark; nil while the keyboard's layer isn't known.
    var layer: Int?
    var isDimmed: Bool
    /// The arc's fill, 0–1 in 5% steps, while a flash writes.
    var progress: Double?
    /// The optional layer-color dot; nil when it is off or the layer has no color.
    var dot: HexColor?
    var accessibilityText: String

    /// - Parameter dot: the color for the dot, already nil when the setting is off.
    public init(connection: LiveSession.Connection, layer: Int?, progress: Double?, dot: HexColor? = nil) {
        isDimmed = false
        self.layer = nil
        self.dot = nil
        if let progress {
            let steps = (min(max(progress, 0), 1) * 20).rounded(.down) / 20
            self.progress = steps
            accessibilityText = String(localized: "Sextant, flashing the keyboard, \(Int((steps * 100).rounded())) percent")
            return
        }
        self.progress = nil
        switch connection {
        case .noKeyboard:
            isDimmed = true
            accessibilityText = String(localized: "Sextant, no keyboard connected")
        case .bootloader: accessibilityText = String(localized: "Sextant, keyboard in flash mode")
        case .heldByAnotherApp: accessibilityText = String(localized: "Sextant, keyboard in use by another app")
        case .liveOff: accessibilityText = String(localized: "Sextant, keyboard connected, Live View off")
        case .connected:
            guard let layer else {
                accessibilityText = String(localized: "Sextant, keyboard connected")
                return
            }
            self.layer = layer
            self.dot = dot
            accessibilityText = String(localized: "Sextant, keyboard on layer \(layer)")
        }
    }

    /// The label as an image: MenuBarExtra labels draw only an Image and a Text, so the number goes into the image. A
    /// template, so the menu bar tints it, unless the color dot is on; then the mark and number are drawn in the menu
    /// bar's label color as the system draws the image.
    public var image: NSImage {
        let glyph: CGFloat = 16
        let text = layer.map { NSAttributedString(string: "\($0)", attributes: [.font: Self.font]) }
        let textSize = text?.size() ?? .zero
        let dotSize: CGFloat = dot == nil ? 0 : 6
        let width = glyph + (text == nil ? 0 : 2 + ceil(textSize.width)) + (dot == nil ? 0 : 3 + dotSize)
        let image = NSImage(size: NSSize(width: width, height: glyph), flipped: true) { [self] _ in
            // The menu bar draws its items opaque, so the label color loses its 85% alpha.
            let ink = (dot == nil ? NSColor.black : NSColor.labelColor).withAlphaComponent(isDimmed ? 0.5 : 1)
            ink.setFill()
            let mark = SextantGlyph(progress: progress).path(in: CGRect(x: 0.5, y: 0.5, width: glyph - 1, height: glyph - 1))
            NSBezierPath(cgPath: mark.cgPath).fill()
            if let text {
                let colored = NSMutableAttributedString(attributedString: text)
                colored.addAttribute(.foregroundColor, value: ink, range: NSRange(location: 0, length: colored.length))
                colored.draw(at: NSPoint(x: glyph + 2, y: (glyph - textSize.height) / 2))
            }
            if let dot {
                NSColor(srgbRed: dot.red, green: dot.green, blue: dot.blue, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: width - dotSize, y: (glyph - dotSize) / 2, width: dotSize, height: dotSize)).fill()
            }
            return true
        }
        image.isTemplate = dot == nil
        image.accessibilityDescription = accessibilityText
        return image
    }

    /// SF Pro Rounded 11 bold (spec §8.3).
    private static var font: NSFont {
        let bold = NSFont.systemFont(ofSize: 11, weight: .bold)
        return bold.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11) } ?? bold
    }
}

/// The menu bar extra's label, over the app-wide live session and the layout on the keyboard.
struct MenuBarLabel: View {
    var live: LiveSession
    var onKeyboard: OnKeyboard
    @AppStorage(SettingsKey.showsMenuBarLayerColor) private var showsColor = false

    var body: some View {
        let state = MenuBarLabelState(live: live, onKeyboard: onKeyboard, showsColor: showsColor)
        Image(nsImage: state.image).accessibilityLabel(state.accessibilityText)
    }
}

extension MenuBarLabelState {
    /// The label for the app's live session. The layer shows only while a session is paired: the last session's stays
    /// in `activeLayer` while the next one pairs.
    @MainActor
    init(live: LiveSession, onKeyboard: OnKeyboard, showsColor: Bool) {
        let layer = live.canSend ? live.activeLayer : nil
        let color = showsColor ? layer.flatMap { onKeyboard.running?.layout.layers[safe: $0]?.color } : nil
        self.init(connection: live.connection, layer: layer, progress: live.flashProgress, dot: color)
    }
}
