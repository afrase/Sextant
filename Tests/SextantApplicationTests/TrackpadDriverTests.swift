import Clocks
import Foundation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

/// Holds a call at a chosen moment until the test lets it go.
final class Gate: Sendable {
    private let state = Mutex((armed: false, waiting: [CheckedContinuation<Void, Never>]()))

    func arm() { state.withLock { $0.armed = true } }
    var isHolding: Bool { state.withLock { !$0.waiting.isEmpty } }

    /// Waits here if armed (once), until `open`.
    func pass() async {
        guard
            state.withLock({ s in
                defer { s.armed = false }
                return s.armed
            })
        else { return }
        await withCheckedContinuation { continuation in state.withLock { $0.waiting.append(continuation) } }
    }

    func open() {
        let waiting = state.withLock { s in
            defer { s.waiting = [] }
            return s.waiting
        }
        waiting.forEach { $0.resume() }
    }
}

/// A Navigator trackpad link with the real one's contract: pads attach and detach, frames arrive, every mode write is
/// recorded, a write needs an open session, and closing a session writes mouse mode to every pad it left in touchpad
/// mode.
final class FakeTrackpadLink: TrackpadLink {
    private struct State {
        var inputAccess = true
        var accessRequests = 0
        var present: [TrackpadID] = []
        var subscribers: [UUID: AsyncStream<TrackpadEvent>.Continuation] = [:]
        var writes: [(TrackpadInputMode, TrackpadID)] = []
        var failsWrites = false
        var inTouchpadMode: Set<TrackpadID> = []
    }
    private let state = Mutex(State())
    /// Holds the next mode write after recording it.
    let writeGate = Gate()

    var inputAccess: Bool {
        get { state.withLock { $0.inputAccess } }
        set { state.withLock { $0.inputAccess = newValue } }
    }
    var failsWrites: Bool {
        get { state.withLock { $0.failsWrites } }
        set { state.withLock { $0.failsWrites = newValue } }
    }
    var accessRequests: Int { state.withLock { $0.accessRequests } }
    var writes: [TrackpadInputMode] { state.withLock { $0.writes.map(\.0) } }
    var sessions: Int { state.withLock { $0.subscribers.count } }

    func hasInputAccess() async -> Bool { inputAccess }

    func requestInputAccess() async -> Bool {
        state.withLock {
            $0.accessRequests += 1
            return $0.inputAccess
        }
    }

    func session() -> AsyncStream<TrackpadEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TrackpadEvent.self)
        let id = UUID()
        state.withLock { s in
            s.present.forEach { continuation.yield(.attached($0)) }
            s.subscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { s in
                s.subscribers.removeValue(forKey: id)
                for pad in s.inTouchpadMode { s.writes.append((.mouse, pad)) }
                s.inTouchpadMode = []
            }
        }
        return stream
    }

    /// The session couldn't open the interface.
    func failSession(_ error: TrackpadError) {
        state.withLock { s in s.subscribers.values.forEach { $0.yield(.failed(error)) } }
    }

    func setInputMode(_ mode: TrackpadInputMode, on pad: TrackpadID) async throws(TrackpadError) {
        let open = state.withLock { !$0.subscribers.isEmpty && $0.present.contains(pad) }
        guard open else { throw .notAttached }
        let fails = state.withLock { s in
            s.writes.append((mode, pad))
            return s.failsWrites
        }
        await writeGate.pass()
        if fails { throw .io("write failed") }
        state.withLock { s in
            if mode == .touchpad { s.inTouchpadMode.insert(pad) } else { s.inTouchpadMode.remove(pad) }
        }
    }

    func attach(_ pad: TrackpadID = TrackpadID(7)) {
        state.withLock { s in
            s.present.append(pad)
            s.subscribers.values.forEach { $0.yield(.attached(pad)) }
        }
    }

    func detach(_ pad: TrackpadID = TrackpadID(7)) {
        state.withLock { s in
            s.present.removeAll { $0 == pad }
            s.subscribers.values.forEach { $0.yield(.detached(pad)) }
        }
    }

    func send(_ contacts: [TrackpadContact], scan: Int, from pad: TrackpadID = TrackpadID(7)) {
        state.withLock { s in
            s.subscribers.values.forEach { $0.yield(.frame(TrackpadFrame(contacts: contacts, scanTime: scan, timestamp: 0), from: pad)) }
        }
    }
}

