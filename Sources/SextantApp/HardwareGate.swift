// The live-access gate (ADRs 0012, 0034): until the user turns live access on, the app wires this in place of the real
// raw-HID link, whose pairing request writes to the keyboard without a click.

import SextantApplication
import SextantDomain

/// A live link that ends every session at once and never reads its commands: live access is off.
struct RefusingKeyboardLink: KeyboardLink {
    func session(
        with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>
    ) -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in
            continuation.yield(.ended(.hardwareAccessOff))
            continuation.finish()
        }
    }
}
