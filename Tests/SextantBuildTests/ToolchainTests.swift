import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// The shared build pipeline and output parsers, against fake command runners and Oryx's real build logs.
struct ToolchainTests {
    /// A runner that replays canned output and, like `qmk compile`, may leave an image in the QMK home.
    struct FakeRunner: CommandRunner {
        var output: [CommandOutput]
        var image: (URL, Data)?
        var fails = false
        let commands = Commands()

        final class Commands: @unchecked Sendable {
            var all: [BuildCommand] = []
        }

        func run(_ command: BuildCommand) -> AsyncThrowingStream<CommandOutput, any Error> {
            commands.all.append(command)
            if let (url, data) = image { try? data.write(to: url) }
            return AsyncThrowingStream { continuation in
                output.forEach { continuation.yield($0) }
                continuation.finish(throwing: fails ? CocoaError(.executableNotLoadable) : nil)
            }
        }
    }

    let home = FileManager.default.temporaryDirectory.appending(path: "sextant-toolchain-\(UUID().uuidString)", directoryHint: .isDirectory)
    let board = BoardDefinition.voyager
    let source = GeneratedSource(
        files: ["keymap.c": "// keymap\n", "rules.mk": "", "config.h": "", "keymap.json": "{}"],
        sourceMap: [21: KeyRef(layer: 1, index: 4, slot: .tap)])
    var imageURL: URL { home.appending(path: "zsa_voyager_sextant.bin") }

    func events(_ runner: FakeRunner) async -> [BuildEvent] {
        var out: [BuildEvent] = []
        for await e in QMKBuild(hostHome: home, commandHome: "/qmk", runner: runner).run(source, board: board) { out.append(e) }
        return out
    }

    @Test(arguments: [
        ("KlgM7-40xJ7M-source.zip", 65786), ("JRGQm-source.zip", 75512), ("e5Rrr-source.zip", 67326),
        ("m9dpx-source.zip", 70222), ("XlrR4-source.zip", 44504),
    ])
    func readsOryxBuildLogs(zip: String, size: Int) throws {
        let text = try QMKGeneratorGoldenTests.unzipped(QMKGeneratorGoldenTests.examples.appending(path: "sources/\(zip)")) {
            try String(contentsOf: $0.appending(path: "build.log"), encoding: .utf8)
        }
        var log = BuildLog(sourceMap: [:])
        let events = text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { log.consume(String($0)) }
        #expect(log.usedBytes == size)
        #expect(log.lines.allSatisfy { !$0.contains("\u{1B}") }, "colour codes are stripped")
        let compiling = events.compactMap { if case let .compiling(file, done, total) = $0 { (file, done, total) } else { nil } }
        #expect(compiling.count == text.components(separatedBy: "Compiling:").count - 1)
        #expect(compiling.allSatisfy { !$0.0.contains("/") && $0.1 <= $0.2 })
        #expect(events.contains(.linking))
        #expect(log.diagnostics.isEmpty && log.overflow == nil)
    }