/// Records what would be posted to the Mac.
final class FakePointerOutput: PointerOutput {
    private let state = Mutex((access: true, requests: 0, posted: [PointerIntent]()))
    /// Holds the next permission check.
    let accessGate = Gate()

    var access: Bool {
        get { state.withLock { $0.access } }
        set { state.withLock { $0.access = newValue } }
    }
    var requests: Int { state.withLock { $0.requests } }
    var posted: [PointerIntent] { state.withLock { $0.posted } }

    func hasAccess() async -> Bool {
        await accessGate.pass()
        return access
    }

    func requestAccess() async -> Bool {
        state.withLock {
            $0.requests += 1
            return $0.access
        }
    }

    func post(_ intents: [PointerIntent]) async { state.withLock { $0.posted += intents } }
}

struct FakeSystemPointer: SystemPointerSettings {
    var preferences = SystemPointerPreferences.standard
    func current() async -> SystemPointerPreferences { preferences }
}

/// Seconds on the test clock.
private final class TestTime: Sendable {
    let clock = TestClock()
    var now: @Sendable () -> Double {
        let start = clock.now
        return { [clock] in
            let elapsed = start.duration(to: clock.now).components
            return 100 + Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        }
    }
}

/// Every settings value the driver saved.
final class SavedSettings: Sendable {
    private let values = Mutex([TrackpadSettings]())
    var last: TrackpadSettings? { values.withLock { $0.last } }
    func append(_ settings: TrackpadSettings) { values.withLock { $0.append(settings) } }
}

@MainActor
struct TrackpadDriverTests {
    let link = FakeTrackpadLink()
    let output = FakePointerOutput()
    private let time = TestTime()
    let saved = SavedSettings()

    func driver(_ settings: TrackpadSettings = TrackpadSettings(isEnabled: true)) -> TrackpadDriver {
        TrackpadDriver(
            link: link, output: output, system: FakeSystemPointer(), clock: time.clock, now: time.now, settings: settings,
            save: { [saved] in saved.append($0) })
    }

    /// A one-finger tap: still for 7 reports, then a lift, a report every 6.5 ms on the test clock.
    func tap() async {
        for i in 0..<7 {
            link.send([TrackpadContact(id: 0, x: 1000, y: 1000)], scan: 1000 + i * 65)
            await time.clock.advance(by: .microseconds(6500))
        }
        link.send([], scan: 1000 + 7 * 65)
    }

    @Test func offOpensNothingAndWritesNothing() async {
        let driver = driver(TrackpadSettings())
        link.attach()
        await driver.start()
        #expect(driver.status == .off)
        #expect(link.sessions == 0)
        #expect(link.writes.isEmpty)
        #expect(link.accessRequests == 0 && output.requests == 0)
    }

