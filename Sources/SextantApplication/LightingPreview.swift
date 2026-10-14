import Foundation
import Observation
import SextantDomain

/// Shows a layer's lighting on the keyboard while the user previews it (spec §6.2, ADR 0051): RGB takeover over the live
/// command channel (ADR 0038). App-wide; one window holds it at a time.
///
/// It writes only while Live View is paired and a window holds the preview, which only the user's toggle claims. The first
/// frame of a session takes the lights (`05 01`), fills them with the frame's most common color (`09`) and sets the rest
/// one by one (`06`); later frames send only the lights that changed. Every way the preview ends gives the keyboard its own
/// lighting back (`05 00`, through ``LiveSession/releaseLights()``, which also does it before Live View ends a session),
/// except a session that already ended: there is no board to write to, and a session paired again gets the whole frame
/// again.
@MainActor
@Observable
public final class LightingPreview {
    /// The window previewing, and its layout's title for the other windows' "Previewing in …".
    public struct Holder: Equatable, Sendable {
        fileprivate let id: ObjectIdentifier
        public let title: String
    }

    public static let brightnessRange = 0.1...1.0

    public private(set) var holder: Holder?
    /// Scales every color on the Mac before it is sent (``setBrightness(_:)``). The keyboard scales it again by its own
    /// brightness.
    public private(set) var brightness = 1.0

    /// The holder's latest frame, one color per LED (nil is off).
    @ObservationIgnored private var frame: [HexColor?]?
    /// What the keyboard shows from this paired session, to send only what changes; nil when unknown, so the next frame
    /// takes the lights first. Whether a release is due is the live session's to know: a reply can clear this.
    @ObservationIgnored private var shown: [LEDColor]?
    /// A batch was just queued: later frames wait for the link to write it, and the latest one then wins.
    @ObservationIgnored private var pacing: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let live: LiveSession
    @ObservationIgnored private let board: BoardDefinition

    public init(live: LiveSession, board: BoardDefinition = .voyager) {
        self.live = live
        self.board = board
    }

    /// Follows the live session for the app's lifetime: a session that ends forgets what the keyboard was sent, one that
    /// pairs gets the whole frame, and Live View turned off ends the preview.
    public func start() {
        guard tasks.isEmpty else { return }
        let live = live
        tasks = [
            Task {
                for await (canSend, isLive) in Observations({ (live.canSend, live.isLive) }) {
                    if !isLive {
                        (holder, frame) = (nil, nil)
                    }
                    if canSend { send() } else { shown = nil }
                }
            },
            Task {
                // Another host's `05 00` (Keymapp, Oryx in Chrome) gives the lights back too: the next frame takes them
                // again in full. A late reply to Sextant's own release costs one such resend.
                for await event in live.activity() where event == .lighting(false) { shown = nil }
            },
        ]
    }

    /// Why `owner` can't preview now; nil when it can, or already does.
    public func refusal(for owner: AnyObject) -> LightingPreviewRefusal? {
        if let holder { return holder.id == ObjectIdentifier(owner) ? nil : .previewingElsewhere(holder.title) }
        return keyboardRefusal
    }

    /// Why the keyboard can't show a preview now, whichever window holds it; nil while Live View is connected.
    public var keyboardRefusal: LightingPreviewRefusal? {
        switch live.connection {
        case .noKeyboard: return .noKeyboard
        case .bootloader: return .flashMode
        case .liveOff: return .liveOff
        case .heldByAnotherApp: return .heldByAnotherApp
        case .connected: return nil
        }
    }

    public func isHeld(by owner: AnyObject) -> Bool { holder?.id == ObjectIdentifier(owner) }

    /// Sets ``brightness``, clamped to ``brightnessRange``, and sends the frame at it.
    public func setBrightness(_ value: Double) {
        let clamped = min(max(value.isNaN ? 1 : value, Self.brightnessRange.lowerBound), Self.brightnessRange.upperBound)
        guard clamped != brightness else { return }
        brightness = clamped
        send()
    }

    /// Starts `owner`'s preview, on the user's toggle only. Nothing is written until its first ``show(_:for:title:)``.
    public func claim(for owner: AnyObject, title: String) throws(LightingPreviewRefusal) {
        if let refusal = refusal(for: owner) { throw refusal }
        holder = Holder(id: ObjectIdentifier(owner), title: title)
    }

