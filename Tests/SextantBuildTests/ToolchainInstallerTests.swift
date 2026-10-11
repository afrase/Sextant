import CryptoKit
import Foundation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

@testable import SextantBuild

/// The setup step (ADR 0033) against a fake downloader and command runner, and the build sandbox against the real
/// `sandbox-exec`.
struct ToolchainInstallerTests {
    let home = FileManager.default.temporaryDirectory.appending(path: "sextant-setup-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// Serves canned bytes per URL and counts requests; `wait` holds every download until it is released.
    final class FakeDownloader: Downloading {
        let files: [URL: Data]
        let requests = Mutex(0)
        let gate: AsyncStream<Void>?

        init(_ files: [URL: Data], gate: AsyncStream<Void>? = nil) {
            self.files = files
            self.gate = gate
        }

        func download(_ artifact: Artifact, to file: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
            requests.withLock { $0 += 1 }
            if let gate { for await _ in gate { break } }
            let data = files[artifact.url] ?? Data()
            progress(Int64(data.count))
            try data.write(to: file)
        }
    }

    /// Records commands and exits with `status` (non-zero for any command containing `failing`).
    final class Runner: CommandRunner {
        let commands = Mutex<[[String]]>([])
        let failing: String?

        init(failing: String? = nil) { self.failing = failing }

        func run(_ command: BuildCommand) -> AsyncThrowingStream<CommandOutput, any Error> {
            commands.withLock { $0.append(command.arguments) }
            let code: Int32 = failing.map { f in command.arguments.contains { $0.contains(f) } } == true ? 1 : 0
            return AsyncThrowingStream {
                $0.yield(.exit(code)); $0.finish()
            }
        }
    }

    static func artifact(_ name: String, _ bytes: Data, unpack: [Unpack] = []) -> Artifact {
        Artifact(
            name: name, url: URL(filePath: "/downloads/\(name)"), size: Int64(bytes.count),
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), unpack: unpack)
    }

    let compiler = artifact("arm.tar.xz", Data("compiler".utf8), unpack: [Unpack(into: "arm", include: ["*/bin/*"], exclude: ["*gdb*"])])
    let wheel = artifact("qmk-1.2.0-py3-none-any.whl", Data("wheel".utf8))

    func installer(_ downloader: FakeDownloader, _ runner: Runner, artifacts: [Artifact]? = nil) -> ToolchainInstaller {
        ToolchainInstaller(home: home, downloader: downloader, runner: runner, artifacts: artifacts ?? [compiler, wheel])
    }

    func served() -> FakeDownloader {
        FakeDownloader([compiler.url: Data("compiler".utf8), wheel.url: Data("wheel".utf8)])
    }

    func events(_ installer: ToolchainInstaller) async -> [SetupEvent] {
        var out: [SetupEvent] = []
        for await event in installer.setUp() { out.append(event) }
        return out
    }

