import Foundation
import SextantApplication
import SextantDomain

/// The build toolchain (ADR 0033): Arm's GCC 12.2.1 (the release ZSA builds with), GNU make 4, Python with the `qmk`
/// CLI and ZSA's QMK fork at pinned commits, all in one folder the setup step fills with the user's consent.
/// ``status()`` only looks at it and never downloads. Every build runs under `sandbox-exec` (``Sandbox``).
public struct NativeToolchain: Toolchain {
    let installer: ToolchainInstaller
    let runner: any CommandRunner
    var home: URL { installer.home }
    var firmware: URL { home.appending(path: "qmk_firmware", directoryHint: .isDirectory) }

    /// `installer` is shared by every window's toolchain, so only one setup runs at a time.
    public init(installer: ToolchainInstaller) { self.init(installer: installer, runner: ProcessRunner()) }

    init(installer: ToolchainInstaller, runner: any CommandRunner) {
        self.installer = installer
        self.runner = runner
    }

    public func status() async -> ToolchainStatus {
        guard installer.isInstalled else {
            let size = ByteCountFormatter.string(fromByteCount: installer.downloadSize, countStyle: .file)
            return .needsSetup(String(localized: "Building firmware needs a one-time download of the build tools (about \(size))."))
        }
        return .ready(String(localized: "ZSA's compiler (Arm GCC 12.2.1) and QMK firmware 25, on this Mac"))
    }

    public func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        let scratch = home.appending(path: "tmp", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let tools = ["arm/bin", "make/bin", "python/bin"].map { home.appending(path: $0).path }
        let sandbox = Sandbox(readable: home, writable: [firmware.appending(path: ".build"), scratch], images: firmware)
        return QMKBuild(
            hostHome: firmware, commandHome: firmware.path, runner: runner,
            qmk: sandbox.command + [home.appending(path: "python/bin/qmk").path],
            environment: [
                "PATH": (tools + ["/usr/bin", "/bin"]).joined(separator: ":"), "HOME": scratch.path, "TMPDIR": scratch.path,
                // The sandbox keeps the toolchain read-only; Python would try to write bytecode next to its modules.
                "PYTHONDONTWRITEBYTECODE": "1",
            ]
        )
        .run(source, board: board)
    }

    public func setUp() -> AsyncStream<SetupEvent> { installer.setUp() }
}

/// A `sandbox-exec` profile for a build (ADR 0033): no network, no reads in the home folder outside the toolchain, and
/// writes only to the build's folders and its firmware image. A layout that got past the generator's validation can't
/// read the user's files into the firmware, send anything anywhere, or change the toolchain for later builds.
struct Sandbox {
    /// The toolchain folder, the only part of the home folder a build reads.
    var readable: URL
    var writable: [URL]
    /// The QMK home, where `qmk compile` copies the finished `.bin`.
    var images: URL
    var home = URL.homeDirectory

    var command: [String] { ["/usr/bin/sandbox-exec", "-p", profile] }

    var profile: String {
        let writes = writable.map { "(subpath \(Self.quoted($0)))" }.joined(separator: " ")
        let image = "^" + NSRegularExpression.escapedPattern(for: Self.canonical(images)) + "/zsa_[a-z0-9_]+\\.bin$"
        return """
            (version 1)
            (allow default)
            (deny network*)
            (deny file-write*)
            (allow file-write* \(writes) (regex #"\(image)") (literal "/dev/null") (literal "/dev/dtracehelper"))
            (deny file-read-data (subpath \(Self.quoted(home))))
            (allow file-read-data (subpath \(Self.quoted(readable))))
            """
    }

    /// The real path: sandbox rules match resolved paths (`/private/var`, not `/var`).
    static func canonical(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func quoted(_ url: URL) -> String {
        "\"" + canonical(url).replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}
