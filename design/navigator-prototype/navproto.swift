// The `AppleCurve` section re-expresses PACurvesSetupAccelParams and PACurvesGetAccelerationMultiplier from
// Apple's IOHIDFamily (IOHIDSystem/IOHIPointing.cpp, Apple Public Source License 2.0). That section stays
// under APSL-2.0; see ADR 0068 before porting it.

// Throwaway Navigator gesture prototype. NOT production code.
//
// Device writes (approved per run by the user): feature report 4 (input mode) on the Navigator's
// digitizer interface only: 3 (PTP) on attach and on wake, 0 (mouse) on exit. Nothing else is sent.
//
// Gestures: one finger moves the pointer (macOS-like acceleration), one-finger tap = left click,
// two-finger tap = right click, tap then touch-and-move = drag, two-finger move = phased scroll
// with momentum.
//
// Usage: navproto [--seconds N] [--verbose]
//   pointer:   [--tracking 0...3] [--speed X] [--scale X] [--knee mm/s] [--top 0...1] [--hold frames]
//   scrolling: [--scroll X] [--friction X] [--no-momentum] [--traditional]
//   dragging:  [--drag-window s] [--drag-radius mm] [--drag-lock s] [--no-drag]
//   pad:       [--flip-x] [--flip-y] [--swap-xy]
//        navproto --curve                (prints the pointer curve; touches nothing)
//        navproto --replay capture.txt   (feeds a probe capture through the engine; posts nothing)
// Build: swiftc -swift-version 5 -O navproto.swift -o navproto
import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

// MARK: - Options

struct Options {
    var seconds: Double = 0
    var speed = 1.0
    var scroll = 1.0
    var friction = 0.997  // velocity kept per millisecond of momentum
    var momentum = true
    var natural = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.swipescrolldirection"] as? Bool) ?? true
    var flipX = false, flipY = false, swapXY = false
    var verbose = false
    var replay: String?
    var tracking: Double?         // System Settings tracking speed (0...3); default: the user's
    var scale = 1.0               // treat the pad as this many times its real size
    var knee = 100.0              // mm/s above which acceleration is softened
    var top = 0.6                 // share of the curve's extra gain kept above the knee (1 = Apple's)
    var holdFrames = 2            // ~13 ms of latency to drop lift-off roll
    var dragWindow = 0.2          // s after a tap in which a touch-and-move drags
    var dragRadius = 4.0          // mm: a drag's second touch must land this close to the tap
    var dragLock = 0.0            // s the button stays down after a drag lifts; 0 = off

    init(_ args: [String]) {
        var i = 1
        func next() -> String { i += 1; return i < args.count ? args[i] : "" }
        while i < args.count {
            switch args[i] {
            case "--seconds": seconds = Double(next()) ?? 0
            case "--speed": speed = Double(next()) ?? 1
            case "--scroll": scroll = Double(next()) ?? 1
            case "--friction": friction = Double(next()) ?? 0.997
            case "--no-momentum": momentum = false
            case "--traditional": natural = false
            case "--flip-x": flipX = true
            case "--flip-y": flipY = true
            case "--swap-xy": swapXY = true
            case "--verbose": verbose = true
            case "--replay": replay = next()
            case "--curve": break
            case "--tracking": tracking = Double(next())
            case "--scale": scale = Double(next()) ?? 1
            case "--knee": knee = Double(next()) ?? 100
            case "--top": top = Double(next()) ?? 0.6
            case "--hold": holdFrames = Int(next()) ?? 2
            case "--drag-window": dragWindow = Double(next()) ?? 0.2
            case "--drag-lock": dragLock = Double(next()) ?? 0
            case "--drag-radius": dragRadius = Double(next()) ?? 4
            case "--no-drag": dragWindow = 0
            default: print("unknown option \(args[i])"); exit(2)
            }
            i += 1
        }
    }
}
let opts = Options(CommandLine.arguments)

// MARK: - Report parsing (zsa/qmk_modules navigator_trackpad_ptp.c, report 1)

struct Contact { var id: Int; var x: Double; var y: Double }
struct Frame { var contacts: [Contact]; var scan: Int }

let unitsPerMM = 2048.0 / 40.0  // logical range over the ~40 mm pad

