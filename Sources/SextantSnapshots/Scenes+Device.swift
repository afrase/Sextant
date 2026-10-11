import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI
import Synchronization

// Device and Build & Flash scenes (spec §3.6, §7, §8.2): real LiveSession and BuildFlashSession state machines over
// scripted fakes, so every phase shown is one the use cases actually reach. Nothing here touches hardware.

extension Scenes {
    static func device(_ f: Fixtures) async -> [SnapshotScene] {
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent() else { return [] }
        var scenes: [SnapshotScene] = []
        let serial = "KlgM7/40xJ7M"
        let keyboard = ConnectedDevice.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: serial))
        let bootloader = ConnectedDevice.bootloader(BootloaderDevice(id: 9, productID: 0x0791, kind: .stm32, version: 0x0200))
        let live: [LiveEvent] = [.protocolVersion(5), .layer(0)]

        // The sidebar card in every state.
        var cards: [LayoutWindowModel] = []
        let states: [([ConnectedDevice], [LiveEvent])] = [
            ([], []),
            ([keyboard], [.protocolVersion(5), .layer(2)]),
            ([.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/0aB1cD"))], live),
            ([.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "Q9x2a/aa11"))], live),
            ([bootloader], []),
            ([keyboard], [.ended(.heldByAnotherApp)]),
            ([keyboard], [.ended(.hardwareAccessOff)]),
        ]
        for (devices, events) in states {
            cards.append(await deviceModel(f, root: root, devices: devices, live: events))
        }
        try? await Task.sleep(for: .milliseconds(400))
        scenes += SnapshotScene.pair("device-card", size: CGSize(width: 228, height: 900), chrome: .content) {
            VStack(spacing: 0) { ForEach(cards.indices, id: \.self) { DeviceCard(model: cards[$0]) } }.frame(width: 228)
        }

        // Following the keyboard on Brd+Sys with two keys down, the Device popover open from the capsule.
        let board = BoardDefinition.voyager
        let presses = [51, 13].map { LiveEvent.keyDown(row: board.keys[$0].matrixRow, column: board.keys[$0].matrixColumn) }
        let following = await deviceModel(f, root: root, devices: [keyboard], live: [.protocolVersion(5), .layer(2)] + presses)
        _ = await until {
            if case .onKeyboard = following.activity.status { following.session?.selection.layer == 2 } else { false }
        }
        scenes += SnapshotScene.pair(
            "window-live", size: full,
            overlays: [
                .popover(size: CGSize(width: 360, height: 0), anchor: CGRect(x: 560, y: 14, width: 150, height: 26)) {
                    DevicePopover(model: following)
                }
            ]
        ) { LayoutWindow(model: following, layoutID: .constant(f.entry.id)) }
        // The same at the honest minimum (spec §3.2): the card and the lane's live capsule must still fit.
        scenes.append(
            SnapshotScene("window-live-min-light", size: CGSize(width: 1120, height: 640)) {
                LayoutWindow(model: following, layoutID: .constant(f.entry.id))
            })

        // The Build & Flash sheet in the phases spec §7.3 describes.
        let image = validImage()
        let artifact = BuildEvent.finished(BuildArtifact(image: image, usedBytes: 65_786, log: []))
        let output: [BuildEvent] = [
            .output("Generating keymap.c, config.h, rules.mk"), .output("Compiling: keyboards/zsa/voyager/voyager.c"),
            .output("Compiling: quantum/keymap_introspection.c"), .output("Compiling: keyboards/zsa/voyager/keymaps/sextant/keymap.c"),
        ]
        let compileError = Diagnostic(
            file: "keyboards/zsa/voyager/keymaps/sextant/keymap.c", line: 31, column: 9, severity: .error,
            message: "'KC_LBRACKETT' undeclared here (not in a function); did you mean 'KC_LBRACKET'?")
        let writing = [FlashProgress(phase: .erasing, done: 33, total: 33), FlashProgress(phase: .writing, done: 41_984, total: 65_786)]
        // Name, build events (hanging or not), flash progress (a bootloader waits when there is some), and the serial
        // the keyboard comes back with (nil: the flash never ends). Each runs Build & Flash, except "built" (⌘B).
        let failure: [BuildEvent] = [.output("keymap.c:31:9: error: 'KC_LBRACKETT' undeclared"), .failed(.compileFailed([compileError]))]
        let runs: [(String, SceneToolchain, [FlashProgress], String?)] = [
            ("compiling", SceneToolchain(output + [.compiling(file: "keymap.c", done: 12, total: 41)], hangs: true), [], nil),
            ("built", SceneToolchain(output + [.linking, artifact]), [], nil),
            ("waiting", SceneToolchain(output + [artifact]), [], nil),
            ("writing", SceneToolchain(output + [artifact]), writing, nil),
            ("done", SceneToolchain(output + [artifact]), writing, serial),
            ("failed", SceneToolchain(output + failure), [], nil),
            ("setup", SceneToolchain([], setup: []), [], nil),
            ("downloading", SceneToolchain([], setup: [.downloading(received: 84_200_000, total: 190_400_000)]), [], nil),
        ]
        for (name, toolchain, progress, reconnect) in runs {
            let flashMode = SceneWatcher(progress.isEmpty ? [] : [bootloader])
            let model = await deviceModel(
                f, root: root, devices: name == "writing" ? [bootloader] : [keyboard], live: live, toolchain: toolchain,
                flashMode: flashMode,
                flasher: SceneFlasher(progress, reconnectAs: reconnect, watcher: flashMode))
            guard let build = model.buildFlash else { continue }
            if name == "built" { build.build() } else { build.buildAndFlash(connectedKeyboard: nil) }
            if name == "downloading", await until({ phase(build.phase, isNamed: "setup") }) { build.setUpBuildTools() }
            _ = await until { phase(build.phase, isNamed: name) }
            scenes += SnapshotScene.pair("buildflash-\(name)", size: full, overlays: [.sheet(width: 640) { BuildFlashSheet(model: model) }])
            {
                LayoutWindow(model: model, layoutID: .constant(f.entry.id))
            }
        }
        return scenes
    }

    /// A Build & Flash over fakes that is never started, so Build & Flash draws enabled in scenes that don't build.
    static func idleBuildFlash(_ model: LayoutWindowModel) async -> BuildFlashSession? {
        guard let session = model.session, let root = await model.library.location(of: session.id)?.deletingLastPathComponent() else {
            return nil
        }
        return BuildFlashSession(
            session: session, library: PackageLibrary(root: root), generator: SceneGenerator(), toolchain: SceneToolchain([]),
            watcher: SceneWatcher([]), flasher: SceneFlasher(), md5: { _ in "" })
    }

    /// A window model whose live session sees `devices` (each keyboard's link playing `live`) and whose Build & Flash
    /// runs the scripted toolchain, flash-mode watcher and flasher. It follows the keyboard from the start, so the
    /// state has settled before the window renders (the window's own loop starts only then).
    private static func deviceModel(
        _ f: Fixtures, root: URL, devices: [ConnectedDevice], live events: [LiveEvent], toolchain: SceneToolchain = SceneToolchain([]),
        flashMode: SceneWatcher = SceneWatcher([]), flasher: SceneFlasher = SceneFlasher()
    ) async -> LayoutWindowModel {
        let store = PackageLibrary(root: root)
        let live = LiveSession(watcher: SceneWatcher(devices), link: SceneLink(events: events), secureInputProbe: { false })
        live.start()
        let model = LayoutWindowModel(
            library: Library(store: store), live: live,
            makeBuildFlash: { session in
                BuildFlashSession(
                    session: session, library: store, generator: SceneGenerator(), toolchain: toolchain, watcher: flashMode,
                    flasher: flasher,
                    md5: { _ in "" })
            })
        await model.open(f.entry.id)
        Task { await model.followKeyboard() }
        return model
    }

    private static func phase(_ phase: BuildFlashSession.Phase, isNamed name: String) -> Bool {
        switch (phase, name) {
        case (.compiling, "compiling"), (.built, "built"), (.waitingForFlashMode, "waiting"), (.writing, "writing"), (.done, "done"),
            (.failed, "failed"), (.needsSetup, "setup"), (.settingUp, "downloading"):
            true
        default: false
        }
    }

    /// Polls `condition` for up to 5 s.
    private static func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<250 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    /// The smallest image that passes validation for an STM32 bootloader: stack in RAM, odd reset vector in the app area.
    private static func validImage() -> Data {
        var payload = Data(count: 64)
        payload.replaceSubrange(0..<8, with: [0x00, 0x80, 0x00, 0x20, 0x01, 0x21, 0x00, 0x08])
        return FirmwareImage.withSuffix(payload, vendorID: 0x3297, productID: 0x0791).data
    }
}

