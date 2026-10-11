import Foundation
import Observation

/// One live event, as the raw-HID protocol would report it (physical presses before tap-hold resolution,
/// and layer changes).
public struct LiveEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case keyDown(Int)
        case keyUp(Int)
        /// Highest active layer changed.
        case layer(Int)
    }
    /// Seconds from the start of the script.
    public var time: TimeInterval
    public var kind: Kind
}

/// A timed sequence of live events.
public struct LiveScript: Hashable, Sendable {
    public var events: [LiveEvent]
    /// Total length; a looping simulation restarts after this.
    public var duration: TimeInterval

    /// The default script on the user's layout:
    /// 0.0 s type "hello world" on Main · 2.0 s hold Space (Brd+Sys) and press ↑ ↑ → → → · 3.6 s release ·
    /// 4.0 s hold Enter (Sym+Num) and type ( 1 2 ) · 5.3 s release · 5.8 s type "ok" · 7.0 s end.
    public static func typingAndLayerHold(layout: KeyboardLayout) -> LiveScript {
        var b = ScriptBuilder(layout: layout)
        b.type("hello world", at: 0.0)
        b.hold(index: 51, layer: 2, from: 2.0, until: 3.6)       // Space / hold Brd+Sys
        b.tap(index: 40, at: 2.35); b.tap(index: 40, at: 2.55)    // ↑ ↑
        b.tap(index: 41, at: 2.8); b.tap(index: 41, at: 3.0); b.tap(index: 41, at: 3.2) // → → →
        b.hold(index: 24, layer: 1, from: 4.0, until: 5.3)       // Enter / hold Sym+Num
        b.tap(index: 16, at: 4.35); b.tap(index: 44, at: 4.55); b.tap(index: 45, at: 4.75); b.tap(index: 17, at: 4.95) // ( 1 2 )
        b.type("ok", at: 5.8)
        return LiveScript(events: b.events.sorted { $0.time < $1.time }, duration: 7.0)
    }

    /// Typing only (no layers), for heat or press-animation demos.
    public static func typing(_ text: String, layout: KeyboardLayout, start: TimeInterval = 0) -> LiveScript {
        var b = ScriptBuilder(layout: layout)
        let end = b.type(text, at: start)
        return LiveScript(events: b.events.sorted { $0.time < $1.time }, duration: end + 0.5)
    }
}

private struct ScriptBuilder {
    let layout: KeyboardLayout
    var events: [LiveEvent] = []
    let interval = 0.13
    let press = 0.075

    mutating func tap(index: Int, at t: TimeInterval) {
        events.append(LiveEvent(time: t, kind: .keyDown(index)))
        events.append(LiveEvent(time: t + press, kind: .keyUp(index)))
    }

    /// Holds a layer key; the layer engages after a 200 ms tapping term.
    mutating func hold(index: Int, layer: Int, from: TimeInterval, until: TimeInterval) {
        events.append(LiveEvent(time: from, kind: .keyDown(index)))
        events.append(LiveEvent(time: from + 0.2, kind: .layer(layer)))
        events.append(LiveEvent(time: until, kind: .keyUp(index)))
        events.append(LiveEvent(time: until, kind: .layer(0)))
    }

    @discardableResult
    mutating func type(_ text: String, at start: TimeInterval) -> TimeInterval {
        var t = start
        for ch in text.uppercased() {
            if let i = index(for: ch) { tap(index: i, at: t) }
            t += interval
        }
        return t
    }

    func index(for ch: Character) -> Int? {
        let code: String = switch ch {
        case " ": "KC_SPACE"
        case ".": "KC_DOT"
        case ",": "KC_COMMA"
        default: "KC_\(ch)"
        }
        return layout.layers.first?.keys.firstIndex { $0.tap?.canonicalCode == code }
    }
}

/// A connected ZSA Voyager, simulated. Never touches USB or HID.
///
/// Use ``seek(to:)`` for deterministic snapshot states (e.g. `seek(to: 2.6)` shows Brd+Sys held with ↑ pressed),
/// or ``start(loop:)`` to animate in a running prototype.
@MainActor
@Observable
public final class MockDevice {
    public enum Connection: String, Hashable, Sendable, CaseIterable {
        case disconnected
        case searching
        case connected
        /// Another app (e.g. Keymapp) holds the device exclusively.
        case heldByAnotherApp
        /// Board is in its bootloader (flash mode).
        case bootloader
    }

