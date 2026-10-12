import Foundation
import Observation
import SextantDomain
import os

/// Why Build & Flash stopped (spec §7.3, §7.4).
public enum BuildFlashError: Error, Equatable, Sendable, LocalizedError {
    case generator(GeneratorError)
    /// Compile errors (with their keys), too large, or a toolchain failure.
    case toolchain(ToolchainError)
    /// The build tools' one-time setup didn't finish (spec §7.3).
    case setup(ToolchainError)
    case multipleBootloaders
    /// Includes `.imageRejected`: the image failed validation for the connected bootloader, with no override.
    case flash(FlashError)
    /// The keyboard didn't come back within 10 s of flashing.
    case notReconnected
    /// The keyboard came back reporting another serial than the build's.
    case unexpectedSerial(String?)
    /// Another layout's Build & Flash holds flash mode (spec §7.6).
    case flashingElsewhere

    public var errorDescription: String? {
        switch self {
        case let .generator(e): e.localizedDescription
        case let .toolchain(e): e.localizedDescription
        // The detail alone: the toolchain's own wording says the build didn't finish.
        case let .setup(.failed(detail)): detail
        case let .setup(e): e.localizedDescription
        case .multipleBootloaders: String(localized: "Connect only one keyboard in flash mode.")
        case let .flash(e): e.localizedDescription
        case .notReconnected:
            String(localized: "The keyboard didn't reconnect after flashing. Unplug it and plug it back in to check it.")
        case let .unexpectedSerial(serial?):
            String(localized: "The keyboard reconnected as \(serial), not the new firmware. Put it in flash mode to try again.")
        case .unexpectedSerial(nil):
            String(localized: "The keyboard reconnected without a serial. Put it in flash mode to try again.")
        case .flashingElsewhere: String(localized: "Another window is flashing the keyboard. Try again when it finishes.")
        }
    }
}

