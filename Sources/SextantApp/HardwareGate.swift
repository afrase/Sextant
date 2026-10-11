// The hardware gate (ADR 0012): until the user turns hardware access on, the app wires these in place of the
// real raw-HID link and DFU flasher, so nothing it runs can write to the keyboard.

import SextantApplication
import SextantDomain

/// A live link that ends every session at once: live access is off.
struct RefusingKeyboardLink: KeyboardLink {
    func session(with device: KeyboardDevice, board: BoardDefinition) -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in
            continuation.yield(.ended(.hardwareAccessOff))
            continuation.finish()
        }
    }
}

/// A flasher that refuses every image: flashing is off.
struct RefusingFlasher: Flasher {
    var isEnabled: Bool { false }
    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) {
        throw .hardwareAccessOff
    }
}