func parse(_ b: [UInt8]) -> Frame? {
    guard b.count >= 16, b[0] == 1 else { return nil }
    var cs: [Contact] = []
    for o in [1, 7] where b[o] & 0x03 == 0x03 {  // confidence and tip
        var x = Double(Int(b[o + 2]) | Int(b[o + 3]) << 8), y = Double(Int(b[o + 4]) | Int(b[o + 5]) << 8)
        if opts.swapXY { swap(&x, &y) }
        if opts.flipX { x = 2048 - x }
        if opts.flipY { y = 2048 - y }
        cs.append(Contact(id: Int(b[o + 1] & 0x07), x: x, y: y))
    }
    // One finger split into two: drop a second contact closer than ~1.2 mm.
    if cs.count == 2, hypot(cs[0].x - cs[1].x, cs[0].y - cs[1].y) < 60 { cs.removeLast() }
    return Frame(contacts: cs, scan: Int(b[13]) | Int(b[14]) << 8)
}

// MARK: - Output (CGEvent), or a log in replay mode

protocol Output {
    func move(dx: Double, dy: Double, dragging: Bool)
    func click(right: Bool, down: Bool, clickState: Int)
    func scroll(dx: Double, dy: Double, phase: Int64, momentum: Int64)
}

final class LogOutput: Output {
    func move(dx: Double, dy: Double, dragging: Bool) {}
    func click(right: Bool, down: Bool, clickState: Int) { print("  \(right ? "right" : "left") \(down ? "down" : "up") x\(clickState)") }
    func scroll(dx: Double, dy: Double, phase: Int64, momentum: Int64) {
        if phase != 2 && momentum != 2 { print(String(format: "  scroll phase=%lld momentum=%lld", phase, momentum)) }
    }
}

final class EventOutput: Output {
    let source = CGEventSource(stateID: .hidSystemState)
    var remX = 0.0, remY = 0.0, sremX = 0.0, sremY = 0.0

    var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    func clamp(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        let bounds = ids.prefix(Int(n)).map { CGDisplayBounds($0) }
        if bounds.contains(where: { $0.contains(p) }) { return p }
        let home = bounds.first(where: { $0.contains(old) }) ?? bounds.first ?? .zero
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1), y: min(max(p.y, home.minY), home.maxY - 1))
    }

    func post(_ e: CGEvent?) {
        guard let e else { return }
        e.flags = CGEventSource.flagsState(.hidSystemState)
        e.post(tap: .cghidEventTap)
    }

    func move(dx: Double, dy: Double, dragging: Bool) {
        remX += dx; remY += dy
        let ix = remX.rounded(.towardZero), iy = remY.rounded(.towardZero)
        guard ix != 0 || iy != 0 else { return }
        remX -= ix; remY -= iy
        let old = cursor
        let p = clamp(CGPoint(x: old.x + ix, y: old.y + iy), from: old)
        let held = dragging || CGEventSource.buttonState(.hidSystemState, button: .left)
        let e = CGEvent(mouseEventSource: source, mouseType: held ? .leftMouseDragged : .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(ix))
        e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(iy))
        post(e)
    }

    func click(right: Bool, down: Bool, clickState: Int) {
        let type: CGEventType = right ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .leftMouseDown : .leftMouseUp)
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: cursor, mouseButton: right ? .right : .left)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        post(e)
    }

    func scroll(dx: Double, dy: Double, phase: Int64, momentum: Int64) {
        sremX += dx; sremY += dy
        let ix = sremX.rounded(.towardZero), iy = sremY.rounded(.towardZero)
        sremX -= ix; sremY -= iy
        let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(iy), wheel2: Int32(ix), wheel3: 0)
        e?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e?.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        post(e)
    }
}

// MARK: - Apple's parametric acceleration (IOHIDFamily IOHIPointing.cpp, PACurves*)

struct AppleCurve {
    var gain = [1.0, 0, 0, 0]       // linear, parabolic, cubic, quartic
    var tangent = [0.0, 0]          // linear, parabolic-root (inches/s)
    var firstTangent = 0, m0 = 0.0, b0 = 0.0, y1 = 0.0, mRoot = 0.0, bRoot = 0.0

    static func quartic(_ x: Double, _ g: [Double]) -> Double { g[0] * x + g[1] * x * x + g[2] * x * x * x + g[3] * x * x * x * x }
    static func derivative(_ x: Double, _ g: [Double]) -> Double { g[0] + 2 * g[1] * x + 3 * g[2] * x * x + 4 * g[3] * x * x * x }

