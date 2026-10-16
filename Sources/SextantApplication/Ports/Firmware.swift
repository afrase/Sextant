import Foundation
import SextantDomain

// MARK: - Generator

/// What the built firmware calls itself: QMK `SERIAL_NUMBER`, which the keyboard reports over USB.
public struct FirmwareIdentity: Hashable, Sendable {
    public var serial: String
    /// The layout record the build stores (ADR 0061); nil stores none (Oryx's own build, the setting off, too large).
    public var record: LayoutRecord?

    public init(serial: String, record: LayoutRecord? = nil) {
        self.serial = serial
        self.record = record
    }
}

/// Generated QMK keymap sources plus the map from `keymap.c` lines back to keys.
public struct GeneratedSource: Hashable, Sendable {
    /// File name → contents: `keymap.c`, `config.h`, `rules.mk`, `keymap.json`, `i18n.h` when needed, and
    /// `sextant_layout.c` when the identity carries a layout record.
    public var files: [String: String]
    /// `keymap.c` line (1-based) → the key that line was generated from.
    public var sourceMap: [Int: KeyRef]

    public init(files: [String: String], sourceMap: [Int: KeyRef]) {
        self.files = files
        self.sourceMap = sourceMap
    }
}

/// Errors from generating source.
public enum GeneratorError: Error, Equatable, Sendable, LocalizedError {
    /// The layout uses something the generator can't express yet.
    case unsupported(String, KeyRef?)
    /// The layout is for a board this generator doesn't build for.
    case unsupportedBoard(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(what, _): String(localized: "Sextant can't build this yet: \(what)")
        case let .unsupportedBoard(board): String(localized: "Sextant can't build firmware for \(board) yet.")
        }
    }
}

/// Turns a layout into firmware sources (Oryx-equivalent QMK for ZSA boards).
public protocol FirmwareGenerator: Sendable {
    func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource
}

// MARK: - Toolchain

/// A compiler diagnostic (`file:line:col: error: message`).
public struct Diagnostic: Hashable, Sendable {
    public enum Severity: String, Hashable, Sendable { case error, warning, note }
    public var file: String
    public var line: Int
    public var column: Int
    public var severity: Severity
    public var message: String
    /// The key the line maps to, when it's in `keymap.c` and the source map knows it.
    public var key: KeyRef?

    public init(file: String, line: Int, column: Int, severity: Severity, message: String, key: KeyRef? = nil) {
        self.file = file
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.key = key
    }
}

/// A finished build.
public struct BuildArtifact: Hashable, Sendable {
    /// The `.bin`, DFU suffix included.
    public var image: Data
    /// Payload bytes used, as the build's size report states them.
    public var usedBytes: Int?
    public var log: [String]

    public init(image: Data, usedBytes: Int?, log: [String]) {
        self.image = image
        self.usedBytes = usedBytes
        self.log = log
    }
}

/// Whether the toolchain can build right now.
public enum ToolchainStatus: Hashable, Sendable {
    case ready(String)
    /// Needs a one-time download or setup (spec §7.3 "Set up the build tools").
    case needsSetup(String)
}

/// Errors from building.
public enum ToolchainError: Error, Hashable, Sendable, LocalizedError {
    case notInstalled(String)
    case compileFailed([Diagnostic])
    /// The image doesn't fit the board's flash window.
    case tooLarge(overBy: Int)
    case cancelled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: String(localized: "The build tools aren't set up yet.")
        case let .compileFailed(d):
            String(localized: "Build failed: \(d.filter { $0.severity == .error }.count) errors.")
        case let .tooLarge(over): String(localized: "Firmware is \(over) bytes too large.")
        case .cancelled: String(localized: "The build was stopped.")
        case let .failed(detail): String(localized: "The build didn't finish. \(detail)")
        }
    }
}

/// One step of a running build.
public enum BuildEvent: Hashable, Sendable {
    /// A log line (ANSI colour removed).
    case output(String)
    /// Compilation progress (spec §3.5 "Compiling keymap.c · 12 of 41").
    case compiling(file: String, done: Int, total: Int)
    case linking
    case finished(BuildArtifact)
    case failed(ToolchainError)
}

/// One step of the one-time setup (spec §7.3 "Set up the build tools").
public enum SetupEvent: Hashable, Sendable {
    /// Bytes downloaded so far, of the whole setup's download.
    case downloading(received: Int64, total: Int64)
    /// Unpacking and installing what was downloaded.
    case installing
    case finished
    case failed(ToolchainError)
}

/// Compiles generated sources into an image. Cancelling the consuming task stops the build.
public protocol Toolchain: Sendable {
    func status() async -> ToolchainStatus
    /// Streams progress and ends with `.finished` or `.failed`.
    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent>
    /// Downloads and installs what ``status()`` reports missing; the caller has the user's consent. Streams
    /// progress and ends with `.finished` or `.failed`. Cancelling the consuming task stops it.
    func setUp() -> AsyncStream<SetupEvent>
}
