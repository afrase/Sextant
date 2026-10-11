import CryptoKit
import Foundation
import SextantApplication
import Synchronization
import os

/// Downloads one pinned file: URLSession in the app, a fake in tests.
protocol Downloading: Sendable {
    /// Saves `artifact` at `file`, reporting the bytes received so far. Stops past `artifact.size` bytes.
    func download(_ artifact: Artifact, to file: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
}

/// The one-time setup of the build tools (spec §7.3, ADR 0033): downloads every pinned artifact, refuses any that
/// isn't exactly its pinned size and SHA-256, unpacks them with `/usr/bin/tar` and installs the wheels with pip from
/// the verified files only. The marker holding the pins is written last, so an interrupted setup reads as not set up;
/// verified downloads are kept for the retry. The composition root makes one, shared by every window, so only one
/// setup runs at a time.
public actor ToolchainInstaller {
    nonisolated public let home: URL
    private let downloader: any Downloading
    private let runner: any CommandRunner
    private let artifacts: [Artifact]
    private var running = false
    private let log = Logger(subsystem: "com.sextant.app", category: "build")

    public init(home: URL = ToolchainInstaller.defaultHome()) {
        self.init(home: home, downloader: URLSessionDownloader(), runner: ProcessRunner(), artifacts: ToolchainPins.all)
    }

    init(home: URL, downloader: any Downloading, runner: any CommandRunner, artifacts: [Artifact]) {
        self.home = home
        self.downloader = downloader
        self.runner = runner
        self.artifacts = artifacts
    }

    /// `~/Library/Caches/com.sextant.app/Toolchain`: QMK's makefiles can't take spaces in paths (so not Application
    /// Support), and everything here can be downloaded again.
    public static func defaultHome() -> URL {
        URL.cachesDirectory.appending(path: "com.sextant.app/Toolchain", directoryHint: .isDirectory)
    }

    nonisolated var marker: URL { home.appending(path: ".pins") }
    nonisolated var downloads: URL { home.appending(path: "downloads", directoryHint: .isDirectory) }

    /// The pinned set is installed: the marker the setup writes last names exactly these artifacts.
    nonisolated var isInstalled: Bool {
        (try? String(contentsOf: marker, encoding: .utf8)) == Self.identity(of: artifacts)
    }

    /// Bytes the setup downloads.
    nonisolated var downloadSize: Int64 { artifacts.reduce(0) { $0 + $1.size } }

    static func identity(of artifacts: [Artifact]) -> String {
        artifacts.map { "\($0.name) \($0.sha256)" }.joined(separator: "\n")
    }

    nonisolated public func setUp() -> AsyncStream<SetupEvent> {
        AsyncStream { continuation in
            let task = Task {
                do throws(ToolchainError) {
                    try await install { continuation.yield($0) }
                    continuation.yield(.finished)
                } catch {
                    continuation.yield(.failed(Task.isCancelled ? .cancelled : error))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func install(_ emit: @escaping @Sendable (SetupEvent) -> Void) async throws(ToolchainError) {
        guard !running else {
            throw .failed(String(localized: "The build tools are already being set up in another window."))
        }
        guard artifacts.allSatisfy({ $0.sha256.count == 64 && $0.size > 0 }) else {
            throw .failed(String(localized: "This version of Sextant can't set up the build tools yet."))
        }
        running = true
        defer { running = false }
        do {
            try clearKeepingDownloads()
        } catch {
            log.error("Clearing the toolchain folder failed: \(error.localizedDescription, privacy: .public)")
            throw .failed(String(localized: "Sextant couldn't prepare the build tools folder."))
        }

        let total = downloadSize
        var done: Int64 = 0
        emit(.downloading(received: 0, total: total))
        for artifact in artifacts {
            let file = downloads.appending(path: artifact.name)
            if !Self.matches(file, artifact) {
                try? FileManager.default.removeItem(at: file)
                let before = done
                do {
                    try await downloader.download(artifact, to: file) { emit(.downloading(received: before + $0, total: total)) }
                } catch {
                    try? FileManager.default.removeItem(at: file)
                    if Task.isCancelled { throw .cancelled }
                    log.error("Downloading \(artifact.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    throw .failed(String(localized: "Downloading \(artifact.name) failed. Check the connection and try again."))
                }
                guard Self.matches(file, artifact) else {
                    try? FileManager.default.removeItem(at: file)
                    throw .failed(String(localized: "\(artifact.name) didn't match its pinned checksum, so Sextant deleted it."))
                }
            }
            done += artifact.size
            emit(.downloading(received: done, total: total))
        }

        emit(.installing)
        for artifact in artifacts {
            for pass in artifact.unpack {
                try await run(Self.tar(downloads.appending(path: artifact.name), pass, home: home), failure: artifact.name)
            }
        }
        let wheels = artifacts.filter(\.isWheel).map { downloads.appending(path: $0.name).path }
        if !wheels.isEmpty {
            // Only the verified files: no index, no dependency resolution, no user configuration.
            let python = home.appending(path: "python/bin/python3").path
            try await run(
                [python, "-m", "pip", "install", "--isolated", "--no-index", "--no-deps", "--no-cache-dir", "--disable-pip-version-check"]
                    + wheels,
                failure: "qmk")
        }
        do {
            try Data(Self.identity(of: artifacts).utf8).write(to: marker, options: .atomic)
        } catch {
            throw .failed(String(localized: "Sextant couldn't finish setting up the build tools."))
        }
        try? FileManager.default.removeItem(at: downloads)
    }

    /// Removes everything in the toolchain folder but verified-or-partial downloads.
    private func clearKeepingDownloads() throws {
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        for item in try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
        where item.lastPathComponent != "downloads" {
            try FileManager.default.removeItem(at: item)
        }
    }

    private func run(_ arguments: [String], failure name: String) async throws(ToolchainError) {
        var status: Int32 = -1
        var lines: [String] = []
        do {
            for try await event in runner.run(BuildCommand(arguments: arguments, environment: [:], workingDirectory: home.path)) {
                switch event {
                case let .line(line): lines = Array((lines + [line]).suffix(5))
                case let .exit(code): status = code
                }
            }
        } catch {
            if Task.isCancelled { throw .cancelled }
            status = -1
        }
        if Task.isCancelled { throw .cancelled }
        guard status == 0 else {
            log.error("Installing \(name, privacy: .public) failed: \(lines.joined(separator: " | "), privacy: .public)")
            throw .failed(String(localized: "Installing \(name) failed."))
        }
    }

    /// The `tar` command for one unpack pass; `into` is created first.
    static func tar(_ archive: URL, _ pass: Unpack, home: URL) -> [String] {
        let into = home.appending(path: pass.into, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: into, withIntermediateDirectories: true)
        return ["/usr/bin/tar", "-x", "-f", archive.path, "-C", into.path, "--strip-components", "\(pass.strip)"]
            + pass.exclude.flatMap { ["--exclude", $0] } + pass.include.flatMap { ["--include", $0] }
    }

    /// True when `file` is exactly the pinned artifact.
    static func matches(_ file: URL, _ artifact: Artifact) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int64, size == artifact.size,
            let handle = try? FileHandle(forReadingFrom: file)
        else { return false }
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == artifact.sha256
    }
}

/// Downloads with URLSession: only a 200 response is saved, and a response longer than the pinned size is cut off.
struct URLSessionDownloader: Downloading {
    func download(_ artifact: Artifact, to file: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        var request = URLRequest(url: artifact.url)
        for (field, value) in artifact.headers { request.setValue(value, forHTTPHeaderField: field) }
        let delegate = DownloadDelegate(file: file, limit: artifact.size, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                delegate.finish.withLock { $0 = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let file: URL
    let limit: Int64
    let progress: @Sendable (Int64) -> Void
    let finish = Mutex<CheckedContinuation<Void, any Error>?>(nil)
    private let failure = Mutex<(any Error)?>(nil)

    init(file: URL, limit: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.file = file
        self.limit = limit
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesWritten <= limit else {
            failure.withLock { $0 = URLError(.dataLengthExceedsMaximum) }
            return downloadTask.cancel()
        }
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is gone once this returns, so it moves now.
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: file)
        } catch {
            failure.withLock { $0 = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let error = failure.withLock { $0 } ?? error
        let continuation = finish.withLock { c in
            defer { c = nil }
            return c
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}