    @Test func parsesDiagnosticsAndMapsKeymapLinesToKeys() {
        let map = [21: KeyRef(layer: 1, index: 4, slot: .tap)]
        let error = BuildLog.diagnostic(
            "keyboards/zsa/voyager/keymaps/sextant/keymap.c:21:5: error: 'KC_FOO' undeclared here (not in a function)", sourceMap: map)
        #expect(
            error
                == Diagnostic(
                    file: "keyboards/zsa/voyager/keymaps/sextant/keymap.c", line: 21, column: 5, severity: .error,
                    message: "'KC_FOO' undeclared here (not in a function)", key: KeyRef(layer: 1, index: 4, slot: .tap)))
        #expect(BuildLog.diagnostic("quantum/action.c:21:1: warning: unused", sourceMap: map)?.key == nil)
        #expect(BuildLog.diagnostic("x.c:3:9: fatal error: y.h: No such file", sourceMap: map)?.severity == .error)
        #expect(BuildLog.diagnostic("Compiling: keymap.c [OK]", sourceMap: map) == nil)
    }

    @Test func buildsWritesTheKeymapAndReturnsTheImage() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let image = FirmwareImage.withSuffix(Data(repeating: 1, count: 1000), vendorID: 0x3297, productID: 0x0791).data
        let runner = FakeRunner(
            output: [
                .line("\u{1B}[32mCompiling: keyboards/zsa/voyager/keymaps/sextant/keymap.c\u{1B}[0m [OK]"), .line("Linking: x.elf"),
                .line("Size after:"), .line("   text\t   data\t    bss\t    dec\t    hex\tfilename"),
                .line("      0\t   1000\t      0\t   1000\t    3e8\tzsa_voyager_sextant.bin"), .exit(0),
            ],
            image: (imageURL, image))
        let events = await events(runner)
        #expect(events.first == .output("Compiling: keyboards/zsa/voyager/keymaps/sextant/keymap.c [OK]"))
        #expect(events.contains(.compiling(file: "keymap.c", done: 1, total: BuildLog.expectedUnits)))
        guard case let .finished(artifact)? = events.last else { Issue.record("no artifact: \(events)"); return }
        #expect(artifact.image == image && artifact.usedBytes == 1000 && artifact.log.count == 5)
        let keymap = home.appending(path: "keyboards/zsa/voyager/keymaps/sextant/keymap.c")
        #expect(try String(contentsOf: keymap, encoding: .utf8) == "// keymap\n")
        #expect(
            runner.commands.all == [
                BuildCommand(
                    arguments: ["qmk", "compile", "-j", "8", "-kb", "zsa/voyager", "-km", "sextant"],
                    environment: ["QMK_HOME": "/qmk", "SKIP_GIT": "yes"], workingDirectory: "/qmk")
            ])
    }

    @Test func compileErrorsComeBackMappedToKeys() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let events = await events(
            FakeRunner(output: [.line("keyboards/zsa/voyager/keymaps/sextant/keymap.c:21:5: error: 'KC_FOO' undeclared"), .exit(2)]))
        guard case let .failed(.compileFailed(diagnostics))? = events.last else { Issue.record("\(events)"); return }
        #expect(diagnostics.map(\.key) == [KeyRef(layer: 1, index: 4, slot: .tap)])
    }

    @Test func tooLargeImagesFail() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let overflow = await events(FakeRunner(output: [.line("ld: region `flash0' overflowed by 1234 bytes"), .exit(2)]))
        #expect(overflow.last == .failed(.tooLarge(overBy: 1234)))
        let window = Int(board.flashEnd - board.flashStart)
        let big = await events(FakeRunner(output: [.exit(0)], image: (imageURL, Data(count: window + 16 + 5))))
        #expect(big.last == .failed(.tooLarge(overBy: 5)))
    }

    @Test func aMissingToolOrImageFails() async {
        defer { try? FileManager.default.removeItem(at: home) }
        guard case .failed(.notInstalled)? = await events(FakeRunner(output: [], fails: true)).last else {
            Issue.record("expected notInstalled")
            return
        }
        guard case .failed(.failed)? = await events(FakeRunner(output: [.exit(0)])).last else {
            Issue.record("expected a failure without an image")
            return
        }
    }

    @Test func statusNeedsSetupUntilTheToolsArePresent() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let container = ContainerToolchain(home: .init(root: home), runner: FakeRunner(output: []))
        let native = NativeToolchain(home: home, runner: FakeRunner(output: []))
        guard case .needsSetup = await container.status(), case .needsSetup = await native.status() else {
            Issue.record("an empty home must need setup")
            return
        }
        for (file, text) in [
            ("vmlinux", ""), ("initfs.ext4", ""), ("rootfs.ext4", ""),
            ("qmk_firmware/.git/HEAD", ContainerToolchain.Pins.firmwareCommit + "\n"),
            ("qmk_firmware/.git/modules/modules/zsa/HEAD", ContainerToolchain.Pins.modulesCommit + "\n"),
        ] {
            let url = home.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        guard case .ready = await container.status() else {
            Issue.record("the container toolchain should be ready")
            return
        }
    }

    @Test func lineWriterSplitsBytesIntoLines() throws {
        let lines = LockedLines()
        let writer = LineWriter { lines.append($0) }
        try writer.write(Data("one\ntw".utf8))
        try writer.write(Data("o\nthree".utf8))
        try writer.close()
        #expect(lines.all == ["one", "two", "three"])
    }

    final class LockedLines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        var all: [String] { lock.withLock { lines } }
        func append(_ line: String) { lock.withLock { lines.append(line) } }
    }
}
