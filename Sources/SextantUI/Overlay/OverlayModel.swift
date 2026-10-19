import Foundation
import Observation
import SextantApplication
import SextantDomain

/// What the overlay HUD shows (spec §8.4).
enum OverlayPresentation: Equatable {
    /// The layer's map, held on by a key (on the layer it went down on), or locked with Settings' "Full overlay" (nil).
    case full(layer: Int, heldBy: KeyRef?)
    /// The small "Sym+Num locked" reminder.
    case pill(layer: Int)

    var layer: Int {
        switch self {
        case let .full(layer, _), let .pill(layer): layer
        }
    }
}

/// Settings › Keyboard's overlay options, with the defaults the pane declares (ADRs 0045, 0062). Any change re-places
/// the HUD, and the preview, at once.
struct OverlaySettings: Equatable {
    var showsOverlay = true
    var delay = Duration.milliseconds(150)
    var position = OverlayPosition.bottom
    /// Points from the edges of the visible frame the HUD is anchored to.
    var margin: Double = 72
    var display = OverlayDisplay.pointer
    var size = OverlaySize.medium
    /// The whole panel's opacity, 0.3 to 1.
    var opacity: Double = 1
    var tints = false
    var locked = LockedLayerOverlay.reminder
    /// Whether keys pressed over the full overlay hide it, and until when (ADRs 0064, 0065).
    var typing = OverlayTyping.keepShowing

    /// The delays the pane offers, in milliseconds.
    static let delays = 0...1000
    /// The distances from the screen's edges the pane offers, in points.
    static let margins = 0...200
    /// The opacities the pane offers, in percent.
    static let opacities = 30...100

    init() {}

