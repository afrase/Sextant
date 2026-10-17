import Foundation
import SextantApplication
import SextantDomain
import Synchronization

/// Records the layout and identity it was asked to build; `keymap.c` line 31 maps to Brd+Sys key 45's tap. An identity
/// with a layout record also gets `sextant_layout.c`, as the real generator's does.
final class FakeGenerator: FirmwareGenerator {
    static let mappedLine = 31
    static let mappedKey = KeyRef(layer: 2, index: 45, slot: .tap)

    private let error: GeneratorError?
    private let identities = Mutex<[FirmwareIdentity]>([])
    private let layouts = Mutex<[KeyboardLayout]>([])

    init(error: GeneratorError? = nil) { self.error = error }

    var lastIdentity: FirmwareIdentity? { identities.withLock { $0.last } }
    var lastLayout: KeyboardLayout? { layouts.withLock { $0.last } }

    func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        identities.withLock { $0.append(identity) }
        layouts.withLock { $0.append(layout) }
        if let error { throw error }
        var files = ["keymap.c": "…"]
        if identity.record != nil { files["sextant_layout.c"] = "…" }
        return GeneratedSource(files: files, sourceMap: [Self.mappedLine: Self.mappedKey])
    }
}

/// Plays scripted build events; with `hangs`, never finishes (until the consumer stops). Setting up plays `setup`
/// (holding open unless it ends) and is ready afterwards when it ends with `.finished`. With `tooLargeWithRecord`, a
/// source that stores the layout (`sextant_layout.c`) fails as too large.
final class FakeToolchain: Toolchain {
    private let readiness: Mutex<ToolchainStatus>
    private let script: [BuildEvent]
    private let hangs: Bool
    private let tooLargeWithRecord: Bool
    private let setup: [SetupEvent]
    private let open = Mutex<[AsyncStream<BuildEvent>.Continuation]>([])
    private let settingUp = Mutex<[AsyncStream<SetupEvent>.Continuation]>([])

    init(
        readiness: ToolchainStatus = .ready("test"), script: [BuildEvent] = FakeToolchain.success(), hangs: Bool = false,
        tooLargeWithRecord: Bool = false, setup: [SetupEvent] = [.finished]
    ) {
        self.readiness = Mutex(readiness)
        self.script = script
        self.hangs = hangs
        self.tooLargeWithRecord = tooLargeWithRecord
        self.setup = setup
    }

    var buildCount: Int { open.withLock { $0.count } }
    var setupCount: Int { settingUp.withLock { $0.count } }

    func status() async -> ToolchainStatus { readiness.withLock { $0 } }

    func setUp() -> AsyncStream<SetupEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SetupEvent.self)
        settingUp.withLock { $0.append(continuation) }
        if setup.last == .finished { readiness.withLock { $0 = .ready("test") } }
        setup.forEach { continuation.yield($0) }
        if case .finished? = setup.last { continuation.finish() } else if case .failed? = setup.last { continuation.finish() }
        return stream
    }

    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BuildEvent.self)
        open.withLock { $0.append(continuation) }  // kept alive so a hanging build stays open
        if tooLargeWithRecord, source.files["sextant_layout.c"] != nil {
            [.output("Linking"), .failed(.tooLarge(overBy: 512))].forEach { continuation.yield($0) }
            continuation.finish()
            return stream
        }
        script.forEach { continuation.yield($0) }
        if !hangs { continuation.finish() }
        return stream
    }

    static func success(image: Data = Images.valid(), usedBytes: Int? = 65_786) -> [BuildEvent] {
        [
            .output("Compiling keymap.c"), .compiling(file: "keymap.c", done: 12, total: 41), .linking,
            .finished(BuildArtifact(image: image, usedBytes: usedBytes, log: [])),
        ]
    }
}

enum Images {
    /// A minimal image that passes validation for `productID`: stack in RAM, odd reset vector in the app area.
    static func valid(productID: UInt16 = 0x0791) -> Data {
        var payload = Data(count: 64)
        payload.replaceSubrange(0..<8, with: [0x00, 0x80, 0x00, 0x20, 0x01, 0x21, 0x00, 0x08])
        return FirmwareImage.withSuffix(payload, vendorID: 0x3297, productID: productID).data
    }
}