    // Identity (what the real board reports).
    public let name = "ZSA Voyager"
    /// USB serial number: Oryx layout id / revision id.
    public let serialNumber = "KlgM7/40xJ7M"
    public var layoutID: String { String(serialNumber.split(separator: "/").first ?? "") }
    public var revisionID: String { String(serialNumber.split(separator: "/").last ?? "") }
    /// ZSA firmware line.
    public let firmwareVersion = "25.0"
    /// Raw-HID protocol version (`FE` → `FE 05 FE`).
    public let protocolVersion = 5
    public let vendorID = 0x3297
    public let productID = 0x1977
    /// The Navigator attached to the user's board.
    public let navigator = NavigatorConfig(kind: .trackpad, side: .right)

    // Live state.
    public var connection: Connection
    /// Highest active layer reported by the keyboard.
    public var activeLayer: Int = 0
    /// Keys physically held right now (key indices).
    public var pressedKeys: Set<Int> = []
    /// The four status LEDs. Stock firmware shows the active layer's bits (LED 1 = bit 0 … LED 4 = bit 3).
    public var statusLEDs: [Bool] = [false, false, false, false]
    /// Global LED brightness 0...1.
    public var ledBrightness: Double = 0.8
    /// Most recent event.
    public var lastEvent: LiveEvent?
    /// Presses since connection (feeds a live heatmap).
    public var pressCounts: [Int: Int] = [:]
    /// Current position in the script, seconds.
    public private(set) var time: TimeInterval = 0
    public private(set) var isSimulating = false

    public let layout: KeyboardLayout
    public let script: LiveScript
    private var task: Task<Void, Never>?

    public init(layout: KeyboardLayout = Samples.layout, script: LiveScript? = nil, connection: Connection = .connected) {
        self.layout = layout
        self.script = script ?? .typingAndLayerHold(layout: layout)
        self.connection = connection
    }

    /// A device frozen at a script time (handy in snapshot scenes).
    public static func frozen(at time: TimeInterval, layout: KeyboardLayout = Samples.layout) -> MockDevice {
        let d = MockDevice(layout: layout)
        d.seek(to: time)
        return d
    }

    /// Recomputes state as of `time` from the start of the script.
    public func seek(to time: TimeInterval) {
        activeLayer = 0
        pressedKeys = []
        pressCounts = [:]
        lastEvent = nil
        for e in script.events where e.time <= time { apply(e) }
        statusLEDs = Self.layerBits(activeLayer)
        self.time = time
    }

    /// Applies one event.
    public func apply(_ event: LiveEvent) {
        switch event.kind {
        case let .keyDown(i):
            pressedKeys.insert(i)
            pressCounts[i, default: 0] += 1
        case let .keyUp(i):
            pressedKeys.remove(i)
        case let .layer(l):
            activeLayer = l
            statusLEDs = Self.layerBits(l)
        }
        lastEvent = event
    }

    /// Status LED pattern for a layer index (binary, as voyager.c does without a host override).
    public static func layerBits(_ layer: Int) -> [Bool] { (0..<4).map { (layer >> $0) & 1 == 1 } }

    /// Plays the script in real time on the main actor.
    public func start(loop: Bool = true, speed: Double = 1) {
        stop()
        isSimulating = true
        connection = .connected
        task = Task { [weak self] in
            repeat {
                guard let self else { return }
                self.seek(to: 0)
                var last: TimeInterval = 0
                for e in self.script.events {
                    let wait = (e.time - last) / speed
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    if Task.isCancelled { return }
                    self.apply(e)
                    self.time = e.time
                    last = e.time
                }
                try? await Task.sleep(for: .seconds(max(0, self.script.duration - last) / speed))
            } while loop && !Task.isCancelled
            self?.isSimulating = false
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isSimulating = false
    }
}