    /// Reads the built-in or Magic Trackpad's curve set and interpolates it at `desired` (tracking speed).
    init(desired: Double) {
        var curves: [[String: Any]] = []
        var it: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &it) == KERN_SUCCESS {
            while case let svc = IOIteratorNext(it), svc != 0 {
                defer { IOObjectRelease(svc) }
                let type = IORegistryEntryCreateCFProperty(svc, "HIDPointerAccelerationType" as CFString, nil, 0)?.takeRetainedValue() as? String
                if type == "HIDTrackpadAcceleration", curves.isEmpty,
                   let c = IORegistryEntryCreateCFProperty(svc, "HIDAccelCurves" as CFString, nil, 0)?.takeRetainedValue() as? [[String: Any]] {
                    curves = c
                }
            }
            IOObjectRelease(it)
        }
        guard !curves.isEmpty else { print("No Apple trackpad curves found; using linear"); return }
        func num(_ d: [String: Any], _ k: String) -> Double { Double((d[k] as? NSNumber)?.int64Value ?? 0) / 65536 }
        func params(_ d: [String: Any]) -> (i: Double, g: [Double], t: [Double]) {
            (num(d, "HIDAccelIndex"),
             [num(d, "HIDAccelGainLinear"), num(d, "HIDAccelGainParabolic"), num(d, "HIDAccelGainCubic"), num(d, "HIDAccelGainQuartic")],
             [num(d, "HIDAccelTangentSpeedLinear"), num(d, "HIDAccelTangentSpeedParabolicRoot")])
        }
        let ps = curves.map(params).sorted { $0.i < $1.i }
        var lo = ps[0], hi = ps[0]
        for p in ps { hi = p; if desired <= p.i { break }; lo = p }
        if hi.i > lo.i {
            let r = (desired - lo.i) / (hi.i - lo.i)
            gain = (0..<4).map { max(lo.g[$0] + (hi.g[$0] - lo.g[$0]) * r, 0) }
            tangent = (0..<2).map { max(lo.t[$0] + (hi.t[$0] - lo.t[$0]) * r, 0) }
        } else { gain = hi.g; tangent = hi.t }
        if tangent[1] > 0 && tangent[1] < tangent[0] { firstTangent = 1 }
        if firstTangent == 0 {
            let y0 = Self.quartic(tangent[0], gain)
            m0 = Self.derivative(tangent[0], gain); b0 = y0 - m0 * tangent[0]; y1 = m0 * tangent[1] + b0
        } else {
            y1 = Self.quartic(tangent[1], gain); m0 = Self.derivative(tangent[1], gain)
        }
        mRoot = m0 * y1 * 2; bRoot = y1 * y1 - mRoot * tangent[1]
    }

    /// Output speed / input speed, both in inches per second.
    func multiplier(inchesPerSecond v: Double) -> Double {
        guard v > 0 else { return gain[0] }
        let out: Double
        if tangent[firstTangent] != 0 && v <= tangent[firstTangent] { out = Self.quartic(v, gain) }
        else if firstTangent == 0 && tangent[1] != 0 && v <= tangent[1] { out = m0 * v + b0 }
        else { out = (mRoot * v + bRoot).squareRoot() }
        return out / v
    }
}