    @Test func onSwitchesAnAttachedPadToTouchpadAndClicksATap() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { driver.status == .running })
        #expect(link.writes == [.touchpad])
        await tap()
        #expect(await eventually { output.posted.contains(.button(.left, isDown: true, clickCount: 1)) })
    }

    @Test func launchingWithoutPermissionsNeverPrompts() async {
        link.inputAccess = false
        let driver = driver()
        await driver.start()
        #expect(driver.status == .needsInputMonitoring)
        #expect(link.accessRequests == 0)
        #expect(link.sessions == 0)
    }

    @Test func withoutAccessibilityThePadStaysInMouseMode() async {
        output.access = false
        let driver = driver(TrackpadSettings())
        link.attach()
        await driver.setEnabled(true)
        #expect(driver.status == .needsAccessibility)
        #expect(output.requests == 1)
        #expect(link.writes.isEmpty)
        #expect(link.sessions == 0)
        // Granted later: the next refresh starts driving.
        output.access = true
        await driver.refresh()
        #expect(await eventually { driver.status == .running })
        #expect(link.writes == [.touchpad])
    }

    @Test func turningItOnAsksForInputMonitoringFirst() async {
        link.inputAccess = false
        let driver = driver(TrackpadSettings())
        await driver.setEnabled(true)
        #expect(driver.status == .needsInputMonitoring)
        #expect(link.accessRequests == 1)
        #expect(driver.settings.isEnabled)
        #expect(saved.last?.isEnabled == true)
    }

    @Test func turningItOffPutsThePadBackInMouseMode() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { link.writes == [.touchpad] })
        await driver.setEnabled(false)
        #expect(link.writes == [.touchpad, .mouse])
        #expect(driver.status == .off)
        #expect(await eventually { link.sessions == 0 })
    }

    @Test func losingAccessibilityStopsAndRestoresMouseMode() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { driver.status == .running })
        output.access = false
        await driver.refresh()
        #expect(driver.status == .needsAccessibility)
        #expect(link.writes == [.touchpad, .mouse])
    }

    @Test func aPadAttachedLaterIsSwitchedWhenItArrives() async {
        let driver = driver()
        await driver.start()
        #expect(driver.status == .waitingForTrackpad)
        #expect(link.writes.isEmpty)
        link.attach()
        #expect(await eventually { driver.status == .running })
        #expect(link.writes == [.touchpad])
        link.detach()
        #expect(await eventually { driver.status == .waitingForTrackpad })
    }

    @Test func wakingReassertsTouchpadMode() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { link.writes == [.touchpad] })
        await driver.systemDidWake()
        #expect(link.writes == [.touchpad, .touchpad])
    }

    @Test func quittingRestoresMouseMode() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { link.writes == [.touchpad] })
        await driver.shutDown()
        #expect(link.writes == [.touchpad, .mouse])
    }

    @Test func aFailedWriteIsReported() async {
        link.failsWrites = true
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { if case .failed = driver.status { true } else { false } })
    }

    @Test func settingsApplyToTheNextTouch() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { driver.status == .running })
        driver.update { $0.tapping.tapToClick = false }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(saved.last?.tapping.tapToClick == false)
        await tap()
        await time.clock.advance(by: .milliseconds(200))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!output.posted.contains { if case .button = $0 { true } else { false } })
    }

    @Test func updatesCantFlipTheSwitch() async {
        let driver = driver()
        driver.update { $0.isEnabled = false }
        #expect(driver.settings.isEnabled)
    }

    @Test func aDetachedPadLetsGoOfADrag() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { driver.status == .running })
        await tap()
        await time.clock.advance(by: .milliseconds(50))
        for i in 0..<30 {
            link.send([TrackpadContact(id: 0, x: 1000 + Double(i) * 20, y: 1000)], scan: 3000 + i * 65)
            await time.clock.advance(by: .microseconds(6500))
        }
        #expect(await eventually { output.posted.contains { if case .move(_, _, true) = $0 { true } else { false } } })
        link.detach()
        #expect(await eventually { output.posted.last == .button(.left, isDown: false, clickCount: 1) })
    }

    @Test func momentumGlidesOnTheClock() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { driver.status == .running })
        for i in 0..<25 {
            let y = 1400 - Double(i) * 40
            link.send([TrackpadContact(id: 0, x: 800, y: y), TrackpadContact(id: 1, x: 1800, y: y)], scan: 5000 + i * 65)
            await time.clock.advance(by: .microseconds(6500))
        }
        link.send([], scan: 5000 + 25 * 65)
        #expect(await eventually { output.posted.contains(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none)) })
        for _ in 0..<300 { await time.clock.advance(by: .milliseconds(8)) }
        #expect(
            await eventually {
                output.posted.contains { if case .scroll(_, _, .none, .ended) = $0 { true } else { false } }
            })
    }

    // MARK: Races the review found (2026-11-14)

    @Test func turningItOffDuringAStartLeavesItOff() async {
        let driver = driver()
        link.attach()
        output.accessGate.arm()
        let starting = Task { await driver.start() }
        #expect(await eventually { output.accessGate.isHolding })
        let stopping = Task { await driver.setEnabled(false) }
        output.accessGate.open()
        await starting.value
        await stopping.value
        #expect(driver.status == .off)
        #expect(!driver.settings.isEnabled)
        #expect(link.writes.last != .touchpad)
        #expect(await eventually { link.sessions == 0 })
    }

    @Test func quittingWhileAnAttachIsSwitchingRestoresMouseMode() async {
        let driver = driver()
        link.attach()
        link.writeGate.arm()
        await driver.start()
        #expect(await eventually { link.writeGate.isHolding })
        let quitting = Task { await driver.shutDown() }
        try? await Task.sleep(for: .milliseconds(20))
        link.writeGate.open()
        await quitting.value
        #expect(link.writes == [.touchpad, .mouse])
        #expect(await eventually { link.sessions == 0 })
    }

    @Test func aQuickOffAndOnEndsDriving() async {
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { driver.status == .running })
        link.writeGate.arm()
        let off = Task { await driver.setEnabled(false) }
        #expect(await eventually { link.writeGate.isHolding })
        let on = Task { await driver.setEnabled(true) }
        link.writeGate.open()
        await off.value
        await on.value
        #expect(driver.settings.isEnabled)
        #expect(await eventually { driver.status == .running })
        #expect(link.writes == [.touchpad, .mouse, .touchpad])
        #expect(link.sessions == 1)
        await driver.shutDown()
        #expect(link.writes.last == .mouse)
    }

    @Test func unpluggingAPadWhoseSwitchFailedClearsTheFailure() async {
        link.failsWrites = true
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { if case .failed = driver.status { true } else { false } })
        link.detach()
        #expect(await eventually { driver.status == .waitingForTrackpad })
    }

    @Test func aPadLeftInMouseModeIsNotDriven() async {
        link.failsWrites = true
        let driver = driver()
        link.attach()
        await driver.start()
        #expect(await eventually { if case .failed = driver.status { true } else { false } })
        await tap()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(output.posted.isEmpty)
    }

    @Test func aSessionThatCantOpenIsReported() async {
        let driver = driver()
        await driver.start()
        #expect(await eventually { link.sessions == 1 })
        link.failSession(.inputMonitoringDenied)
        #expect(await eventually { driver.status == .failed(.inputMonitoringDenied) })
        #expect(link.writes.isEmpty)
    }

    @Test func turningItOnAsksForBothPermissionsAtOnce() async {
        link.inputAccess = false
        output.access = false
        let driver = driver(TrackpadSettings())
        await driver.setEnabled(true)
        #expect(link.accessRequests == 1)
        #expect(output.requests == 1)
        #expect(driver.status == .needsInputMonitoring)
    }

    /// Launched with the switch already on: only checked, so Accessibility was never asked for and Sextant wasn't listed.
    @Test func checkingAgainAsksForWhatsMissing() async {
        output.access = false
        let driver = driver()
        await driver.start()
        #expect(driver.status == .needsAccessibility)
        #expect(output.requests == 0)
        await driver.requestPermissions()
        #expect(output.requests == 1)
    }

    @Test func resetPermissionsClearsThenAsksAgain() async {
        output.access = false
        let cleared = Mutex(0)
        let driver = TrackpadDriver(
            link: link, output: output, system: FakeSystemPointer(), clock: ImmediateClock(), now: { 0 },
            settings: TrackpadSettings(isEnabled: true), save: { _ in }, clearPermissions: { cleared.withLock { $0 += 1 } })
        await driver.start()
        #expect(driver.hasInputMonitoring && !driver.hasAccessibility)
        await driver.resetPermissions()
        #expect(cleared.withLock { $0 } == 1)
        #expect(output.requests == 1)
        #expect(link.accessRequests == 1)
    }
}
