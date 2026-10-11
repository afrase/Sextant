import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// The shared build pipeline and output parsers, against fake command runners and Oryx's real build logs.
struct ToolchainTests {
    /// A runner that replays canned output and, like `qmk compile`, may leave an image named for the keymap (the last
    /// argument) in the QMK home.
    struct FakeRunner: CommandRunner {
        var output: [CommandOutput]
        var image: (home: URL, data: Data)?
        var fails = false
        /// Runs before the output, while the build waits on the command.
        var during: @Sendable () async -> Void = {}
        let commands = Commands()

        final class Commands: @unchecked Sendable {
            var all: [BuildCommand] = []
            /// `keymap.c` as the command found it.
            var keymaps: [String] = []
        }

        func run(_ command: BuildCommand) -> AsyncThrowingStream<CommandOutput, any Error> {
            commands.all.append(command)
            if let (home, data) = image, let keymap = command.arguments.last {
                let source = home.appending(path: "keyboards/zsa/voyager/keymaps/\(keymap)/keymap.c")
                commands.keymaps.append((try? String(contentsOf: source, encoding: .utf8)) ?? "")
                try? data.write(to: home.appending(path: "zsa_voyager_\(keymap).bin"))
            }
            let (stream, continuation) = AsyncThrowingStream<CommandOutput, any Error>.makeStream()
            Task { [output, fails, during] in
                await during()
                output.forEach { continuation.yield($0) }
                continuation.finish(throwing: fails ? CocoaError(.executableNotLoadable) : nil)
            }
            return stream
        }
    }

    let home = FileManager.default.temporaryDirectory.appending(path: "sextant-toolchain-\(UUID().uuidString)", directoryHint: .isDirectory)
    let board = BoardDefinition.voyager
    let source = GeneratedSource(
        files: ["keymap.c": "// keymap\n", "rules.mk": "", "config.h": "", "keymap.json": "{}"],
        sourceMap: [21: KeyRef(layer: 1, index: 4, slot: .tap)])

    /// Runs a build against `runner`, in a QMK home that has the Voyager's keyboard folder unless `checkout` is false.
    func events(_ runner: FakeRunner, checkout: Bool = true) async -> [BuildEvent] {
        if checkout {
            try? FileManager.default.createDirectory(at: home.appending(path: "keyboards/zsa/voyager"), withIntermediateDirectories: true)
        }
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
        let payload = Data(repeating: 1, count: 1000)
        let runner = FakeRunner(
            output: [
                .line("\u{1B}[32mCompiling: keyboards/zsa/voyager/keymaps/sextant/keymap.c\u{1B}[0m [OK]"), .line("Linking: x.elf"),
                .line("Size after:"), .line("   text\t   data\t    bss\t    dec\t    hex\tfilename"),
                .line("      0\t   1000\t      0\t   1000\t    3e8\tzsa_voyager_sextant.bin"), .exit(0),
            ],
            image: (home, payload))
        let events = await events(runner)
        #expect(events.first == .output("Compiling: keyboards/zsa/voyager/keymaps/sextant/keymap.c [OK]"))
        #expect(events.contains(.compiling(file: "keymap.c", done: 1, total: BuildLog.expectedUnits)))
        guard case let .finished(artifact)? = events.last else { Issue.record("no artifact: \(events)"); return }
        // Sextant adds the DFU suffix itself; the flasher's checks accept it.
        #expect(artifact.image == FirmwareImage.withSuffix(payload, vendorID: 0x3297, productID: 0x0791).data)
        #expect(artifact.usedBytes == 1000 && artifact.log.count == 5)
        #expect(runner.commands.keymaps == ["// keymap\n"])
        let command = try #require(runner.commands.all.first)
        let keymap = try #require(command.arguments.last)
        #expect(keymap.wholeMatch(of: /sextant_[0-9a-f]{8}/) != nil)
        #expect(
            command
                == BuildCommand(
                    arguments: [
                        "qmk", "compile", "-j", "8", "-e", "BUILD_DIR=.build/\(keymap)", "-e", "DFU_SUFFIX=true", "-kb", "zsa/voyager",
                        "-km", keymap,
                    ],
                    environment: ["QMK_HOME": "/qmk", "SKIP_GIT": "yes"], workingDirectory: "/qmk"))
        // The keymap folder and image are gone, so builds don't pile up in the checkout.
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.path) == ["keyboards"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: home.appending(path: "keyboards/zsa/voyager/keymaps").path).isEmpty)
    }

    /// Two windows can build at once: each build must read back its own image, not the other's.
    @Test func overlappingBuildsKeepTheirOwnImages() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (firstRan, firstRanSignal) = AsyncStream<Void>.makeStream()
        let (secondRan, secondRanSignal) = AsyncStream<Void>.makeStream()
        let images = [1, 2].map { Data(repeating: UInt8($0), count: 100) }
        // The first command finishes only after the second has written its keymap and image.
        let first = FakeRunner(output: [.exit(0)], image: (home, images[0])) {
            firstRanSignal.yield()
            for await _ in secondRan { return }
        }
        let second = FakeRunner(output: [.exit(0)], image: (home, images[1])) { secondRanSignal.yield() }
        async let firstEvents = events(first)
        for await _ in firstRan { break }
        let secondEvents = await events(second)
        for (events, image) in [(await firstEvents, images[0]), (secondEvents, images[1])] {
            guard case let .finished(artifact)? = events.last else { Issue.record("no artifact: \(events)"); continue }
            #expect(artifact.image.prefix(100) == image)
        }
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
        // Running out of RAM isn't a flash-size problem.
        let ram = await events(FakeRunner(output: [.line("ld: region `ram0' overflowed by 99 bytes"), .exit(2)]))
        #expect(ram.last == .failed(.failed("ld: region `ram0' overflowed by 99 bytes")))
        let window = Int(board.applicationEnd - board.flashStart)
        let big = await events(FakeRunner(output: [.exit(0)], image: (home, Data(count: window + 5))))
        #expect(big.last == .failed(.tooLarge(overBy: 5)))
    }

    @Test func aMissingCheckoutToolOrImageFails() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner(output: [.exit(0)])
        guard case .failed(.notInstalled)? = await events(runner, checkout: false).last else {
            Issue.record("expected notInstalled without a checkout")
            return
        }
        #expect(runner.commands.all.isEmpty && !FileManager.default.fileExists(atPath: home.path), "nothing runs or is created")
        guard case .failed(.failed)? = await events(FakeRunner(output: [], fails: true)).last else {
            Issue.record("expected a failure when the command can't run")
            return
        }
        guard case .failed(.failed)? = await events(FakeRunner(output: [.exit(0)])).last else {
            Issue.record("expected a failure without an image")
            return
        }
    }

    /// The real process runner, on a harmless shell command: environment, merged stderr and the exit status.
    @Test func processRunnerStreamsOutputAndExitStatus() async throws {
        let command = BuildCommand(
            arguments: ["/bin/sh", "-c", "echo $X; echo err >&2; exit 3"], environment: ["X": "out"],
            workingDirectory: FileManager.default.temporaryDirectory.path)
        var output: [CommandOutput] = []
        for try await event in ProcessRunner().run(command) { output.append(event) }
        #expect(output == [.line("out"), .line("err"), .exit(3)])
    }
}
