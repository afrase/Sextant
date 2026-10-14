import Clocks
import Foundation
import SextantDomain
import Synchronization
import Testing

@testable import SextantApplication

/// App Layers (ADR 0054) on FakeFrontmostAppWatcher, FakeKeyboardLink, FakeDeviceWatcher and a test clock: nothing here
/// watches the real frontmost app or writes to a keyboard.
@MainActor
struct AppLayerSwitcherTests {
    let store = InMemoryLibrary()
    let watcher = FakeDeviceWatcher()
    let link = FakeKeyboardLink()
    let clock = TestClock()
    let apps = FakeFrontmostAppWatcher(frontmost: .finder)
    let live: LiveSession
    let library: Library
    let onKeyboard: OnKeyboard
    let switcher: AppLayerSwitcher

    init() {
        live = LiveSession(watcher: watcher, link: link, clock: clock) { false }
        library = Library(store: store)
        onKeyboard = OnKeyboard(library: library, store: store, live: live)
        switcher = AppLayerSwitcher(
            watcher: apps, onKeyboard: onKeyboard, live: live, store: store, ownBundleID: MacApp.sextant.bundleID, clock: clock,
            now: { Date(timeIntervalSince1970: 1_789_000_000) })
    }

    /// The user's layout (Main, Sym+Num, Brd+Sys) on a keyboard that runs it, with its rules: Xcode → Sym+Num and back to
    /// Main on leaving, Figma → Brd+Sys staying there.
    @discardableResult
    func knownKeyboard(rulesOn: Bool = true) async throws -> (LibraryEntry, KeyboardLayout) {
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let layout = try await store.load(entry.id).layout
        try await store.saveAppLayerRules(Self.rules(layout, on: rulesOn), for: entry.id)
        live.start()
        onKeyboard.start()
        switcher.start()
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { onKeyboard.running?.entry.id == entry.id && !switcher.rules(for: entry.id).rules.isEmpty })
        return (entry, layout)
    }

    static func rules(_ layout: KeyboardLayout, on: Bool = true) -> AppLayerRules {
        AppLayerRules(
            isOn: on,
            rules: [
                AppLayerRule(bundleID: MacApp.xcode.bundleID, name: "Xcode", layerID: layout.layers[1].id, leaving: .returnToMain),
                AppLayerRule(bundleID: MacApp.figma.bundleID, name: "Figma", layerID: layout.layers[2].id, leaving: .stay),
            ])
    }

    /// Turns Live View on and pairs its session, which reports `layer`.
    func goLive(layer: Int = 0) async -> Bool {
        live.startLive()
        guard await eventually({ link.sessionCount == 1 }) else { return false }
        return await report(layer: layer)
    }

    /// The keyboard reports `layer`, as it does after a move.
    func report(layer: Int) async -> Bool {
        link.send(.layer(layer))
        return await eventually {
            await clock.advance(by: .milliseconds(17))
            return live.canSend && live.activeLayer == layer
        }
    }

    /// Presses (or releases) one key on the keyboard.
    func hold(_ down: Bool) async -> Bool {
        link.send(down ? .keyDown(row: 2, column: 2) : .keyUp(row: 2, column: 2))
        return await eventually {
            await clock.advance(by: .milliseconds(17))
            return live.pressedKeys.isEmpty != down
        }
    }

    /// Brings `app` forward and lets it settle.
    func bring(_ app: MacApp) async -> Bool {
        apps.bring(app)
        return await eventually {
            await clock.advance(by: .milliseconds(50))
            return switcher.frontmost == app
        }
    }

    /// Lets queued commands reach the fake link.
    func sent() async -> [KeyboardCommand] {
        try? await Task.sleep(for: .milliseconds(20))
        return link.commands.flatMap { $0 }
    }

    // MARK: Switching

    @Test func anAppWithARuleMovesTheKeyboard() async throws {
        try await knownKeyboard()
        #expect(await goLive())
        #expect(await bring(.xcode))
        #expect(await eventually { link.commands == [[.moveToLayer(1)]] })
        #expect(switcher.history.map(\.app) == ["Xcode"])
        #expect(switcher.history.first?.layerName == "Sym+Num" && switcher.history.first?.left == nil)
    }

    @Test func leavingReturnsToMainOrStays() async throws {
        let (entry, _) = try await knownKeyboard()
        #expect(await goLive())
        #expect(await bring(.xcode))
        #expect(await report(layer: 1))
        #expect(switcher.applied(for: entry.id) == AppLayerSwitcher.Applied(app: "Xcode", layerName: "Sym+Num"))
        #expect(await bring(.safari))
        #expect(await eventually { link.commands == [[.moveToLayer(1), .moveToLayer(0)]] }, "Xcode returns to Main")
        #expect(switcher.history.first?.left == "Xcode" && switcher.history.first?.app == "Safari")
        #expect(await report(layer: 0))

        #expect(await bring(.figma))
        #expect(await report(layer: 2))
        #expect(await bring(.safari))
        #expect(await sent() == [.moveToLayer(1), .moveToLayer(0), .moveToLayer(2)], "Figma stays")
    }

    /// The layer the keyboard reports is its highest active one, which may be a held layer key's or a stale report.
    @Test func aMoveIsSentWhenTheKeyboardReportsTheLayerAlready() async throws {
        try await knownKeyboard()
        #expect(await goLive(layer: 1))
        #expect(await bring(.xcode))
        #expect(await eventually { link.commands == [[.moveToLayer(1)]] })
        #expect(switcher.history.map(\.app) == ["Xcode"])
    }

    /// A move under a held layer key would turn that layer off, and the key's release would drop to Main: App Layers waits
    /// for the keys to come up, then moves.
    @Test func aHeldKeyDelaysTheMoveUntilItIsUp() async throws {
        try await knownKeyboard()
        #expect(await goLive())
        #expect(await hold(true))
        #expect(await report(layer: 1), "the layer key holds Sym+Num")
        apps.bring(.xcode)
        await clock.advance(by: .seconds(1))
        #expect(await sent().isEmpty, "nothing while the key is down")
        #expect(await hold(false))
        #expect(await report(layer: 0), "its release drops to Main")
        #expect(await eventually { link.commands == [[.moveToLayer(1)]] }, "then Xcode's rule moves the keyboard")
        #expect(switcher.frontmost == .xcode)
    }

    /// A switch to another app while a key is held replaces the one waiting.
    @Test func aSwitchWhileAKeyIsHeldReplacesTheWaitingOne() async throws {
        try await knownKeyboard()
        #expect(await goLive())
        #expect(await hold(true))
        apps.bring(.xcode)
        await clock.advance(by: .seconds(1))
        apps.bring(.figma)
        await clock.advance(by: .seconds(1))
        #expect(await hold(false))
        #expect(await eventually { link.commands == [[.moveToLayer(2)]] })
        #expect(await sent() == [.moveToLayer(2)])
    }

    /// Sextant coming forward isn't a switch: reading its rules, or its menu bar panel, leaves the keyboard alone.
    @Test func sextantItselfIsIgnored() async throws {
        let (entry, _) = try await knownKeyboard()
        #expect(await goLive())
        #expect(await bring(.xcode))
        #expect(await report(layer: 1))
        apps.bring(.sextant)
        await clock.advance(by: .seconds(1))
        #expect(await sent() == [.moveToLayer(1)], "Xcode's Return to Main doesn't fire")
        #expect(switcher.frontmost == .xcode)
        #expect(switcher.applied(for: entry.id) == AppLayerSwitcher.Applied(app: "Xcode", layerName: "Sym+Num"))
        #expect(await bring(.safari))
        #expect(await eventually { link.commands == [[.moveToLayer(1), .moveToLayer(0)]] }, "leaving Xcode for Safari does")
    }

    @Test func onlyTheLatestActivationActs() async throws {
        try await knownKeyboard()
        #expect(await goLive())
        apps.bring(.xcode)
        apps.bring(.safari)
        #expect(await bring(.figma))
        #expect(await eventually { link.commands == [[.moveToLayer(2)]] })
        #expect(await sent() == [.moveToLayer(2)], "Xcode and Safari were in front too briefly")
    }

    /// The app in front at launch only sets where switching starts from; turning Live View or a rule on sends nothing
    /// until the next app switch.
    @Test func nothingIsSentAtLaunchOrWhenThingsTurnOn() async throws {
        apps.bring(.xcode)
        let (entry, layout) = try await knownKeyboard(rulesOn: false)
        #expect(switcher.frontmost == .xcode)
        #expect(await goLive())
        var rules = switcher.rules(for: entry.id)
        rules.isOn = true
        switcher.setRules(rules, for: entry.id)
        await clock.advance(by: .seconds(1))
        #expect(await sent().isEmpty)
        rules.rules.append(AppLayerRule(bundleID: MacApp.safari.bundleID, name: "Safari", layerID: layout.layers[2].id))
        switcher.setRules(rules, for: entry.id)
        #expect(await bring(.safari))
        #expect(await eventually { link.commands == [[.moveToLayer(2)]] }, "the next switch acts")
    }

    // MARK: Pauses

    @Test func theSwitchOffOrNoEnabledRuleSendsNothing() async throws {
        let (entry, layout) = try await knownKeyboard(rulesOn: false)
        #expect(await goLive())
        #expect(switcher.state(for: entry.id) == .off)
        #expect(await bring(.xcode))
        var rules = Self.rules(layout)
        rules.rules = rules.rules.map { $0.disabled }
        switcher.setRules(rules, for: entry.id)
        #expect(switcher.state(for: entry.id) == .off)
        #expect(await bring(.figma))
        #expect(await sent().isEmpty)
    }

    @Test func liveViewOffSendsNothingAndIsntReplayed() async throws {
        let (entry, _) = try await knownKeyboard()
        #expect(switcher.state(for: entry.id) == .paused(.refused(.liveOff)))
        #expect(await bring(.xcode))
        #expect(link.sessionCount == 0, "nothing paired")
        #expect(await goLive())
        await clock.advance(by: .seconds(1))
        #expect(await sent().isEmpty, "the switch made while it was off isn't replayed")
        #expect(switcher.state(for: entry.id) == .on)
    }

    @Test func connectingOrHeldByKeymappSendsNothing() async throws {
        let (entry, _) = try await knownKeyboard()
        live.startLive()
        #expect(await eventually { link.sessionCount == 1 })
        #expect(switcher.state(for: entry.id) == .paused(.refused(.connecting)))
        #expect(await bring(.xcode))
        link.send(.ended(.heldByAnotherApp))
        #expect(await eventually { switcher.state(for: entry.id) == .paused(.refused(.heldByAnotherApp)) })
        #expect(await bring(.figma))
        #expect(await sent().isEmpty)
    }

    @Test func flashModeSendsNothing() async throws {
        let (entry, _) = try await knownKeyboard()
        #expect(await goLive())
        watcher.detach(1)
        watcher.attach(.bootloader(.stm32()))
        #expect(await eventually { switcher.state(for: entry.id) == .paused(.refused(.flashMode)) })
        #expect(await bring(.xcode))
        #expect(await sent().isEmpty)
    }

    /// Another layout flashed: this layout's rules pause, and the keyboard's own layout's rules apply.
    @Test func anotherLayoutsRulesApplyWhileItIsFlashed() async throws {
        let (entry, layout) = try await knownKeyboard()
        var other = layout
        other.title = "Other"
        other.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        let otherEntry = try await store.create(other, origin: .local, firstRevision: nil)
        try await store.saveAppLayerRules(
            AppLayerRules(isOn: true, rules: [AppLayerRule(bundleID: MacApp.safari.bundleID, name: "Safari", layerID: other.layers[2].id)]),
            for: otherEntry.id)
        await library.refresh()
        let serial = FirmwareIdentity(layout: other, libraryID: otherEntry.id, importedLayout: nil).serial
        watcher.detach(1)
        watcher.attach(.keyboard(.voyager(id: 2, serial: serial)))
        #expect(await eventually { onKeyboard.running?.entry.id == otherEntry.id })
        #expect(await goLive())
        #expect(await eventually { switcher.rules(for: otherEntry.id).isActive })
        #expect(switcher.state(for: entry.id) == .paused(.otherLayout("Other", hasRules: true)))
        #expect(switcher.state(for: otherEntry.id) == .on)
        #expect(await bring(.xcode))
        #expect(await sent().isEmpty, "Xcode's rule belongs to the layout the keyboard doesn't run")
        #expect(await bring(.safari))
        #expect(await eventually { link.commands.last == [.moveToLayer(2)] })
        // With the keyboard layout's own rules off, none apply: the paused text mustn't say they do.
        var off = switcher.rules(for: otherEntry.id)
        off.isOn = false
        switcher.setRules(off, for: otherEntry.id)
        #expect(switcher.state(for: entry.id) == .paused(.otherLayout("Other", hasRules: false)))
        #expect(!AppLayersPause.otherLayout("Other", hasRules: false).text.contains("own rules apply"))
    }

    @Test func anUnknownLayoutSendsNothing() async throws {
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let layout = try await store.load(entry.id).layout
        try await store.saveAppLayerRules(Self.rules(layout), for: entry.id)
        live.start()
        onKeyboard.start()
        switcher.start()
        await switcher.load(entry.id)
        watcher.attach(.keyboard(.voyager(serial: "Q9x2/aa11")))
        #expect(await goLive())
        #expect(switcher.state(for: entry.id) == .paused(.refused(.unknownLayout)))
        #expect(await bring(.xcode))
        #expect(await sent().isEmpty, "not even layer 0, which such a keyboard has")
    }

    /// Every layer is checked against the layout as it was flashed: one added since isn't on the keyboard.
    @Test func aLayerNotOnTheKeyboardSendsNothing() async throws {
        let (entry, layout) = try await knownKeyboard()
        #expect(await goLive())
        var rules = Self.rules(layout)
        rules.rules.append(AppLayerRule(bundleID: MacApp.safari.bundleID, name: "Safari", layerID: "added-since-the-flash"))
        switcher.setRules(rules, for: entry.id)
        #expect(await bring(.safari))
        #expect(await sent().isEmpty)
    }

    // MARK: History

    @Test func theHistoryKeepsTwentyAppNamesInMemory() async throws {
        try await knownKeyboard()
        #expect(await goLive())
        for n in 0..<25 { #expect(await bring(n.isMultiple(of: 2) ? .xcode : .figma)) }
        #expect(await eventually { link.commands.first?.count == 25 })
        #expect(switcher.history.count == AppLayerSwitcher.historyLimit)
        #expect(switcher.history.first?.app == "Xcode" && switcher.history.first?.layerName == "Sym+Num", "newest first")
        #expect(switcher.history.map(\.id) == Array((6...25).reversed()))
        #expect(!String(describing: switcher.history).contains("com."), "app names only, no bundle ids")
    }

    // MARK: Rules

    @Test func rulesSaveInOrderAndAFailureIsReported() async throws {
        let (entry, layout) = try await knownKeyboard(rulesOn: false)
        let on = Self.rules(layout)
        switcher.setRules(on, for: entry.id)
        #expect(await eventually { (try? await store.appLayerRules(of: entry.id)) == on })
        await store.failAppLayersSaves(with: .io("disk full"))
        switcher.setRules(AppLayerRules(), for: entry.id)
        #expect(await eventually { switcher.saveError(for: entry.id) == .io("disk full") })
        #expect(switcher.rules(for: entry.id) == AppLayerRules(), "the change holds while Sextant runs")
        await store.failAppLayersSaves(with: nil)
        switcher.setRules(on, for: entry.id)
        #expect(await eventually { switcher.saveError(for: entry.id) == nil })
    }

    /// A switch turned off that didn't save would come back on at the next launch: the failure stays shown until Try
    /// Again writes the off, and another layout's save doesn't clear it.
    @Test func aFailedSwitchOffStaysShownUntilItSaves() async throws {
        let (entry, layout) = try await knownKeyboard()
        let other = try await store.create(layout, origin: .local, firstRevision: nil)
        await switcher.load(other.id)
        await store.failAppLayersSaves(with: .io("disk full"))
        var off = switcher.rules(for: entry.id)
        off.isOn = false
        switcher.setRules(off, for: entry.id)
        #expect(await eventually { switcher.saveError(for: entry.id) == .io("disk full") })
        #expect(switcher.state(for: entry.id) == .off, "off for the rest of this run")
        await store.failAppLayersSaves(with: nil)
        switcher.setRules(Self.rules(layout, on: false), for: other.id)
        #expect(await eventually { (try? await store.appLayerRules(of: other.id)) == Self.rules(layout, on: false) })
        #expect(switcher.saveError(for: entry.id) == .io("disk full"), "another layout's save doesn't clear it")
        #expect(try await store.appLayerRules(of: entry.id).isOn, "the file still says on")

        switcher.retrySave(for: entry.id)
        #expect(await eventually { switcher.saveError(for: entry.id) == nil })
        #expect(try await store.appLayerRules(of: entry.id) == off)
        let relaunched = AppLayerSwitcher(watcher: apps, onKeyboard: onKeyboard, live: live, store: store, clock: clock)
        await relaunched.load(entry.id)
        #expect(!relaunched.rules(for: entry.id).isOn)
    }

    @Test func unreadableRulesArentOverwritten() async throws {
        let failing = UnreadableRules()
        let switcher = AppLayerSwitcher(watcher: apps, onKeyboard: onKeyboard, live: live, store: failing, clock: clock)
        let id = UUID()
        await switcher.load(id)
        #expect(switcher.loadError(for: id) == .newerFormat(2))
        switcher.setRules(AppLayerRules(isOn: true), for: id)
        #expect(switcher.rules(for: id) == AppLayerRules())
    }

    /// A change made before the rules were read would replace the file with the empty set shown until then.
    @Test func editsWaitForTheRulesToLoad() async throws {
        let entry = try await library.importOryxJSON(Fixtures.userLayoutData)
        let layout = try await store.load(entry.id).layout
        try await store.saveAppLayerRules(Self.rules(layout), for: entry.id)
        switcher.setRules(AppLayerRules(isOn: true), for: entry.id)
        try await Task.sleep(for: .milliseconds(20))
        #expect(await store.appLayersSaves == 1, "only the test's own save")
        await switcher.load(entry.id)
        #expect(switcher.rules(for: entry.id) == Self.rules(layout))
    }

    @Test func runningAppsComeFromThePortWithoutSextant() async {
        apps.running = [.safari, .sextant, .xcode]
        var updates = switcher.runningApps().makeAsyncIterator()
        #expect(await updates.next() == [.safari, .xcode])
        apps.running = [.xcode]
        #expect(await updates.next() == [.xcode], "again as apps launch and quit")
        #expect(await switcher.app(at: URL(fileURLWithPath: "/Applications/Xcode.app")) == .xcode)
        #expect(await switcher.app(at: URL(fileURLWithPath: "/Applications/Sextant.app")) == nil)
    }
}