let trackingSpeed = opts.tracking ?? (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.trackpad.scaling"] as? Double) ?? 0.6875
let appleCurve = AppleCurve(desired: trackingSpeed)

// MARK: - Engine

final class Engine {
    let out: Output
    init(out: Output) { self.out = out }

    // Touch session: from the first finger down to the last finger up.
    var inSession = false
    var sessionStart = 0.0
    var maxFingers = 0
    var travel = 0.0                 // pad units, summed over contacts
    var pointerLive = false          // settle passed: pointer moves
    var pending = (dx: 0.0, dy: 0.0) // motion held back during settle
    var last: [Int: Contact] = [:]
    var lastScan = 0
    var time = 0.0                   // seconds, from scan times

    // Clicking and dragging
    var lastTapEnd = -10.0, lastTapClicks = 0, lastTapPoint = CGPoint.zero
    var lastTapPad: Contact?, sessionFirst: Contact?, lastTapClean = false
    var dragArmed = false, dragging = false
    var dragLockTimer: DispatchWorkItem?   // button stays down briefly after a drag lifts
    var dragContinued = false

    // Pointer shaping
    var speed = 0.0                        // mm/s, smoothed
    var queue: [(Double, Double)] = []     // last frames held back, dropped on lift (finger roll)
    var twoFingerFrames = 0

    // Scrolling
    enum Axis { case free, x, y }
    var scrolling = false, scrollAxis = Axis.free, scrollTravel = (x: 0.0, y: 0.0)
    var vel = (x: 0.0, y: 0.0)       // px/s, smoothed
    var momentumTimer: DispatchSourceTimer?

    func log(_ s: @autoclosure () -> String) { if opts.verbose || opts.replay != nil { print(String(format: "%7.3f ", time) + s()) } }

    // Points per mm of finger travel, from Apple's trackpad curve at the user's tracking speed.
    // Above the knee, only `top` of the curve's extra acceleration is kept, so fast moves overshoot less.
    func gain(_ mmPerSec: Double) -> Double {
        let inchesPerMM = opts.scale / 25.4
        func apple(_ v: Double) -> Double { opts.speed * 96 * inchesPerMM * appleCurve.multiplier(inchesPerSecond: v * inchesPerMM) }
        guard mmPerSec > opts.knee else { return apple(mmPerSec) }
        let atKnee = apple(opts.knee)
        return atKnee + (apple(mmPerSec) - atKnee) * opts.top
    }

    func scrollGain(_ mmPerSec: Double) -> Double {
        let t = min(max((mmPerSec - 20) / (250 - 20), 0), 1)
        return opts.scroll * (9 + (28 - 9) * t * t)
    }

    func handle(_ f: Frame, at t: Double) {
        var dt = Double((f.scan - lastScan + 65536) % 65536) / 10000
        if dt <= 0 || dt > 0.05 { dt = 0.0065 }
        lastScan = f.scan
        time = t

        let now = Dictionary(uniqueKeysWithValues: f.contacts.map { ($0.id, $0) })
        if !inSession && !now.isEmpty { sessionFirst = f.contacts.first; begin() }
        guard inSession else { return }
        maxFingers = max(maxFingers, now.count)

        // Per-contact motion for contacts present in both frames.
        var mx = 0.0, my = 0.0, n = 0.0
        for (id, c) in now { if let p = last[id] { mx += c.x - p.x; my += c.y - p.y; n += 1 } }
        if n > 0 { mx /= n; my /= n; travel += hypot(mx, my) }
        last = now

        if now.isEmpty { end(); return }

        // A touch is two-finger once both fingers stay down ~40 ms; a brief blip of a second
        // contact is ignored. Two-finger frames never move the pointer, and neither does
        // anything after the touch became two-finger.
        let twoNow = now.count >= 2 && n >= 2
        if twoNow { twoFingerFrames += 1 }
        if twoFingerFrames > 6 {
            if twoNow { scrollStep(mx: mx, my: my, dt: dt) }
            return
        }
        if now.count >= 2 { return }

        // One finger: pointer. Speed for the gain is smoothed over ~40 ms, and a single
        // frame far faster than that is clamped, so one noisy frame can't fling the pointer.
        var fx = mx, fy = my
        let frameSpeed = hypot(mx, my) / unitsPerMM / dt
        let limit = max(3 * speed, 80)
        if frameSpeed > limit { fx *= limit / frameSpeed; fy *= limit / frameSpeed }
        let a = 1 - exp(-dt / 0.025)
        speed += a * (min(frameSpeed, limit) - speed)
        let g = gain(speed)
        let dx = fx / unitsPerMM * g, dy = fy / unitsPerMM * g
        if !pointerLive {
            // Settle: motion during the first moments of a touch is dropped, not replayed.
            if travel > 25 || time - sessionStart > 0.12 { pointerLive = true }
            return
        }
        if dragArmed && !dragging && travel > 40 { dragging = true; out.click(right: false, down: true, clickState: 1); log("drag start") }
        // Hold back the newest frames; the frames just before a lift are finger roll.
        queue.append((dx, dy))
        if queue.count > opts.holdFrames {
            let (qx, qy) = queue.removeFirst()
            if qx != 0 || qy != 0 { out.move(dx: qx, dy: qy, dragging: dragging) }
        }
    }

    func begin() {
        stopMomentum()
        inSession = true; sessionStart = time; maxFingers = 0; travel = 0
        pointerLive = false; pending = (0, 0); last = [:]
        speed = 0; queue = []; twoFingerFrames = 0
        dragContinued = false
        if let lock = dragLockTimer {  // touched again while a drag was locked: keep dragging
            lock.cancel(); dragLockTimer = nil; dragContinued = true; log("drag continue")
        }
        // Tap-drag only when the second touch lands where the tap was: a reposition lands elsewhere.
        var near = false
        if let a = lastTapPad, let b = sessionFirst { near = hypot(a.x - b.x, a.y - b.y) / unitsPerMM <= opts.dragRadius }
        dragArmed = !dragging && near && time - lastTapEnd < opts.dragWindow && lastTapClean
        if !near && time - lastTapEnd < opts.dragWindow && lastTapClean { log("tap then touch elsewhere: no drag") }
        scrolling = false; scrollAxis = .free; scrollTravel = (0, 0); vel = (0, 0)
    }

    func end() {
        inSession = false
        let dur = time - sessionStart
        queue = []
        if dragging {
            // A quick tap while a drag is locked drops it; otherwise lock the button for a moment
            // so the finger can be repositioned on the small pad.
            let tap = dragContinued && dur < 0.18 && travel < 60
            if tap || opts.dragLock <= 0 { releaseDrag(); return }
            log("drag locked")
            let item = DispatchWorkItem { [weak self] in self?.dragLockTimer = nil; self?.releaseDrag() }
            dragLockTimer = item
            if out is LogOutput { releaseDrag() } else { DispatchQueue.main.asyncAfter(deadline: .now() + opts.dragLock, execute: item) }
            return
        }
        if scrolling { scrollEnd(); return }
        let right = twoFingerFrames >= 4
        let isTap = dur < (right ? 0.22 : 0.18) && travel < (right ? 120 : 60)
        guard isTap else { return }
        let cursor = (out as? EventOutput)?.cursor ?? .zero
        var clicks = 1
        if !right && time - lastTapEnd < NSEvent.doubleClickInterval && hypot(cursor.x - lastTapPoint.x, cursor.y - lastTapPoint.y) < 6 {
            clicks = min(lastTapClicks + 1, 3)
        }
        out.click(right: right, down: true, clickState: clicks)
        out.click(right: right, down: false, clickState: clicks)
        log("\(right ? "right" : "left") click x\(clicks) (\(Int(dur * 1000)) ms, travel \(Int(travel)))")
        lastTapEnd = time; lastTapClicks = right ? 0 : clicks; lastTapPoint = cursor
        lastTapPad = sessionFirst
        lastTapClean = !right && clicks == 1 && travel <= 25  // a sloppy tap clicks but never arms a drag
    }

    func releaseDrag() {
        out.click(right: false, down: false, clickState: 1); dragging = false; lastTapClicks = 0
        log("drag end")
    }

    func scrollStep(mx: Double, my: Double, dt: Double) {
        let sign = opts.natural ? 1.0 : -1.0
        let mm = hypot(mx, my) / unitsPerMM
        let g = scrollGain(mm / dt)
        var sx = sign * mx / unitsPerMM * g, sy = sign * my / unitsPerMM * g
        scrollTravel.x += abs(mx); scrollTravel.y += abs(my)
        if !scrolling {
            guard scrollTravel.x + scrollTravel.y > 50 else { return }  // ~0.5 mm before a scroll starts
            scrolling = true
            out.scroll(dx: 0, dy: 0, phase: 1, momentum: 0)  // began
            log("scroll began")
        }
        // Lock to the dominant axis once the first ~6 mm show a clear direction.
        if scrollAxis == .free && scrollTravel.x + scrollTravel.y > 300 {
            if scrollTravel.y > 2 * scrollTravel.x { scrollAxis = .y } else if scrollTravel.x > 2 * scrollTravel.y { scrollAxis = .x }
        }
        if scrollAxis == .y { sx = 0 }
        if scrollAxis == .x { sy = 0 }
        let a = 0.35
        vel.x = (1 - a) * vel.x + a * sx / dt; vel.y = (1 - a) * vel.y + a * sy / dt
        out.scroll(dx: sx, dy: sy, phase: 2, momentum: 0)  // changed
    }

    func scrollEnd() {
        out.scroll(dx: 0, dy: 0, phase: 4, momentum: 0)  // ended
        let speed = hypot(vel.x, vel.y)
        log(String(format: "scroll ended, release %.0f px/s", speed))
        guard opts.momentum, speed > 150 else { return }
        if speed > 6000 { vel.x *= 6000 / speed; vel.y *= 6000 / speed }
        startMomentum()
    }

    func startMomentum() {
        var v = vel, first = true
        let tick = 1.0 / 120
        let keep = pow(opts.friction, tick * 1000)
        if out is LogOutput { log("momentum"); return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: tick)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            v.x *= keep; v.y *= keep
            if hypot(v.x, v.y) < 12 { self.out.scroll(dx: 0, dy: 0, phase: 0, momentum: 3); self.stopMomentum(); return }
            self.out.scroll(dx: v.x * tick, dy: v.y * tick, phase: 0, momentum: first ? 1 : 2)
            first = false
        }
        momentumTimer = t
        t.resume()
    }

    func stopMomentum() {
        guard let t = momentumTimer else { return }
        t.cancel(); momentumTimer = nil
        out.scroll(dx: 0, dy: 0, phase: 0, momentum: 3)
    }
}

