import Foundation
import SextantDomain

/// Why Build & Flash stopped (spec §7.3, §7.4).
public enum BuildFlashError: Error, Equatable, Sendable, LocalizedError {
    case generator(GeneratorError)
    /// Compile errors (with their keys), too large, or a toolchain failure.
    case toolchain(ToolchainError)
    /// The build tools' one-time setup didn't finish (spec §7.3).
    case setup(ToolchainError)
    case multipleBootloaders
    /// Includes `.imageRejected`: the image failed validation for the connected bootloader, with no override.
    case flash(FlashError)
    /// The keyboard didn't come back within 10 s of flashing.
    case notReconnected
    /// The keyboard came back reporting another serial than the build's.
    case unexpectedSerial(String?)
    /// Another layout's Build & Flash holds flash mode (spec §7.6).
    case flashingElsewhere

    public var errorDescription: String? {
        switch self {
        case let .generator(e): e.localizedDescription
        case let .toolchain(e): e.localizedDescription
        // The detail alone: the toolchain's own wording says the build didn't finish.
        case let .setup(.failed(detail)): detail
        case let .setup(e): e.localizedDescription
        case .multipleBootloaders: String(localized: "Connect only one keyboard in flash mode.")
        case let .flash(e): e.localizedDescription
        case .notReconnected:
            String(localized: "The keyboard didn't reconnect after flashing. Unplug it and plug it back in to check it.")
        case let .unexpectedSerial(serial?):
            String(localized: "The keyboard reconnected as \(serial), not the new firmware. Put it in flash mode to try again.")
        case .unexpectedSerial(nil):
            String(localized: "The keyboard reconnected without a serial. Put it in flash mode to try again.")
        case .flashingElsewhere: String(localized: "Another window is flashing the keyboard. Try again when it finishes.")
        }
    }
}

extension ToolchainError {
    /// Points compile errors in `keymap.c` at the keys they came from.
    func mapped(through sourceMap: [Int: KeyRef]) -> ToolchainError {
        guard case let .compileFailed(diagnostics) = self else { return self }
        return .compileFailed(
            diagnostics.map { d in
                var d = d
                if d.key == nil, d.file.split(separator: "/").last == "keymap.c" { d.key = sourceMap[d.line] }
                return d
            })
    }
}
