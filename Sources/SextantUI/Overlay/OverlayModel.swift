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

/// Settings › Keyboard's overlay options, with the defaults the pane declares (ADR 0045).
struct OverlaySettings: Equatable {
    var showsOverlay = true
    var delay = Duration.milliseconds(150)
    var position = OverlayPosition.bottom
    var size = OverlaySize.medium
    var tints = false
    var locked = LockedLayerOverlay.reminder

    init() {}

    init(_ defaults: UserDefaults) {
        showsOverlay = defaults.object(forKey: SettingsKey.showsOverlay) as? Bool ?? true
        delay = .milliseconds(min(max(defaults.object(forKey: SettingsKey.overlayDelay) as? Int ?? 150, 0), 500))
        position = defaults.string(forKey: SettingsKey.overlayPosition).flatMap(OverlayPosition.init) ?? .bottom
        size = defaults.string(forKey: SettingsKey.overlaySize).flatMap(OverlaySize.init) ?? .medium
        tints = defaults.bool(forKey: SettingsKey.tintsOverlay)
        locked = defaults.string(forKey: SettingsKey.lockedLayerOverlay).flatMap(LockedLayerOverlay.init) ?? .reminder
    }
}

/// The layout the keyboard runs (``OnKeyboard``), by library id.
struct OverlayLayout: Equatable {
    var id: UUID
    var layout: KeyboardLayout
}

/// When the overlay HUD shows, and what (spec §8.4, ADR 0050). It follows the keyboard's live activity: a layer a key
/// holds on shows the full overlay once the hold lasts the delay, and hides the moment that key is let go; a locked
/// layer shows a reminder (or the full overlay, or nothing, per Settings). It shows nothing while Live View is off,
/// during secure input, without the keyboard's layout, or while a Sextant window that is key shows the same layer.
@MainActor
@Observable
final class OverlayModel {
    /// What shows now; nil while the HUD is hidden.
    private(set) var presentation: OverlayPresentation?
    var settings = OverlaySettings() {
        didSet { if settings != oldValue { update() } }
    }
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
    /// Secure input is on: nothing shows, and the keys held are forgotten, since their key-ups won't arrive.
    var isSecureInputOn = false {
        didSet {
            guard isSecureInputOn != oldValue else { return }
            if isSecureInputOn { held = [:] }
            update()
        }
    }
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
    /// Each layout window that is key, with the layer its board shows.
    private var keyWindows: [ObjectIdentifier: ShownLayer] = [:]
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var pending: (target: OverlayPresentation, task: Task<Void, Never>)?

    /// A lock shows only once it has lasted this long, even with no delay: a held TT's key-up comes just before its
    /// layer ends.
    static let lockSettle = Duration.milliseconds(50)

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    /// Folds in one thing the keyboard did (``LiveSession/activity()``). A key-up without its key-down is ignored.
    func handle(_ activity: LiveActivity) {
        switch activity {
        case let .keyDown(index, layer): held[index] = layer
        case let .keyUp(index): keyUp(index)
        case let .layer(layer): (self.layer, released) = (layer, nil)
        case .lighting, .refused: return
        }
        update()
    }

    /// A layout window reports the layer its board shows while it is key; nil when it isn't key or shows a page.
    func window(_ window: ObjectIdentifier, shows shown: ShownLayer?) {
        guard keyWindows[window] != shown else { return }
        keyWindows[window] = shown
        update()
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

    /// Shows or hides now, or after the delay: a held layer waits for `delay`, unless the HUD already shows; a lock waits
    /// for `delay` and at least ``lockSettle``. Hiding never waits.
    private func update() {
        let target = wanted
        guard target != presentation else { return cancelPending() }
        guard let target else {
            cancelPending()
            presentation = nil
            return
        }
        let wait: Duration =
            if case .full(_, heldBy: _?) = target { presentation == nil ? settings.delay : .zero } else {
                max(settings.delay, Self.lockSettle)
            }
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
}

/// The layer a key layout window's board shows.
struct ShownLayer: Hashable {
    var layoutID: UUID
    var layer: Int
}