// MARK: - Fakes

/// Presence a scene sets up: devices present at subscription, plus ones attached later.
private final class SceneWatcher: DeviceWatcher {
    private let state: Mutex<(devices: [ConnectedDevice], subscribers: [AsyncStream<DeviceEvent>.Continuation])>

    init(_ devices: [ConnectedDevice]) { state = Mutex((devices, [])) }

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
        state.withLock { s in
            s.devices.forEach { continuation.yield(.attached($0)) }
            s.subscribers.append(continuation)
        }
        return stream
    }

    func attach(_ device: ConnectedDevice) {
        state.withLock { s in
            s.devices.append(device)
            s.subscribers.forEach { $0.yield(.attached(device)) }
        }
    }
}

/// Every link session plays `events`, staying open unless they end it.
private final class SceneLink: KeyboardLink {
    private let events: [LiveEvent]
    private let open = Mutex<[AsyncStream<LiveEvent>.Continuation]>([])

    init(events: [LiveEvent]) { self.events = events }

    func session(with device: KeyboardDevice, board: BoardDefinition) -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self)
        events.forEach { continuation.yield($0) }
        if case .ended = events.last { continuation.finish() } else { open.withLock { $0.append(continuation) } }
        return stream
    }
}

/// Maps `keymap.c` line 31 to Brd+Sys key 45's tap, like a real source map would.
private struct SceneGenerator: FirmwareGenerator {
    func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        GeneratedSource(files: [:], sourceMap: [31: KeyRef(layer: 2, index: 45, slot: .tap)])
    }
}

