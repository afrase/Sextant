import AppKit
import SwiftUI

/// Widens the inspector by a point and back once it is on screen, as a drag of its divider does. macOS 26 first lays
/// out an inspector inside the detail column as a full-height panel running up behind the toolbar, and only a divider
/// move gives it its titlebar band under the toolbar. shortcut: a workaround for that AppKit layout, remove it once a
/// fresh window opens with the band.
struct InspectorLayoutNudge: NSViewRepresentable {
    /// Changes when the inspector is shown again, so it is nudged each time it appears.
    var isShown: Bool

    func makeNSView(context: Context) -> NSView { NudgeView() }

    func updateNSView(_ view: NSView, context: Context) {
        // Only when the inspector comes back: SwiftUI calls this on unrelated updates too.
        defer { context.coordinator.wasShown = isShown }
        guard isShown, !context.coordinator.wasShown else { return }
        Self.nudgeSoon(in: view.window)
    }

    func makeCoordinator() -> Coordinator { Coordinator(wasShown: isShown) }

    final class Coordinator {
        var wasShown: Bool
        init(wasShown: Bool) { self.wasShown = wasShown }
    }

    /// Nudges once it joins a window: the window's split views exist by then.
    private final class NudgeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            InspectorLayoutNudge.nudgeSoon(in: window)
        }
    }

    /// After the window's first layout pass, which is what lays the inspector out wrong.
    @MainActor static func nudgeSoon(in window: NSWindow?) {
        guard let window else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in nudge(in: window) }
    }

    @MainActor static func nudge(in window: NSWindow?) {
        guard let root = window?.contentView, let split = inspectorSplitView(in: root), split.subviews.count > 1 else { return }
        let position = split.subviews[0].frame.width
        split.setPosition(position - 1, ofDividerAt: 0)
        split.setPosition(position, ofDividerAt: 0)
    }

    /// The split view whose controller holds the inspector item.
    @MainActor private static func inspectorSplitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, let controller = split.delegate as? NSSplitViewController,
            controller.splitViewItems.contains(where: { $0.behavior == .inspector })
        {
            return split
        }
        return view.subviews.lazy.compactMap { inspectorSplitView(in: $0) }.first
    }
}