    @Test func installsVerifiedFilesAndMarksTheSetLast() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = Runner()
        let installer = installer(served(), runner)
        #expect(!installer.isInstalled)
        let events = await events(installer)
        #expect(events.first == .downloading(received: 0, total: 13) && events.contains(.installing) && events.last == .finished)
        #expect(installer.isInstalled)
        let downloads = home.appending(path: "downloads")
        #expect(
            runner.commands.withLock { $0 }
                == [
                    [
                        "/usr/bin/tar", "-x", "-f", downloads.appending(path: "arm.tar.xz").path, "-C", home.appending(path: "arm").path,
                        "--strip-components", "1", "--exclude", "*gdb*", "--include", "*/bin/*",
                    ],
                    [
                        home.appending(path: "python/bin/python3").path, "-m", "pip", "install", "--isolated", "--no-index", "--no-deps",
                        "--no-cache-dir", "--disable-pip-version-check", downloads.appending(path: wheel.name).path,
                    ],
                ])
        #expect(!FileManager.default.fileExists(atPath: downloads.path), "downloads go once installed")
    }

    /// A second window's Download and Build, or a stale one, finds the tools installed: nothing is cleared or fetched.
    @Test func anInstalledSetIsLeftAlone() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let downloader = served()
        let runner = Runner()
        #expect(await events(installer(downloader, runner)).last == .finished)
        let build = home.appending(path: "qmk_firmware/.build/sextant_1a2b3c4d.o")
        try FileManager.default.createDirectory(at: build.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("object".utf8).write(to: build)
        let commands = runner.commands.withLock { $0.count }
        #expect(await events(installer(downloader, runner)) == [.finished])
        #expect(downloader.requests.withLock { $0 } == 2 && runner.commands.withLock { $0.count } == commands)
        #expect(FileManager.default.fileExists(atPath: build.path), "a build in progress keeps its files")
    }

    /// A release that changes how an artifact unpacks reinstalls, though its pins are the same.
    @Test func theMarkerCoversHowArtifactsUnpack() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(await events(installer(served(), Runner())).last == .finished)
        var repacked = compiler
        repacked.unpack[0].include.append("*/lib/*")
        #expect(!installer(served(), Runner(), artifacts: [repacked, wheel]).isInstalled)
        #expect(installer(served(), Runner()).isInstalled)
    }

    @Test func refusesAFileThatDoesntMatchItsPin() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = Runner()
        let tampered = FakeDownloader([compiler.url: Data("compilex".utf8), wheel.url: Data("wheel".utf8)])
        let events = await events(installer(tampered, runner))
        guard case .failed(.failed)? = events.last else { Issue.record("expected a failure: \(events)"); return }
        #expect(runner.commands.withLock { $0 }.isEmpty, "nothing unverified is unpacked")
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "downloads/arm.tar.xz").path), "the bad file is deleted")
        #expect(!installer(tampered, runner).isInstalled)
    }

    @Test func aRetryKeepsVerifiedDownloads() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let downloader = served()
        let first = await events(installer(downloader, Runner(failing: "pip")))
        guard case .failed? = first.last else { Issue.record("pip should fail: \(first)"); return }
        #expect(!installer(downloader, Runner()).isInstalled, "no marker after a failed install")
        let second = await events(installer(downloader, Runner()))
        #expect(second.last == .finished)
        #expect(downloader.requests.withLock { $0 } == 2, "the retry downloads nothing again")
    }

    @Test func refusesUnpinnedArtifactsWithoutDownloading() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        var unpinned = compiler
        unpinned.sha256 = ""
        let downloader = served()
        let events = await events(installer(downloader, Runner(), artifacts: [unpinned]))
        guard case .failed? = events.last else { Issue.record("expected a refusal: \(events)"); return }
        #expect(downloader.requests.withLock { $0 } == 0)
    }

    @Test func oneSetupAtATime() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        let downloader = FakeDownloader([compiler.url: Data("compiler".utf8), wheel.url: Data("wheel".utf8)], gate: gate)
        let installer = installer(downloader, Runner())
        async let first = events(installer)
        while downloader.requests.withLock({ $0 }) == 0 { await Task.yield() }
        let second = await events(installer)
        guard case .failed(.failed)? = second.last else { Issue.record("a second setup must be refused: \(second)"); return }
        open.yield()
        open.yield()
        open.finish()
        #expect(await first.last == .finished)
    }

    @Test func thePinnedSetIsWellFormed() {
        let names = ToolchainPins.all.map(\.name)
        #expect(Set(names).count == names.count, "every download has its own file name")
        #expect(ToolchainPins.all.allSatisfy { $0.url.scheme == "https" })
        #expect(ToolchainPins.all.filter { !$0.isWheel }.allSatisfy { !$0.unpack.isEmpty })
        #expect(ToolchainPins.all.filter(\.isWheel).allSatisfy { $0.unpack.isEmpty })
        // Everything but the firmware archives, which get their hashes at the first approved download.
        let pinned = ToolchainPins.tools + ToolchainPins.wheels
        #expect(pinned.allSatisfy { $0.sha256.wholeMatch(of: /[0-9a-f]{64}/) != nil && $0.size > 0 })
    }

    /// Builds run `qmk` from the toolchain under `sandbox-exec`, with only the toolchain's tools on `PATH`.
    @Test func buildsRunSandboxedWithTheToolchainsTools() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let firmware = home.appending(path: "qmk_firmware")
        try FileManager.default.createDirectory(at: firmware.appending(path: "keyboards/zsa/voyager"), withIntermediateDirectories: true)
        let runner = ToolchainTests.FakeRunner(output: [.exit(0)], image: (firmware, Data(count: 64)))
        let toolchain = NativeToolchain(installer: installer(served(), Runner()), runner: runner)
        let source = GeneratedSource(files: ["keymap.c": ""], sourceMap: [:])
        for await _ in toolchain.build(source, board: .voyager) {}
        let command = try #require(runner.commands.all.first)
        #expect(Array(command.arguments.prefix(2)) == ["/usr/bin/sandbox-exec", "-p"])
        #expect(command.arguments[2].contains("(deny network*)"))
        #expect(command.arguments[3] == home.appending(path: "python/bin/qmk").path && command.arguments[4] == "compile")
        let path = try #require(command.environment["PATH"]).split(separator: ":").map(String.init)
        #expect(path.prefix(3) == ["arm/bin", "make/bin", "python/bin"].map { home.appending(path: $0).path }[...])
        #expect(command.environment["HOME"] == home.appending(path: "tmp").path && command.workingDirectory == firmware.path)
    }

    /// The build sandbox, enforced by the real `sandbox-exec`: no reads in the home folder outside the toolchain, no
    /// writes outside the build's folders and image, and no Mach services (the pasteboard, LaunchServices).
    @Test func theSandboxKeepsBuildsToTheirFolders() async throws {
        let root = home.appending(path: "user", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let toolchain = root.appending(path: "Library/Caches/Toolchain", directoryHint: .isDirectory)
        let build = toolchain.appending(path: "qmk_firmware/.build", directoryHint: .isDirectory)
        for folder in [build, toolchain.appending(path: "tmp")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("secret".utf8).write(to: root.appending(path: "secret.txt"))
        try Data("tool".utf8).write(to: toolchain.appending(path: "readable.txt"))
        let sandbox = Sandbox(
            readable: toolchain, writable: [build, toolchain.appending(path: "tmp")], images: toolchain.appending(path: "qmk_firmware"),
            home: root)

        func exit(_ script: String) async throws -> Int32 {
            let command = BuildCommand(
                arguments: sandbox.command + ["/bin/sh", "-c", script], environment: ["PATH": "/usr/bin:/bin"],
                workingDirectory: home.path)
            var status: Int32 = -1
            for try await case let .exit(code) in ProcessRunner().run(command) { status = code }
            return status
        }
        #expect(try await exit("cat '\(toolchain.path)/readable.txt'") == 0)
        #expect(try await exit("cat '\(root.path)/secret.txt'") != 0, "the user's files can't be read")
        #expect(try await exit("stat '\(root.path)/secret.txt'") != 0, "nor even seen")
        #expect(try await exit("/bin/realpath '\(toolchain.path)'") == 0, "the way to the toolchain resolves")
        // Without Mach services `open` can't launch anything outside the sandbox; the pasteboard is the harmless probe.
        #expect(try await exit("/usr/bin/pbpaste") != 0, "no Mach services")
        #expect(try await exit("echo x > '\(build.path)/out.o'") == 0)
        #expect(try await exit("echo x > '\(toolchain.path)/qmk_firmware/zsa_voyager_sextant_1a2b3c4d.bin'") == 0)
        #expect(try await exit("echo x > '\(toolchain.path)/readable.txt'") != 0, "the toolchain stays as installed")
        #expect(try await exit("echo x > '\(root.path)/new.txt'") != 0)
    }
}
