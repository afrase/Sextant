import AppKit
import Observation
import SextantApplication
import SextantDomain
import SwiftUI

/// The overlay HUD (spec §8.4, ADR 0050): app-wide, built and started by the composition root rather than by a window,
/// so it works with no window open. It feeds ``OverlayModel`` from the live session, the keyboard's layout and Settings
/// › Keyboard, and shows the model's presentation in an ``OverlayPanel``. It sends nothing to the keyboard; it reads
/// only what a Live View session already reports, so it never shows while Live View is off.
@MainActor
public final class OverlayHUD {
    /// The model layout windows report their shown layer to.
    let model: OverlayModel
    private let live: LiveSession
    private let onKeyboard: OnKeyboard
    private let defaults: UserDefaults
    private var panel: OverlayPanel?
    private var tasks: [Task<Void, Never>] = []
    private var observers: [any NSObjectProtocol] = []

    public init(live: LiveSession, onKeyboard: OnKeyboard, defaults: UserDefaults = .standard) {
        self.live = live
        self.onKeyboard = onKeyboard
        self.defaults = defaults
        model = OverlayModel()
    }

    /// Follows the keyboard for the app's lifetime.
    public func start() {
        guard tasks.isEmpty else { return }
        let (model, onKeyboard) = (model, onKeyboard)
        model.settings = OverlaySettings(defaults)
        let keyboard: @MainActor @Sendable () -> OverlayLayout? = {
            onKeyboard.running.map { OverlayLayout(id: $0.entry.id, layout: $0.layout) }
        }
        tasks =
            Self.feed(model, from: live, keyboard: keyboard) + [
                Task { [weak self] in
                    for await (presentation, settings) in Observations({ (model.presentation, model.settings) }) {
                        self?.present(presentation, settings: settings)
                    }
                }
            ]
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self.map { $0.model.settings = OverlaySettings($0.defaults) } }
            },
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self.map { $0.present($0.model.presentation, settings: $0.model.settings) } }
            },
        ]
    }

    /// Feeds `model` from the live session and the keyboard's layout until the tasks are cancelled.
    static func feed(
        _ model: OverlayModel, from live: LiveSession, keyboard: @escaping @MainActor @Sendable () -> OverlayLayout?
    ) -> [Task<Void, Never>] {
        let activity = live.activity()
        return [
            Task { for await event in activity { model.handle(event) } },
            Task {
                for await now in Observations({ OverlayInputs(live: live, keyboard: keyboard()) }) {
                    model.keyboard = now.keyboard
                    model.isLive = now.isLive
                    model.secureInput(now.isSecureInputOn, layer: live.activeLayer)
                }
            },
        ]
    }

    /// Shows `presentation` on the screen with the pointer, or hides the panel.
    private func present(_ presentation: OverlayPresentation?, settings: OverlaySettings) {
        guard let presentation, let layout = model.keyboard?.layout, let screen = OverlayPanel.pointerScreen else {
            panel?.hide()
            return
        }
        let panel = panel ?? OverlayPanel()
        self.panel = panel
        // Under Reduce Transparency or Increase Contrast the view draws its own opaque panel (HUDSurface); otherwise
        // AppKit's glass sits behind it.
        let workspace = NSWorkspace.shared
        let opaque = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
        let content = OverlayContent(
            model: model, presentation: presentation, layout: layout,
            width: HUDView.width(size: settings.size, screenWidth: screen.visibleFrame.width), tints: settings.tints)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        if opaque {
            panel.contentView = hosting
        } else {
            let glass = NSGlassEffectView()
            glass.contentView = hosting
            glass.cornerRadius = if case .pill = presentation { HUDPill.height / 2 } else { HUDView.cornerRadius }
            let color = layout.layers[safe: presentation.layer]?.color
            glass.tintColor = settings.tints ? color.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 0.2) } : nil
            panel.contentView = glass
        }
        panel.show(at: OverlayPanel.frame(size: size, position: settings.position, on: screen.visibleFrame))
    }
}

/// What the HUD follows from the live session and ``OnKeyboard``.
private struct OverlayInputs: Sendable {
    var isLive: Bool
    var isSecureInputOn: Bool
    var keyboard: OverlayLayout?

    @MainActor
    init(live: LiveSession, keyboard: OverlayLayout?) {
        if case .connected = live.connection { isLive = true } else { isLive = false }
        isSecureInputOn = live.isSecureInputOn
        self.keyboard = keyboard
    }
}

/// The panel's content: the full overlay or the reminder. The keys held down come from the model as they change; the
/// rest stays as it was shown, so a fading panel keeps its picture.
private struct OverlayContent: View {
    var model: OverlayModel
    var presentation: OverlayPresentation
    var layout: KeyboardLayout
    var width: CGFloat
    var tints: Bool

    var body: some View {
        switch presentation {
        case let .full(layer, holder):
            HUDView(layout: layout, layer: layer, holder: holder, pressed: model.pressedKeys, width: width, tints: tints)
        case let .pill(layer):
            HUDPill(layout: layout, layer: layer, tints: tints)
        }
    }
}

extension View {
    /// Tells the overlay which layer this window's board shows while the window is key, so the HUD doesn't repeat what
    /// the window already shows (spec §8.4).
    func reportsShownLayer(_ model: LayoutWindowModel) -> some View { modifier(ReportsShownLayer(model: model)) }
}

private struct ReportsShownLayer: ViewModifier {
    var model: LayoutWindowModel
    @Environment(OverlayModel.self) private var overlay: OverlayModel?
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        let shown = appearsActive && model.page == nil ? model.session.map { ShownLayer(layoutID: $0.id, layer: $0.selection.layer) } : nil
        content
            .onChange(of: shown, initial: true) { overlay?.window(ObjectIdentifier(model), shows: shown) }
            .onDisappear { overlay?.window(ObjectIdentifier(model), shows: nil) }
    }
}