// MARK: - Curve print (offline)

if CommandLine.arguments.contains("--curve") {
    let e = Engine(out: LogOutput())
    print(String(format: "Apple trackpad curve at tracking speed %.4f, pad scale %.2f, top end %.2f above %.0f mm/s", trackingSpeed, opts.scale, opts.top, opts.knee))
    for mm in [5.0, 20, 50, 100, 180, 300] { print(String(format: "  %3.0f mm/s -> %5.1f pt/mm", mm, e.gain(mm))) }
    exit(0)
}

// MARK: - Replay mode (offline, posts nothing)

if let path = opts.replay {
    let engine = Engine(out: LogOutput())
    let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    for line in text.split(separator: "\n") where line.contains("id=1 len=16") {
        let parts = line.components(separatedBy: "  ")
        guard parts.count > 1 else { continue }
        let bytes = parts[1].split(separator: " ").compactMap { UInt8($0, radix: 16) }
        if let f = parse(bytes), let t = Double(line.split(separator: " ")[0]) { engine.handle(f, at: t) }
    }
    exit(0)
}

// MARK: - Live mode

guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
    print("Needs Accessibility (System Settings › Privacy & Security › Accessibility) to post events. Grant it and run again.")
    exit(1)
}

let engine = Engine(out: EventOutput())
var device: IOHIDDevice?
let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

