import Containerization
import Foundation
import SextantApplication
import SextantDomain
import Synchronization

/// The default toolchain (ADR 0018): `qmk compile` in a throwaway Linux VM (Apple Containerization) running a pinned
/// Debian bookworm root filesystem with ZSA's compiler, against a pinned checkout of ZSA's QMK fork.
///
/// Everything lives in one folder that the setup step fills, with the user's consent: the VM kernel, the init and root
/// filesystems, and the firmware checkout. ``status()`` only looks at it and never downloads anything.
public struct ContainerToolchain: Toolchain {
    /// What the setup step installs, pinned (research 02 §6–7): a `debian:bookworm` root filesystem with
    /// `gcc-arm-none-eabi 15:12.2.rel1-1` (ZSA's compiler), `qmk`, GNU make and `dfu-suffix`, plus these checkouts.
    public enum Pins {
        /// `zsa/qmk_firmware`, branch `firmware25`.
        public static let firmwareCommit = "93b2b9ec3368f86c5eb5a2e3f934049f8daef885"
        /// `zsa/qmk_modules` (submodule `modules/zsa`).
        public static let modulesCommit = "13890cd7856175de20798689d15ba6a46bf0c5c7"
    }

    struct Home: Sendable {
        let root: URL
        var kernel: URL { root.appending(path: "vmlinux") }
        var initfs: URL { root.appending(path: "initfs.ext4") }
        var rootfs: URL { root.appending(path: "rootfs.ext4") }
        var firmware: URL { root.appending(path: "qmk_firmware", directoryHint: .isDirectory) }
    }

    let home: Home
    let runner: any CommandRunner

    public init(home: URL = Self.defaultHome()) {
        let home = Home(root: home)
        self.init(home: home, runner: VirtualMachineRunner(home: home))
    }

    init(home: Home, runner: any CommandRunner) {
        self.home = home
        self.runner = runner
    }

    public static func defaultHome() -> URL {
        URL.applicationSupportDirectory.appending(path: "Sextant/Toolchain/container", directoryHint: .isDirectory)
    }

    public func status() async -> ToolchainStatus {
        let files = [home.kernel, home.initfs, home.rootfs]
        guard files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
            Self.checkedOut(home.firmware.appending(path: ".git/HEAD")) == Pins.firmwareCommit,
            Self.checkedOut(home.firmware.appending(path: ".git/modules/modules/zsa/HEAD")) == Pins.modulesCommit
        else {
            return .needsSetup(String(localized: "Building firmware needs a one-time download of the build tools (about 1 GB)."))
        }
        return .ready(String(localized: "Linux build VM with ZSA's compiler and QMK firmware 25"))
    }