/// Plays scripted build events; with `hangs`, the build never ends. With `setup`, it needs setting up, and setting up
/// plays those events and never ends.
private final class SceneToolchain: Toolchain {
    private let script: [BuildEvent]
    private let hangs: Bool
    private let setup: [SetupEvent]?
    private let open = Mutex<[AsyncStream<BuildEvent>.Continuation]>([])
    private let settingUp = Mutex<[AsyncStream<SetupEvent>.Continuation]>([])

    init(_ script: [BuildEvent], hangs: Bool = false, setup: [SetupEvent]? = nil) {
        self.script = script
        self.hangs = hangs
        self.setup = setup
    }

    func status() async -> ToolchainStatus {
        setup == nil ? .ready("scene") : .needsSetup("Building firmware needs a one-time download of the build tools (about 190 MB).")
    }

    func setUp() -> AsyncStream<SetupEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SetupEvent.self)
        setup?.forEach { continuation.yield($0) }
        settingUp.withLock { $0.append(continuation) }
        return stream
    }

    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BuildEvent.self)
        script.forEach { continuation.yield($0) }
        if hangs { open.withLock { $0.append(continuation) } } else { continuation.finish() }
        return stream
    }
}

/// Reports scripted progress, then holds forever, or with `reconnectAs` finishes and brings the keyboard back with
/// that serial.
private struct SceneFlasher: Flasher {
    var progress: [FlashProgress] = []
    var reconnectAs: String?
    var watcher: SceneWatcher?

    init(_ progress: [FlashProgress] = [], reconnectAs: String? = nil, watcher: SceneWatcher? = nil) {
        self.progress = progress
        self.reconnectAs = reconnectAs
        self.watcher = watcher
    }

    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress report: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) {
        progress.forEach(report)
        guard let serial = reconnectAs, let watcher else {
            try? await Task.sleep(for: .seconds(86_400))
            return
        }
        // After the flash returns, so the session is already waiting for the keyboard.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            watcher.attach(.keyboard(KeyboardDevice(id: 2, productID: 0x1977, serial: serial)))
        }
    }
}