extension MacApp {
    static let finder = MacApp(bundleID: "com.apple.finder", name: "Finder")
    static let xcode = MacApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    static let safari = MacApp(bundleID: "com.apple.Safari", name: "Safari")
    static let figma = MacApp(bundleID: "com.figma.Desktop", name: "Figma")
    static let sextant = MacApp(bundleID: "com.sextant.app", name: "Sextant")
}

extension AppLayerRule {
    fileprivate var disabled: Self {
        var rule = self
        rule.isEnabled = false
        return rule
    }
}

/// The frontmost app as the test sets it: the current one first, then each one brought forward, to every subscriber.
final class FakeFrontmostAppWatcher: FrontmostAppWatcher {
    private struct State {
        var frontmost: MacApp
        var running: [MacApp] = []
        var subscribers: [UUID: AsyncStream<MacApp>.Continuation] = [:]
        var runningSubscribers: [UUID: AsyncStream<[MacApp]>.Continuation] = [:]
    }
    private let state: Mutex<State>

    init(frontmost: MacApp) { state = Mutex(State(frontmost: frontmost)) }

    /// The running apps; setting them tells every ``runningApps()`` subscriber.
    var running: [MacApp] {
        get { state.withLock { $0.running } }
        set {
            state.withLock { s in
                s.running = newValue
                s.runningSubscribers.values.forEach { $0.yield(newValue) }
            }
        }
    }