    /// The holder's frame: one color per LED by key index (nil is off). Past the board's LEDs is dropped, and missing ones
    /// are off. Ignored from a window that doesn't hold the preview.
    public func show(_ colors: [HexColor?], for owner: AnyObject, title: String) {
        guard isHeld(by: owner) else { return }
        if holder?.title != title { holder = Holder(id: ObjectIdentifier(owner), title: title) }
        frame = (0..<board.keyCount).map { colors.indices.contains($0) ? colors[$0] : nil }
        send()
    }

    /// Ends `owner`'s preview: toggled off, Lighting left, another layout opened, the window closed.
    public func release(for owner: AnyObject) {
        guard isHeld(by: owner) else { return }
        end()
    }

    /// Ends the preview, whichever window holds it (the Mac going to sleep).
    public func releaseAll() { end() }

    // MARK: Sending

    /// Ends the preview and gives the keyboard its own lighting back, if this session took it.
    private func end() {
        (holder, frame, shown) = (nil, nil, nil)
        live.releaseLights()
    }

    /// Queues the frame's changes now, unless a batch is still being written: then the pacing task sends the latest
    /// frame once it is.
    private func send() {
        guard pacing == nil, sendChanges() else { return }
        pacing = Task {
            // Waiting until the link has likely written each batch keeps at most one queued, however fast frames come.
            repeat { await live.waitForQueuedWrites() } while sendChanges()
            pacing = nil
        }
    }

    /// Queues the commands that bring the keyboard from what it shows to the latest frame; false when there are none.
    private func sendChanges() -> Bool {
        guard holder != nil, let frame, live.canSend else { return false }
        let target = frame.map { $0.map { LEDColor($0, brightness: brightness) } ?? .off }
        let batch = Self.commands(showing: target, over: shown).filter { $0.isAllowed(on: board) }
        guard !batch.isEmpty else { return false }
        do throws(DeviceError) {
            for command in batch { try live.send(command) }
            shown = target
            return true
        } catch {
            // The session ended under it: the watcher resends the whole frame when one pairs again.
            shown = nil
            return false
        }
    }

    /// The commands that change `shown` into `target`. Without `shown` they take the lights, fill them with the most
    /// common color and set the rest; otherwise they set the lights that differ, or fill again when that is fewer writes.
    static func commands(showing target: [LEDColor], over shown: [LEDColor]?) -> [KeyboardCommand] {
        let changed = target.indices.filter { shown?.indices.contains($0) != true || shown?[$0] != target[$0] }
        guard !changed.isEmpty else { return [] }
        let common = mostCommon(target)
        let rest = target.indices.filter { target[$0] != common }
        func set(_ i: Int) -> KeyboardCommand { .setLED(index: i, red: target[i].red, green: target[i].green, blue: target[i].blue) }
        if let shown, shown.count == target.count, changed.count <= rest.count + 1 { return changed.map(set) }
        let fill = KeyboardCommand.setAllLEDs(red: common.red, green: common.green, blue: common.blue)
        return (shown == nil ? [.lighting(true)] : []) + [fill] + rest.map(set)
    }

    /// The most common color; of equally common ones, the first by index.
    private static func mostCommon(_ colors: [LEDColor]) -> LEDColor {
        var counts: [LEDColor: Int] = [:]
        var best = (color: colors.first ?? .off, count: 0)
        for color in colors {
            counts[color, default: 0] += 1
            if let count = counts[color], count > best.count { best = (color, count) }
        }
        return best.color
    }
}

/// Why a window can't preview lighting on the keyboard now (ADR 0051).
public enum LightingPreviewRefusal: Error, Hashable, Sendable, LocalizedError {
    case noKeyboard
    case flashMode
    /// Live View is off (ADR 0057): nothing is written to the keyboard.
    case liveOff
    case heldByAnotherApp
    /// Another window previews its layout: the title.
    case previewingElsewhere(String)

    public var errorDescription: String? {
        switch self {
        case .noKeyboard: String(localized: "Connect your keyboard to preview lighting on it.")
        case .flashMode: String(localized: "The keyboard is in flash mode.")
        case .liveOff: String(localized: "Turn on Live View to preview lighting on the keyboard.")
        case .heldByAnotherApp: DeviceError.heldByAnotherApp.localizedDescription
        case let .previewingElsewhere(title): String(localized: "Previewing in \(title)")
        }
    }
}