    init(_ defaults: UserDefaults) {
        showsOverlay = defaults.object(forKey: SettingsKey.showsOverlay) as? Bool ?? true
        delay = .milliseconds(Self.clamp(defaults.object(forKey: SettingsKey.overlayDelay) as? Int ?? 150, to: Self.delays))
        position = defaults.string(forKey: SettingsKey.overlayPosition).flatMap(OverlayPosition.init) ?? .bottom
        margin = Double(Self.clamp(defaults.object(forKey: SettingsKey.overlayMargin) as? Int ?? 72, to: Self.margins))
        display = defaults.string(forKey: SettingsKey.overlayDisplay).flatMap(OverlayDisplay.init) ?? .pointer
        size = defaults.string(forKey: SettingsKey.overlaySize).flatMap(OverlaySize.init) ?? .medium
        opacity = Double(Self.clamp(defaults.object(forKey: SettingsKey.overlayOpacity) as? Int ?? 100, to: Self.opacities)) / 100
        tints = defaults.bool(forKey: SettingsKey.tintsOverlay)
        locked = defaults.string(forKey: SettingsKey.lockedLayerOverlay).flatMap(LockedLayerOverlay.init) ?? .reminder
        typing = defaults.string(forKey: SettingsKey.overlayTyping).flatMap(OverlayTyping.init) ?? .keepShowing
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The layout the keyboard runs (``OnKeyboard``), by library id.
struct OverlayLayout: Equatable {
    var id: UUID
    var layout: KeyboardLayout
}

/// What the HUD's panel shows: a presentation over the layout it draws, either the model's own or Settings › Keyboard's
/// preview (ADR 0062).
struct ShownOverlay: Equatable {
    var presentation: OverlayPresentation
    var layout: KeyboardLayout
    /// The preview, whose header says so in place of held or locked.
    var isPreview: Bool
}

/// When the overlay HUD shows, and what (spec §8.4, ADR 0050). It follows the keyboard's live activity: a layer a key
/// holds on shows the full overlay once the hold lasts the delay, and hides the moment that key is let go; a locked
/// layer shows a reminder (or the full overlay, or nothing, per Settings). Keys pressed over the full overlay can hide it
/// until typing pauses for the delay or until the layer is held again, per Settings (ADRs 0064, 0065). It shows nothing while
/// Live View is off, during secure input, without the keyboard's layout, or while a Sextant window that is key shows the
/// same layer. Settings › Keyboard's preview shows apart from all that, whenever nothing else does (ADR 0062).
@MainActor
@Observable
final class OverlayModel {
    /// What shows now for the keyboard; nil while it shows nothing. The preview is never a presentation.
    private(set) var presentation: OverlayPresentation?
    var settings = OverlaySettings() {
        didSet {
            guard settings != oldValue else { return }
            // The preview shows each change at once and lasts its full time from it; turning the overlay off ends it.
            if !settings.showsOverlay { isPreviewing = false } else if isPreviewing { endPreviewLater() }
            update()
        }
    }
    /// Settings › Keyboard's Preview (ADR 0062): the full overlay with the current settings, even with Live View off,
    /// while ``presentation`` is nil. It ends ``previewTime`` after it starts or after the last settings change, and
    /// can't start while the overlay is off.
    var isPreviewing: Bool {
        get { previewing }
        set {
            let on = newValue && settings.showsOverlay
            guard on != previewing else { return }
            previewing = on
            endPreviewLater()
        }
    }
    private var previewing = false
    /// The keyboard's layout; nil when Sextant doesn't hold it, and then the HUD can't draw the layer.
    var keyboard: OverlayLayout? {
        didSet { if keyboard != oldValue { update() } }
    }
    /// A paired Live View session is open; turning it off forgets the keys and the layer.
    var isLive = false {
        didSet {
            guard isLive != oldValue else { return }
            if !isLive { (held, layer, released) = ([:], nil, nil) }
            update()
        }
    }
    /// Secure input is on: nothing shows. The keys held stay as they are: the activity releases them itself once it
    /// hides an event (``LiveSession/activity()``).
    private(set) var isSecureInputOn = false
    /// Keys held down, for the map: none while secure input is on.
    var pressedKeys: Set<Int> { isSecureInputOn ? [] : Set(held.keys) }

    /// The keyboard's highest layer, as last reported.
    private(set) var layer: Int?
    /// Each key held down, with the layer it went down on.
    private var held: [Int: Int] = [:]
    /// A layer whose holding key was let go with no layer change reported yet. The key-up comes first (the firmware
    /// reports it before acting on it), and the change can also go missing (research 03 O2), so until the next layer
    /// report the layer counts as gone, not as locked.
    private var released: Int?
    /// When typing hides the overlay (ADRs 0064, 0065): the full overlay keys were pressed over, and those of them still
    /// held. Until the next hold it doesn't show at all; until a pause, it doesn't while any is held, and once none is it
    /// shows after the delay (at least ``typingSettle``) unless another goes down. A change to what should show forgets
    /// it, so the next hold, or another layer, shows as usual.
    private var typed: (over: OverlayPresentation, keys: Set<Int>)?
    /// Each layout window that is key, with the layer its board shows.
    private var keyWindows: [ObjectIdentifier: ShownLayer] = [:]
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var pending: (target: OverlayPresentation, task: Task<Void, Never>)?
    @ObservationIgnored private var previewEnd: Task<Void, Never>?

    /// A lock shows only once it has lasted this long, even with no delay: a held TT's key-up comes just before its
    /// layer ends.
    static let lockSettle = Duration.milliseconds(50)
    /// Typing hides the full overlay for at least this long after the last key is let go, even with no delay, so it
    /// doesn't flash back between keystrokes.
    static let typingSettle = Duration.milliseconds(100)
    /// How long the preview lasts after it starts or after the last settings change.
    static let previewTime = Duration.seconds(8)
    /// What the preview draws without the keyboard's layout.
    static let previewSample = KeyboardLayout.blankQWERTY(title: String(localized: "Sample"))

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    /// What the panel shows: the presentation over the keyboard's layout, else the preview while it is on. The preview
    /// draws the keyboard's layout on its layer 1 if it has one (else 0), or a sample without it.
    var shown: ShownOverlay? {
        if let presentation, let keyboard {
            return ShownOverlay(presentation: presentation, layout: keyboard.layout, isPreview: false)
        }
        guard isPreviewing, settings.showsOverlay else { return nil }
        let layout = keyboard?.layout ?? Self.previewSample
        let layer = layout.layers.indices.contains(1) ? 1 : 0
        return ShownOverlay(presentation: .full(layer: layer, heldBy: nil), layout: layout, isPreview: true)
    }

    /// Folds in one thing the keyboard did (``LiveSession/activity()``). A key-up without its key-down is ignored.
    func handle(_ activity: LiveActivity) {
        switch activity {
        case let .keyDown(index, layer):
            typing(index, on: layer)
            held[index] = layer
        case let .keyUp(index):
            typed?.keys.remove(index)
            keyUp(index)
        case let .layer(layer): (self.layer, released) = (layer, nil)
        case .lighting, .refused: return
        }
        update()
    }

    /// Secure input turned on or off, with the keyboard's layer as the session last saw it. Layer changes don't arrive
    /// during secure input, so when it ends the model takes the session's layer; a layer reached meanwhile is
    /// unexplained (the keys pressed then were hidden), so it counts as gone, not as locked, until the next report.
    func secureInput(_ on: Bool, layer keyboardLayer: Int?) {
        guard on != isSecureInputOn else { return }
        isSecureInputOn = on
        if !on, let keyboardLayer, keyboardLayer != layer { (layer, released) = (keyboardLayer, keyboardLayer) }
        update()
    }

    /// A layout window reports the layer its board shows while it is key; nil when it isn't key or shows a page.
    func window(_ window: ObjectIdentifier, shows shown: ShownLayer?) {
        guard keyWindows[window] != shown else { return }
        keyWindows[window] = shown
        update()
    }

    /// When typing hides the overlay, a key that goes down over the full overlay hides it, or holds back one still
    /// waiting for the delay. The key holding its layer doesn't, nor does a layer key: the layer it moves to shows as usual.
    private func typing(_ index: Int, on pressedOn: Int) {
        guard settings.typing != .keepShowing, let keyboard, let over = wanted, case let .full(_, holder) = over, holder?.index != index
        else { return }
        let key = keyboard.layout.resolvedKey(layer: pressedOn, index: index).effective
        guard !key.actions.contains(where: { $0.action.layer != nil }) else { return }
        typed = (over, (typed?.keys ?? []).union([index]))  // update() forgets any it held over something else
    }

    private func keyUp(_ index: Int) {
        guard let pressedOn = held[index] else { return }
        let before = hold
        held[index] = nil
        guard case .momentary(heldBy: index) = before, let layer, let keyboard else { return }
        if case .momentary = hold { return }  // another key still holds it
        // The holder let go: the layer ends now, whether or not its change arrives. Only a tapped TT leaves it on.
        let action = LayerHold.holdingAction(layout: keyboard.layout, layer: layer, index: index, pressedOn: pressedOn)
        if action?.canonicalCode != "TT" { released = layer }
    }

    private var hold: LayerHold? {
        guard let keyboard, let layer else { return nil }
        return LayerHold.classify(layout: keyboard.layout, layer: layer, pressed: held)
    }

    /// What should show now, before the delay.
    private var wanted: OverlayPresentation? {
        guard isLive, !isSecureInputOn, settings.showsOverlay, let keyboard, let layer, let hold,
            keyboard.layout.layers.indices.contains(layer),
            !keyWindows.values.contains(ShownLayer(layoutID: keyboard.id, layer: layer))
        else { return nil }
        switch hold {
        case .base, .pointer: return nil
        case let .momentary(key): return .full(layer: layer, heldBy: KeyRef(layer: held[key] ?? layer, index: key))
        case .locked:
            guard released != layer else { return nil }
            return switch settings.locked {
            case .full: .full(layer: layer, heldBy: nil)
            case .reminder: .pill(layer: layer)
            case .nothing: nil
            }
        }
    }

    /// Shows or hides now, or after the delay: a held layer waits for `delay`, unless the HUD already shows a held
    /// layer; a lock waits for `delay` and at least ``lockSettle``; one that typing hid waits for `delay` and at least
    /// ``typingSettle`` once the keys are let go. Hiding never waits.
    private func update() {
        if let typed, settings.typing == .keepShowing || typed.over != wanted { self.typed = nil }
        let hidden = typed.map { !$0.keys.isEmpty || settings.typing == .hideUntilNextHold } ?? false
        let target = hidden ? nil : wanted
        guard target != presentation else { return cancelPending() }
        guard let target else {
            cancelPending()
            presentation = nil
            return
        }
        // From a lock's reminder or overlay a quick tap of a layer key would flash the full overlay: only a held layer
        // replaces a held one at once.
        let delay: Duration =
            if case .full(_, heldBy: _?) = target {
                if case .full(_, heldBy: _?) = presentation { .zero } else { settings.delay }
            } else {
                max(settings.delay, Self.lockSettle)
            }
        // Typing hid it: it doesn't flash back between keystrokes, even with no delay.
        let wait = typed == nil ? delay : max(delay, Self.typingSettle)
        guard wait > .zero else {
            cancelPending()
            presentation = target
            return
        }
        guard pending?.target != target else { return }
        cancelPending()
        let clock = clock
        pending = (
            target,
            Task { [weak self] in
                do { try await clock.sleep(for: wait) } catch { return }
                guard let self, self.pending?.target == target else { return }
                self.pending = nil
                self.presentation = target
            }
        )
    }

    private func cancelPending() {
        pending?.task.cancel()
        pending = nil
    }

    /// Ends the preview ``previewTime`` from now, in place of any end set before; nothing to end while it is off.
    private func endPreviewLater() {
        previewEnd?.cancel()
        previewEnd = nil
        guard previewing else { return }
        let (clock, time) = (clock, Self.previewTime)
        previewEnd = Task { [weak self] in
            do { try await clock.sleep(for: time) } catch { return }
            self?.isPreviewing = false
        }
    }
}

/// The layer a key layout window's board shows.
struct ShownLayer: Hashable {
    var layoutID: UUID
    var layer: Int
}
