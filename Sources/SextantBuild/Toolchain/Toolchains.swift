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

/// A `sandbox-exec` profile for a build (ADR 0033): no network, no Mach services (so nothing can be launched outside the
/// sandbox through LaunchServices, and the pasteboard stays out of reach), no devices, no reads of user data outside the
/// toolchain, and writes only to the build's folders and its firmware image. A layout that got past the generator's
/// validation can't read the user's files into the firmware, send anything anywhere, or change the toolchain for later
/// builds. If a real build turns out to need a Mach service, allow back only that `(global-name …)`.
struct Sandbox {
    /// The toolchain folder, the only user data a build reads.
    var readable: URL
    var writable: [URL]
    /// The QMK home, where `qmk compile` copies the finished `.bin`.
    var images: URL
    var home = URL.homeDirectory

    var command: [String] { ["/usr/bin/sandbox-exec", "-p", profile] }

    var profile: String {
        let writes = writable.map { "(subpath \(Self.quoted($0)))" }.joined(separator: " ")
        let image = "^" + NSRegularExpression.escapedPattern(for: Self.canonical(images)) + "/zsa_[a-z0-9_]+\\.bin$"
        let toToolchain = folders.map { "(literal \(Self.quoted($0)))" }.joined(separator: " ")
        let home = Self.quoted(home), readable = Self.quoted(readable)
        // Rules for an operation by name win over `file-read*`, so the reads are named, not wildcarded.
        return """
            (version 1)
            (allow default)
            (deny network*)
            (deny mach-lookup)
            (deny lsopen)
            (deny appleevent-send)
            (deny iokit-open)
            (deny file-write*)
            (allow file-write* \(writes) (regex #"\(image)") (literal "/dev/null") (literal "/dev/dtracehelper"))
            (deny file-read-data (subpath "/Users") (subpath "/Volumes") (subpath "/private/var/folders") (subpath "/private/tmp"))
            (deny file-read-data (subpath \(home)))
            (deny file-read-metadata (subpath \(home)))
            (allow file-read-metadata \(toToolchain))
            (allow file-read-data file-read-metadata (subpath \(readable)))
            """
    }

    /// The home folder and the folders in it down to the toolchain: `realpath` needs their metadata to reach it.
    private var folders: [String] {
        let home = Self.canonical(home)
        var folder = URL(filePath: Self.canonical(readable)).deletingLastPathComponent()
        var paths = [home]
        while folder.path.hasPrefix(home + "/") {
            paths.append(folder.path)
            folder.deleteLastPathComponent()
        }
        return paths
    }

    /// The real path: sandbox rules match resolved paths (`/private/var`, not `/var`).
    static func canonical(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func quoted(_ url: URL) -> String { quoted(canonical(url)) }

    private static func quoted(_ path: String) -> String {
        "\"" + path.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}
