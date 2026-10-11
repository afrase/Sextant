import Foundation
import SextantApplication
import SextantDomain
import Subprocess
import System
import os

/// A command for a build backend to run.
struct BuildCommand: Sendable, Equatable {
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: String
}

/// What a running command reports: its output lines (stdout and stderr together), then its exit status.
enum CommandOutput: Sendable, Equatable {
    case line(String)
    case exit(Int32)
}

/// Runs a build command somewhere: on the Mac, or in a Linux VM. Cancelling the consumer stops the command.
protocol CommandRunner: Sendable {
    func run(_ command: BuildCommand) -> AsyncThrowingStream<CommandOutput, any Error>
}

/// The build both backends share: write the keymap into a QMK checkout, run `qmk compile`, read the image back.
struct QMKBuild: Sendable {
    static let keymapName = "sextant"

    /// The QMK checkout on the Mac.
    let hostHome: URL
    /// The same checkout as the command sees it.
    let commandHome: String
    let runner: any CommandRunner
    /// The `qmk` executable as the command sees it.
    var qmk = "qmk"
    /// Environment the backend adds (its tools on `PATH`).
    var environment: [String: String] = [:]
    private let log = Logger(subsystem: "com.sextant.app", category: "build")

    func run(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        AsyncStream { continuation in
            let task = Task {
                let end = await build(source, board: board) { continuation.yield($0) }
                continuation.yield(end)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func build(_ source: GeneratedSource, board: BoardDefinition, emit: (BuildEvent) -> Void) async -> BuildEvent {
        let keyboard = "zsa/\(board.name)"
        let image = hostHome.appending(path: "zsa_\(board.name)_\(Self.keymapName).bin")
        do {
            let folder = hostHome.appending(path: "keyboards/\(keyboard)/keymaps/\(Self.keymapName)", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: image)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, text) in source.files { try Data(text.utf8).write(to: folder.appending(path: name), options: .atomic) }
        } catch {
            log.error("Writing the keymap failed: \(error.localizedDescription, privacy: .public)")
            return .failed(.failed(String(localized: "Sextant couldn't write the keymap for the compiler.")))
        }

        let command = BuildCommand(
            arguments: [qmk, "compile", "-j", "8", "-kb", keyboard, "-km", Self.keymapName],
            environment: environment.merging(["QMK_HOME": commandHome, "SKIP_GIT": "yes"]) { $1 },
            workingDirectory: commandHome)
        var output = BuildLog(sourceMap: source.sourceMap)
        var status: Int32 = -1
        do {
            for try await event in runner.run(command) {
                switch event {
                case let .line(line): output.consume(line).forEach(emit)
                case let .exit(code): status = code
                }
            }
        } catch {
            if Task.isCancelled { return .failed(.cancelled) }
            log.error("The build command failed to run: \(error.localizedDescription, privacy: .public)")
            return .failed(.notInstalled(error.localizedDescription))
        }
        if Task.isCancelled { return .failed(.cancelled) }
        return finish(status: status, output: output, image: image, board: board)
    }

    private func finish(status: Int32, output: BuildLog, image: URL, board: BoardDefinition) -> BuildEvent {
        if let over = output.overflow { return .failed(.tooLarge(overBy: over)) }
        guard status == 0 else {
            if output.diagnostics.contains(where: { $0.severity == .error }) { return .failed(.compileFailed(output.diagnostics)) }
            return .failed(.failed(output.lines.suffix(3).joined(separator: "\n")))
        }
        guard let data = try? Data(contentsOf: image), data.count > 16 else {
            return .failed(.failed(String(localized: "The compiler finished without a firmware file.")))
        }
        // The payload (the file minus its 16-byte DFU suffix) must fit the board's flash window.
        let over = data.count - 16 - Int(board.flashEnd - board.flashStart)
        if over > 0 { return .failed(.tooLarge(overBy: over)) }
        return .finished(BuildArtifact(image: data, usedBytes: output.usedBytes, log: output.lines))
    }
}

/// Runs a command as a Mac process (swift-subprocess); the first argument is the executable.
struct ProcessRunner: CommandRunner {
    func run(_ command: BuildCommand) -> AsyncThrowingStream<CommandOutput, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var options = PlatformOptions()
                    options.teardownSequence = [.gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(2))]
                    options.processGroupID = 0
                    let executable = command.arguments.first ?? ""
                    let result = try await Subprocess.run(
                        executable.hasPrefix("/") ? .path(FilePath(executable)) : .name(executable),
                        arguments: Arguments(Array(command.arguments.dropFirst())),
                        environment: .inherit.updating(
                            Dictionary(
                                uniqueKeysWithValues: command.environment.compactMap { k, v in Environment.Key(rawValue: k).map { ($0, v) }
                                })),
                        workingDirectory: FilePath(command.workingDirectory),
                        platformOptions: options,
                        input: .none, output: .sequence, error: .combinedWithOutput
                    ) { execution in
                        for try await line in execution.standardOutput.strings() { continuation.yield(.line(line)) }
                    }
                    if case let .exited(code) = result.terminationStatus {
                        continuation.yield(.exit(code))
                    } else {
                        continuation.yield(.exit(-1))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
