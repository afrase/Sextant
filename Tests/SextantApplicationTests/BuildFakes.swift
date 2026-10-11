import Foundation
import SextantApplication
import SextantDomain
import Synchronization

/// Records the identity it was asked to build; `keymap.c` line 31 maps to Brd+Sys key 45's tap.
final class FakeGenerator: FirmwareGenerator {
    static let mappedLine = 31
    static let mappedKey = KeyRef(layer: 2, index: 45, slot: .tap)

    private let error: GeneratorError?
    private let identities = Mutex<[FirmwareIdentity]>([])

    init(error: GeneratorError? = nil) { self.error = error }

    var lastIdentity: FirmwareIdentity? { identities.withLock { $0.last } }

    func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        identities.withLock { $0.append(identity) }
        if let error { throw error }
        return GeneratedSource(files: ["keymap.c": "…"], sourceMap: [Self.mappedLine: Self.mappedKey])
    }
}

/// Plays scripted build events; with `hangs`, never finishes (until the consumer stops).
final class FakeToolchain: Toolchain {
    private let readiness: ToolchainStatus
    private let script: [BuildEvent]
    private let hangs: Bool
    private let open = Mutex<[AsyncStream<BuildEvent>.Continuation]>([])

    init(readiness: ToolchainStatus = .ready("test"), script: [BuildEvent] = FakeToolchain.success(), hangs: Bool = false) {
        self.readiness = readiness
        self.script = script
        self.hangs = hangs
    }

    var buildCount: Int { open.withLock { $0.count } }

    func status() async -> ToolchainStatus { readiness }

    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BuildEvent.self)
        open.withLock { $0.append(continuation) }  // kept alive so a hanging build stays open
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
