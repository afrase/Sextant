import ApplicationServices
import CoreGraphics
import Foundation
import SextantApplication
import SextantDomain

/// Posts the Navigator driver's intents as Quartz events at the HID level, so the Mac treats them like a real pointing
/// device's (ADR 0068). Needs Accessibility. Fractions of a point carry over to the next event, so slow moves and
/// scrolls lose nothing.
public actor CGEventPointerOutput: PointerOutput {
    private var builder = PointerEventBuilder(source: CGEventSource(stateID: .hidSystemState))

    public init() {}

    /// `AXIsProcessTrusted` follows System Settings' Accessibility switch at once; `CGPreflightPostEventAccess` keeps
    /// the answer it gave at launch until the app restarts, so it alone left the pane saying "missing" after a grant.
    public func hasAccess() -> Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    public func requestAccess() -> Bool { hasAccess() || CGRequestPostEventAccess() }

    public func post(_ intents: [PointerIntent]) {
        for intent in intents {
            let cursor = CGEvent(source: nil)?.location ?? .zero
            // A keyboard's click key holding the button down turns a move into a drag too.
            let held = CGEventSource.buttonState(.hidSystemState, button: .left)
            for event in builder.events(for: intent, cursor: cursor, buttonHeld: held, clamp: DisplayBounds.clamp) {
                event.flags = CGEventSource.flagsState(.hidSystemState)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

/// Builds the Quartz events for each intent, carrying fractions of a point over to the next.
struct PointerEventBuilder {
    let source: CGEventSource?
    private var moveRemainder = (x: 0.0, y: 0.0)
    private var scrollRemainder = (x: 0.0, y: 0.0)

    init(source: CGEventSource?) { self.source = source }

    /// - Parameters:
    ///   - cursor: where the pointer is now.
    ///   - buttonHeld: the left button is down already (a keyboard's click key).
    ///   - clamp: keeps a new position on a display, given the old one.
    mutating func events(
        for intent: PointerIntent, cursor: CGPoint, buttonHeld: Bool, clamp: (CGPoint, CGPoint) -> CGPoint
    ) -> [CGEvent] {
        switch intent {
        case let .move(dx, dy, dragging):
            guard dx.isFinite, dy.isFinite else { return [] }
            moveRemainder.x += dx
            moveRemainder.y += dy
            let whole = (x: moveRemainder.x.rounded(.towardZero), y: moveRemainder.y.rounded(.towardZero))
            guard whole.x != 0 || whole.y != 0 else { return [] }
            moveRemainder.x -= whole.x
            moveRemainder.y -= whole.y
            let target = clamp(CGPoint(x: cursor.x + whole.x, y: cursor.y + whole.y), cursor)
            let event = CGEvent(
                mouseEventSource: source, mouseType: dragging || buttonHeld ? .leftMouseDragged : .mouseMoved,
                mouseCursorPosition: target, mouseButton: .left)
            event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(whole.x))
            event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(whole.y))
            return event.map { [$0] } ?? []
        case let .button(button, isDown, clickCount):
            let type: CGEventType =
                switch (button, isDown) {
                case (.left, true): .leftMouseDown
                case (.left, false): .leftMouseUp
                case (.right, true): .rightMouseDown
                case (.right, false): .rightMouseUp
                }
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: cursor, mouseButton: button == .left ? .left : .right)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            return event.map { [$0] } ?? []
        case let .scroll(dx, dy, phase, momentum):
            scrollRemainder.x += dx.isFinite ? dx : 0
            scrollRemainder.y += dy.isFinite ? dy : 0
            let whole = (x: scrollRemainder.x.rounded(.towardZero), y: scrollRemainder.y.rounded(.towardZero))
            scrollRemainder.x -= whole.x
            scrollRemainder.y -= whole.y
            if phase == .began || phase == .ended || momentum == .ended { scrollRemainder = (0, 0) }
            let event = CGEvent(
                scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(clamping: Int(whole.y)),
                wheel2: Int32(clamping: Int(whole.x)), wheel3: 0)
            event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: Self.value(of: phase))
            event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Self.value(of: momentum))
            return event.map { [$0] } ?? []
        }
    }

    /// `CGScrollPhase`: began 1, changed 2, ended 4.
    static func value(of phase: ScrollPhase) -> Int64 {
        switch phase {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 4
        }
    }

    /// `CGMomentumScrollPhase`: begin 1, continue 2, end 3.
    static func value(of phase: MomentumPhase) -> Int64 {
        switch phase {
        case .none: 0
        case .began: 1
        case .continued: 2
        case .ended: 3
        }
    }
}

/// Keeps the pointer on a display: a point off every display is held to the one the pointer was on.
enum DisplayBounds {
    static func clamp(_ point: CGPoint, from old: CGPoint) -> CGPoint {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success, count > 0 else { return point }
        let displays = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
        return clamp(point, from: old, to: displays)
    }

    static func clamp(_ point: CGPoint, from old: CGPoint, to displays: [CGRect]) -> CGPoint {
        guard !displays.contains(where: { $0.contains(point) }), let home = displays.first(where: { $0.contains(old) }) ?? displays.first
        else { return point }
        return CGPoint(x: min(max(point.x, home.minX), home.maxX - 1), y: min(max(point.y, home.minY), home.maxY - 1))
    }
}
