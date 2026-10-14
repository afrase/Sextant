import AppKit
import SwiftUI

/// The overlay HUD's window (spec §8.4, §13.3 rule 8): a borderless, nonactivating panel above other apps' windows, on
/// every Space and beside full-screen apps. It never becomes key or main and lets every click through, so it can't
/// take focus from the app the user is typing in.
final class OverlayPanel: NSPanel {
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

    /// Where the HUD goes: centered on the visible frame of the screen with the pointer, 72 pt above its bottom or below
    /// its top, which keeps it clear of the Dock, the menu bar and the notch.
    static func frame(size: CGSize, position: OverlayPosition, on visible: CGRect) -> CGRect {
        let y = position == .bottom ? visible.minY + 72 : visible.maxY - 72 - size.height
        return CGRect(x: (visible.midX - size.width / 2).rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// The screen that holds the pointer, else the main one.
    static var pointerScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    }

    /// Fades the panel in at `frame` over 0.12 s, rising 8 pt into place unless Reduce Motion is on. Ordering it in
    /// doesn't activate Sextant.
    func show(at frame: CGRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasVisible = isVisible && alphaValue > 0
        if !wasVisible {
            alphaValue = 0
            setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -8), display: false)
        }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(frame, display: true)
        }
    }

    /// Fades the panel out over 0.18 s, then orders it out unless it was shown again meanwhile.
    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if let self, self.alphaValue == 0 { self.orderOut(nil) }
            }
        }
    }
}