func setMode(_ d: IOHIDDevice, _ mode: UInt8) {
    let bytes: [UInt8] = [0x04, mode]
    let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 4, bytes, bytes.count)
    print(String(format: "input mode -> %d (0x%08X)", mode, r))
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x3297, kIOHIDPrimaryUsagePageKey: 0x0D, kIOHIDPrimaryUsageKey: 0x05] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, d in
    print("Navigator attached")
    device = d
    setMode(d, 3)
    IOHIDDeviceRegisterInputReportCallback(d, reportBuffer, 64, { _, _, _, _, _, report, length in
        if let f = parse([UInt8](UnsafeBufferPointer(start: report, count: length))) { engine.handle(f, at: ProcessInfo.processInfo.systemUptime) }
    }, nil)
}, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in print("Navigator removed"); device = nil }, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess { print(String(format: "open failed 0x%08X (Input Monitoring?)", openResult)) }

// The firmware drops back to mouse mode on power loss; re-assert after wake.
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    if let d = device { setMode(d, 3) }
}

func restoreAndExit() -> Never {
    if let d = device { setMode(d, 0) }
    exit(0)
}
signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
let sigs = [SIGINT, SIGTERM].map { s -> DispatchSourceSignal in
    let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
    src.setEventHandler { restoreAndExit() }
    src.resume()
    return src
}
if opts.seconds > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + opts.seconds) { restoreAndExit() } }
print(String(format: "Apple trackpad curve at tracking speed %.4f, pad scale %.2f, top end %.2f above %.0f mm/s", trackingSpeed, opts.scale, opts.top, opts.knee))
for mm in [5.0, 20, 50, 100, 180, 300] { print(String(format: "  %3.0f mm/s -> %5.1f pt/mm", mm, engine.gain(mm))) }
print("Running\(opts.seconds > 0 ? " for \(Int(opts.seconds)) s" : ""); natural scrolling \(opts.natural ? "on" : "off"). Ctrl-C to stop.")
CFRunLoopRun()