    public func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        QMKBuild(hostHome: home.firmware, commandHome: VirtualMachineRunner.firmwareMount, runner: runner).run(source, board: board)
    }

    /// The commit a detached checkout's `HEAD` file names.
    static func checkedOut(_ head: URL) -> String? {
        (try? String(contentsOf: head, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The fallback toolchain: `qmk compile` on the Mac with a managed QMK CLI, Arm compiler and GNU make 4, against a
/// checkout of ZSA's QMK fork, all in one folder the setup step fills.
public struct NativeToolchain: Toolchain {
    let home: URL
    let runner: any CommandRunner
    private var qmk: URL { home.appending(path: "venv/bin/qmk") }
    private var tools: URL { home.appending(path: "toolchain/bin") }
    private var firmware: URL { home.appending(path: "qmk_firmware", directoryHint: .isDirectory) }

    public init(home: URL = Self.defaultHome()) { self.init(home: home, runner: ProcessRunner()) }

    init(home: URL, runner: any CommandRunner) {
        self.home = home
        self.runner = runner
    }

    public static func defaultHome() -> URL {
        URL.applicationSupportDirectory.appending(path: "Sextant/Toolchain/native", directoryHint: .isDirectory)
    }

    public func status() async -> ToolchainStatus {
        guard FileManager.default.isExecutableFile(atPath: qmk.path),
            FileManager.default.fileExists(atPath: tools.appending(path: "arm-none-eabi-gcc").path),
            ContainerToolchain.checkedOut(firmware.appending(path: ".git/HEAD")) == ContainerToolchain.Pins.firmwareCommit
        else { return .needsSetup(String(localized: "Building firmware needs a one-time download of the build tools.")) }
        return .ready(String(localized: "QMK on this Mac"))
    }

    public func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        let path = [tools.path, qmk.deletingLastPathComponent().path, "/usr/bin", "/bin"].joined(separator: ":")
        return QMKBuild(hostHome: firmware, commandHome: firmware.path, runner: runner, qmk: qmk.path, environment: ["PATH": path])
            .run(source, board: board)
    }
}

/// Runs a build command in a throwaway Linux VM: the pinned root filesystem read-only, the firmware checkout shared
/// read-write at ``firmwareMount``, no network.
struct VirtualMachineRunner: CommandRunner {
    static let firmwareMount = "/qmk"
    let home: ContainerToolchain.Home

    func run(_ command: BuildCommand) -> AsyncThrowingStream<CommandOutput, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let output = LineWriter { continuation.yield(.line($0)) }
                    let container = try makeContainer(command, output: output)
                    try await container.create()
                    let status: ExitStatus
                    do {
                        try await container.start()
                        status = try await withTaskCancellationHandler {
                            try await container.wait()
                        } onCancel: {
                            Task { try? await container.kill(.kill) }
                        }
                    } catch {
                        try? await container.stop()  // never leave a VM running
                        throw error
                    }
                    try? await container.stop()
                    output.flush()
                    continuation.yield(.exit(status.exitCode))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeContainer(_ command: BuildCommand, output: LineWriter) throws -> LinuxContainer {
        let vmm = VZVirtualMachineManager(
            kernel: Kernel(path: home.kernel, platform: .linuxArm),
            initialFilesystem: .block(format: "ext4", source: home.initfs.path, destination: "/", options: ["ro"]))
        let id = "sextant-build-\(UUID().uuidString.prefix(8).lowercased())"
        let cpus = min(8, ProcessInfo.processInfo.activeProcessorCount)
        return try LinuxContainer(
            id, rootfs: .block(format: "ext4", source: home.rootfs.path, destination: "/", options: ["ro"]), vmm: vmm,
            vm: VMResources(cpus: cpus, memoryInBytes: 3 << 30)
        ) { config in
            config.cpus = cpus
            config.memoryInBytes = 2 << 30
            config.process.arguments = command.arguments
            config.process.workingDirectory = command.workingDirectory
            config.process.environmentVariables += ["HOME=/tmp"] + command.environment.map { "\($0)=\($1)" }
            config.process.stdout = output
            config.process.stderr = output
            config.mounts.append(.share(source: home.firmware.path, destination: Self.firmwareMount))
            config.mounts.append(.any(type: "tmpfs", source: "tmpfs", destination: "/tmp", options: ["mode=1777"]))
        }
    }
}

/// Splits a VM process's output bytes into lines.
final class LineWriter: Writer, Sendable {
    private let pending = Mutex(Data())
    private let line: @Sendable (String) -> Void

    init(line: @escaping @Sendable (String) -> Void) { self.line = line }

    func write(_ data: Data) throws {
        let complete: [Data] = pending.withLock { buffer in
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        for bytes in complete { line(Self.text(bytes)) }
    }

    func close() throws { flush() }

    /// Emits a last line that had no newline.
    func flush() {
        let rest = pending.withLock { buffer in
            defer { buffer.removeAll() }
            return buffer
        }
        if !rest.isEmpty { line(Self.text(rest)) }
    }

    /// Compiler output is UTF-8; anything else still comes through (Latin-1 decodes every byte).
    private static func text(_ bytes: Data) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }
}