/// Build & Flash for one open layout (spec §7): the live-issue gate, generate, compile, size, wait for flash
/// mode, validate, write, verify the keyboard's serial, and record a flash revision.
///
/// Writing starts only when exactly one bootloader of the board appears and the image passes validation;
/// there is no "Flash Now". ``stop()`` works while building or waiting and is refused from validation on.
/// Call ``stop()`` when the document closes: a waiting run has no time limit and would flash the next keyboard
/// put in flash mode.
@MainActor
@Observable
public final class BuildFlashSession {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Live issues with error severity block the build (§7.5).
        case blocked([LayoutIssue])
        /// The connected keyboard runs another layout, or firmware with no serial: ``confirmReplace()`` or ``stop()``.
        case confirmingReplace(serial: String?, title: String?)
        /// The toolchain needs its one-time setup (§7.3 "Set up the build tools"): ``setUpBuildTools()`` or ``stop()``.
        case needsSetup(String)
        /// Downloading (`received` of `total` bytes), then installing (`received == total`); the build follows.
        case settingUp(received: Int64, total: Int64)
        case generating
        case compiling(file: String, done: Int, total: Int)
        case linking
        /// Built only (⌘B): ``artifact`` and ``usedBytes`` describe it; ``flash(connectedKeyboard:)`` continues.
        case built
        case waitingForFlashMode(stillWaiting: Bool)
        case validating
        case erasing(done: Int, total: Int)
        case writing(done: Int, total: Int)
        /// Waiting for the keyboard to come back with the build's serial.
        case verifying
        /// Flashed. `saveError` is set when the flash revision couldn't be recorded.
        case done(revision: RevisionSummary?, saveError: LibraryError?)
        case failed(BuildFlashError)
    }

    public private(set) var phase = Phase.idle
    /// The build's output lines.
    public private(set) var log: [String] = []
    /// The last successful build.
    public private(set) var artifact: BuildArtifact?
    /// The serial the last build reports (``FirmwareIdentity``).
    public private(set) var identity: FirmwareIdentity?

    /// Payload bytes of the last build.
    public var usedBytes: Int? { artifact.map { $0.usedBytes ?? max(0, $0.image.count - 16) } }
    /// The board's application flash (the linker's window, not the wider DFU guard window), in bytes.
    public var capacity: Int { Int(board.applicationEnd - board.flashStart) }
    /// The failed build's compiler diagnostics, each with its key when the source map knows it (§7.5).
    public var diagnostics: [Diagnostic] {
        if case let .failed(.toolchain(.compileFailed(d))) = phase { d } else { [] }
    }
    public var canStop: Bool {
        switch phase {
        case .validating, .erasing, .writing, .verifying: false
        default: true
        }
    }

    private enum Request { case build, buildAndFlash, flash }
    private enum Input: Sendable {
        case device(DeviceEvent)
        case settled(Int), stillWaiting, verifyTimeout
    }

    /// How long the set of bootloaders must stay unchanged before Sextant picks one (devices already present
    /// arrive one by one).
    private static let settle = Duration.milliseconds(250)

    @ObservationIgnored private let session: EditSession
    @ObservationIgnored private let library: any LayoutLibrary
    @ObservationIgnored private let generator: any FirmwareGenerator
    @ObservationIgnored private let toolchain: any Toolchain
    @ObservationIgnored private let watcher: any DeviceWatcher
    @ObservationIgnored private let flasher: any Flasher
    @ObservationIgnored private let md5: @Sendable (Data) -> String
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let issues: @Sendable (KeyboardLayout) -> [LayoutIssue]
    @ObservationIgnored private let board: BoardDefinition
    @ObservationIgnored private let live: LiveSession?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runID = 0
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private var builtLayout: KeyboardLayout?
    @ObservationIgnored private var imageMD5 = ""
    @ObservationIgnored private let logger = Logger(subsystem: "com.sextant.app", category: "application")

    /// - Parameters:
    ///   - md5: hex md5 of an image, recorded at build time for the flasher's check (ADR 0013).
    ///   - issues: the live-issue check (the domain's, unless a test injects one).
    ///   - live: the app-wide live session, which lets one Build & Flash at a time wait for flash mode and write.
    public init(
        session: EditSession, library: any LayoutLibrary, generator: any FirmwareGenerator, toolchain: any Toolchain,
        watcher: any DeviceWatcher, flasher: any Flasher, md5: @escaping @Sendable (Data) -> String,
        clock: any Clock<Duration> = ContinuousClock(),
        issues: @escaping @Sendable (KeyboardLayout) -> [LayoutIssue] = LayoutIssues.check, live: LiveSession? = nil
    ) {
        self.session = session
        self.library = library
        self.generator = generator
        self.toolchain = toolchain
        self.watcher = watcher
        self.flasher = flasher
        self.md5 = md5
        self.clock = clock
        self.issues = issues
        self.live = live
        board = session.layout.board ?? .voyager
    }

    // MARK: Actions

    /// Build & Flash (⌘R). `connectedKeyboard` is the keyboard in normal mode, if any, for the replace check.
    public func buildAndFlash(connectedKeyboard: KeyboardDevice?) { begin(.buildAndFlash, keyboard: connectedKeyboard) }

    /// Build only (⌘B).
    public func build() { begin(.build, keyboard: nil) }

    /// Flashes the last build (the capsule's [Flash…] after ⌘B).
    public func flash(connectedKeyboard: KeyboardDevice?) {
        guard artifact != nil else { return }
        begin(.flash, keyboard: connectedKeyboard)
    }

    /// The layout of the open layout's latest import revision: what a build's identity, and so
    /// ``LiveSession/match(_:libraryID:importedLayout:)``, compares against (ADR 0019).
    public func importedLayout() async -> KeyboardLayout? {
        await FirmwareIdentity.importedLayout(of: session.id, revisions: session.revisions, library: library)
    }

    public func confirmReplace() {
        guard case .confirmingReplace = phase, let request else { return }
        begin(request, keyboard: nil, confirmed: true)
    }

    /// Download and Build: runs the toolchain's one-time setup, with the user's consent, then the build it held up.
    public func setUpBuildTools() {
        guard case .needsSetup = phase, task == nil, let request else { return }
        runID += 1
        let id = runID
        task = Task {
            var installed = false
            var failure: ToolchainError?
            for await event in toolchain.setUp() {
                guard !Task.isCancelled else { break }
                switch event {
                case let .downloading(received, total): show(.settingUp(received: received, total: total))
                case .installing:
                    if case let .settingUp(_, total) = phase { show(.settingUp(received: total, total: total)) }
                case .finished: installed = true
                case let .failed(error): failure = error
                }
            }
            guard runID == id else { return }
            // Free first: Try Again on the failure must find no run in progress.
            task = nil
            if let failure { return fail(.setup(failure)) }
            if installed, !Task.isCancelled { begin(request, keyboard: nil, confirmed: true) }
        }
    }

    /// Stop or Cancel: back to idle. Ignored from validation until the flash is verified.
    public func stop() {
        guard canStop else { return }
        task?.cancel()
        task = nil
        phase = .idle
    }

    /// Try Again: after a flash-side failure, waits for flash mode again with the same build; otherwise rebuilds.
    public func retry() {
        guard case .failed = phase, let request else { return }
        begin(artifact != nil && request != .build ? .flash : request, keyboard: nil, confirmed: true)
    }

    // MARK: Running

    private func begin(_ request: Request, keyboard: KeyboardDevice?, confirmed: Bool = false) {
        guard task == nil else { return }
        self.request = request
        runID += 1
        let id = runID
        task = Task {
            await run(request, keyboard: keyboard, confirmed: confirmed)
            if runID == id { task = nil }
        }
    }

    private func run(_ request: Request, keyboard: KeyboardDevice?, confirmed: Bool) async {
        let layout: KeyboardLayout
        let expected: FirmwareIdentity
        if request == .flash, let builtLayout, let identity {
            (layout, expected) = (builtLayout, identity)
        } else {
            layout = session.layout
            let errors = issues(layout).filter { $0.severity == .error }
            guard errors.isEmpty else { return show(.blocked(errors)) }
            expected = FirmwareIdentity(layout: layout, libraryID: session.id, importedLayout: await importedLayout())
        }
        if request != .build, !confirmed, let keyboard,
            (keyboard.serial.map {
                FirmwareMatch(serial: $0, expected: expected, libraryID: session.id, oryxLayoutID: layout.oryx?.layoutId)
            } ?? .otherLayout) == .otherLayout
        {
            return show(.confirmingReplace(serial: keyboard.serial, title: await title(runningSerial: keyboard.serial)))
        }
        guard !Task.isCancelled else { return }
        // The layout hasn't changed since the last build: use that build rather than compile it again.
        let reusable = artifact != nil && builtLayout == layout && identity == expected
        if request != .flash, !reusable {
            guard await build(layout, as: expected) else { return }
        }
        if request == .build { return show(.built) }
        // Never ask for flash mode when the write would be refused: the keyboard would sit in its bootloader for nothing.
        guard flasher.isEnabled else { return fail(.flash(.hardwareAccessOff)) }
        await flashAndVerify()
    }

    /// The library title of the layout a serial names, for the replace confirmation.
    private func title(runningSerial serial: String?) async -> String? {
        guard let serial else { return nil }
        let entries = (try? await library.entries()) ?? []
        return entries.first { $0.isOnKeyboard(serial: serial) }?.title
    }

    private func build(_ layout: KeyboardLayout, as identity: FirmwareIdentity) async -> Bool {
        (artifact, self.identity, builtLayout, log) = (nil, nil, nil, [])
        if case let .needsSetup(detail) = await toolchain.status() {
            show(.needsSetup(detail))
            return false
        }
        show(.generating)
        await session.flush()
        guard !Task.isCancelled else { return false }
        let source: GeneratedSource
        do {
            source = try generator.generate(layout, identity: identity)
        } catch {
            fail(.generator(error))
            return false
        }
        var result: BuildArtifact?
        for await event in toolchain.build(source, board: board) {
            switch event {
            case let .output(line): log.append(line)
            case let .compiling(file, done, total): show(.compiling(file: file, done: done, total: total))
            case .linking: show(.linking)
            case let .finished(built): result = built
            case let .failed(error):
                fail(.toolchain(Self.mapped(error, through: source.sourceMap)))
                return false
            }
        }
        guard !Task.isCancelled else { return false }
        guard let result else {
            fail(.toolchain(.failed(String(localized: "The build ended without firmware."))))
            return false
        }
        let used = result.usedBytes ?? max(0, result.image.count - 16)
        guard used <= capacity else {
            fail(.toolchain(.tooLarge(overBy: used - capacity)))
            return false
        }
        (artifact, self.identity, builtLayout, imageMD5) = (result, identity, layout, md5(result.image))
        return true
    }

    /// Points compile errors in `keymap.c` at the keys they came from.
    private static func mapped(_ error: ToolchainError, through sourceMap: [Int: KeyRef]) -> ToolchainError {
        guard case let .compileFailed(diagnostics) = error else { return error }
        return .compileFailed(
            diagnostics.map { d in
                var d = d
                if d.key == nil, d.file.split(separator: "/").last == "keymap.c" { d.key = sourceMap[d.line] }
                return d
            })
    }

    /// Waits for exactly one bootloader, writes the build to it, then waits up to 10 s for the keyboard to come
    /// back with the build's serial. Device events and timers arrive on one stream, so this reads top to bottom.
    private func flashAndVerify() async {
        guard let artifact, let identity, let builtLayout else { return }
        guard live?.claimFlashMode(for: session.id, owner: self) ?? true else { return fail(.flashingElsewhere) }
        defer { live?.releaseFlashMode(owner: self) }
        show(.waitingForFlashMode(stillWaiting: false))
        let (inputs, feed) = AsyncStream.makeStream(of: Input.self)
        let forward = Task { for await event in watcher.events(for: board) { feed.yield(.device(event)) } }
        defer { forward.cancel() }
        schedule(.stillWaiting, after: .seconds(45), feed)
        var bootloaders: [UInt64: BootloaderDevice] = [:]
        var settleID = 0
        var flashed = false
        for await input in inputs {
            // A stopped stream still hands over events it already holds: never act on one after Stop.
            guard !Task.isCancelled else { return }
            if flashed {
                switch input {
                case let .device(.attached(.keyboard(keyboard))):
                    guard keyboard.serial == identity.serial else { return fail(.unexpectedSerial(keyboard.serial)) }
                    return await record(builtLayout)
                case .verifyTimeout: return fail(.notReconnected)
                default: continue
                }
            }
            switch input {
            case let .device(.attached(.bootloader(device))):
                bootloaders[device.id] = device
            case let .device(.detached(id)):
                guard bootloaders.removeValue(forKey: id) != nil else { continue }
            case .stillWaiting:
                show(.waitingForFlashMode(stillWaiting: true))
                continue
            case let .settled(id) where id == settleID:
                if bootloaders.count > 1 { return fail(.multipleBootloaders) }
                guard let device = bootloaders.values.first else { continue }
                guard await write(artifact, to: device) else { return }
                flashed = true
                show(.verifying)
                schedule(.verifyTimeout, after: .seconds(10), feed)
                continue
            default: continue
            }
            settleID += 1
            if !bootloaders.isEmpty { schedule(.settled(settleID), after: Self.settle, feed) }
        }
    }

    private func schedule(_ input: Input, after delay: Duration, _ feed: AsyncStream<Input>.Continuation) {
        let clock = clock
        Task {
            do {
                try await clock.sleep(for: delay)
                feed.yield(input)
            } catch {}
        }
    }

    /// Validates the image for this bootloader, then writes it. Progress reaches the phase in order.
    private func write(_ artifact: BuildArtifact, to device: BootloaderDevice) async -> Bool {
        live?.isWritingFirmware = true
        defer { live?.isWritingFirmware = false }
        show(.validating)
        let image = FirmwareImage(data: artifact.image)
        do {
            try image.validate(forBootloaderPID: device.productID, board: board)
        } catch {
            fail(.flash(.imageRejected(error)))
            return false
        }
        logger.info("Flashing bootloader \(device.id, privacy: .public)")
        let (progress, report) = AsyncStream.makeStream(of: FlashProgress.self)
        let shown = Task {
            for await p in progress {
                switch p.phase {
                case .erasing: phase = .erasing(done: p.done, total: p.total)
                case .writing: phase = .writing(done: p.done, total: p.total)
                case .leaving: break
                }
            }
        }
        var failure: FlashError?
        do {
            try await flasher.flash(image, md5: imageMD5, to: device, board: board) { report.yield($0) }
        } catch {
            failure = error
        }
        report.finish()
        await shown.value
        if let failure {
            logger.error("Flashing failed: \(String(describing: failure), privacy: .public)")
            fail(.flash(failure))
            return false
        }
        return true
    }

    /// Records the flash as a revision of what is on the keyboard.
    private func record(_ built: KeyboardLayout) async {
        let message = String(localized: "Flashed \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        do {
            // Edited since the build: the revision must hold what was flashed, not the newer document, which stays edited.
            let revision =
                session.layout == built
                ? try await session.saveRevision(source: .flash, message: message)
                : try await session.recordRevision(RevisionDraft(source: .flash, message: message, layout: built))
            phase = .done(revision: revision, saveError: nil)
        } catch {
            logger.error("Recording the flash failed: \(String(describing: error), privacy: .public)")
            phase = .done(revision: nil, saveError: error)
        }
    }

    /// Sets the phase unless the run was stopped (a stopped run must not overwrite `.idle`).
    private func show(_ next: Phase) {
        guard !Task.isCancelled else { return }
        phase = next
    }

    private func fail(_ error: BuildFlashError) { show(.failed(error)) }
}