    func activations() -> AsyncStream<MacApp> {
        let (stream, continuation) = AsyncStream.makeStream(of: MacApp.self)
        let id = UUID()
        state.withLock { s in
            continuation.yield(s.frontmost)
            s.subscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) } }
        return stream
    }

    func bring(_ app: MacApp) {
        state.withLock { s in
            s.frontmost = app
            s.subscribers.values.forEach { $0.yield(app) }
        }
    }

    func runningApps() -> AsyncStream<[MacApp]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [MacApp].self)
        let id = UUID()
        state.withLock { s in
            continuation.yield(s.running)
            s.runningSubscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.runningSubscribers.removeValue(forKey: id) } }
        return stream
    }

    func app(at url: URL) -> MacApp? {
        switch url.lastPathComponent {
        case "Xcode.app": .xcode
        case "Sextant.app": .sextant
        default: nil
        }
    }
}

/// A library whose App Layers file is from a newer Sextant.
private actor UnreadableRules: LayoutLibrary {
    func entries() -> [LibraryEntry] { [] }
    func load(_ id: UUID) throws(LibraryError) -> StoredLayout { throw .notFound(id) }
    func create(_ layout: KeyboardLayout, origin: LayoutOrigin, firstRevision: RevisionDraft?) throws(LibraryError) -> LibraryEntry {
        throw .io("unused")
    }
    func save(_ layout: KeyboardLayout, to id: UUID) {}
    func appendRevision(_ draft: RevisionDraft, to id: UUID) throws(LibraryError) -> RevisionSummary { throw .io("unused") }
    func layout(ofRevision revisionID: String, in id: UUID) throws(LibraryError) -> KeyboardLayout { throw .notFound(id) }
    func rename(_ id: UUID, to title: String) {}
    func duplicate(_ id: UUID) throws(LibraryError) -> LibraryEntry { throw .notFound(id) }
    func trash(_ id: UUID) {}
    func storeFirmware(_ data: Data, md5: String, revisionID: String, to id: UUID) {}
    func firmware(revisionID: String, of id: UUID) -> (data: Data, md5: String)? { nil }
    func location(of id: UUID) -> URL? { nil }
    func saveRecovery(_ layout: KeyboardLayout, for id: UUID) {}
    func recovery(of id: UUID) -> KeyboardLayout? { nil }
    func discardRecovery(of id: UUID) {}
    func appLayerRules(of id: UUID) throws(LibraryError) -> AppLayerRules { throw .newerFormat(2) }
    func saveAppLayerRules(_ rules: AppLayerRules, for id: UUID) throws(LibraryError) { throw .io("must not be written") }
}
