import AppKit
import SwiftUI

/// The overlay HUD's window (spec §8.4, §13.3 rule 8): a borderless, nonactivating panel above other apps' windows, on
/// every Space and beside full-screen apps. It never becomes key or main and lets every click through, so it can't
/// take focus from the app the user is typing in.
final class OverlayPanel: NSPanel {
    /// Counts the times the panel was shown, so a fade-out that a show interrupted doesn't order it out when it ends.
    private var shows = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .statusBar
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Drops the content too: a hidden SwiftUI view would still redraw at every change it reads, the held keys at every
    /// key event. Each ``OverlayHUD`` presentation installs its own.
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        contentView = nil
    }

    /// Where the HUD goes on `visible`, a screen's visible frame (clear of the Dock, the menu bar and the notch): at
    /// `position`, `margin` points from the edges it is anchored to (a corner from both, the centre from neither), kept
    /// inside the visible frame on whole points. One too big for it keeps its left edge and its top, the header, on it.
    static func frame(size: CGSize, position: OverlayPosition, margin: CGFloat, on visible: CGRect) -> CGRect {
        let anchoredX: CGFloat =
            switch position.column {
            case 0: visible.minX + margin
            case 2: visible.maxX - margin - size.width
            default: visible.midX - size.width / 2
            }
        let anchoredY: CGFloat =
            switch position.row {
            case 0: visible.maxY - margin - size.height
            case 2: visible.minY + margin
            default: visible.midY - size.height / 2
            }
        let x = max(min(anchoredX.rounded(), (visible.maxX - size.width).rounded(.down)), visible.minX.rounded(.up))
        let y = min(max(anchoredY.rounded(), visible.minY.rounded(.up)), (visible.maxY - size.height).rounded(.down))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// How far from its place the panel starts as it fades in: 8 pt below, so it rises into place, or for the top row 8 pt
    /// above, so it drops into place.
    static func entranceOffset(for position: OverlayPosition) -> CGFloat {
        position.row == 0 ? 8 : -8
    }

    /// The screen that holds the pointer, else the main one.
    static var pointerScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    }

    /// The screen Settings chose: the one with the pointer, or the one with the menu bar.
    static func screen(for display: OverlayDisplay) -> NSScreen? {
        switch display {
        case .pointer: pointerScreen
        case .main: NSScreen.screens.first ?? NSScreen.main
        }
    }

    /// Fades the panel in to `opacity` at `frame` over 0.12 s, moving 8 pt into place from ``entranceOffset(for:)``
    /// unless Reduce Motion is on. Already showing (or fading out), it moves and fades to them from where it is.
    /// Ordering it in doesn't activate Sextant.
    func show(at frame: CGRect, position: OverlayPosition, opacity: CGFloat) {
        shows += 1
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasVisible = isVisible && alphaValue > 0
        if !wasVisible {
            alphaValue = 0
            setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: Self.entranceOffset(for: position)), display: false)
        }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = opacity
            animator().setFrame(frame, display: true)
        }
    }

    /// Fades the panel out over 0.18 s, then orders it out unless it was shown again meanwhile: it must still be at
    /// alpha 0, with no show since. Every opacity Settings offers is above 0, so a show always lifts it.
    func hide() {
        guard isVisible else { return }
        let shown = shows
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.shows == shown, self.alphaValue == 0 { self.orderOut(nil) }
            }
        }
    }
}
