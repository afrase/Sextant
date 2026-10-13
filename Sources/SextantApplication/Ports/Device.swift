import Foundation
import SextantDomain

/// A keyboard in normal mode.
public struct KeyboardDevice: Hashable, Sendable {
    /// IORegistry entry id; stable while plugged in.
    public var id: UInt64
    public var productID: UInt16
    /// USB serial: for Oryx and Sextant firmware, `layout/revision`.
    public var serial: String?

    public init(id: UInt64, productID: UInt16, serial: String?) {
        self.id = id
        self.productID = productID
        self.serial = serial
    }
}

/// A keyboard in flash mode (bootloader).
public struct BootloaderDevice: Hashable, Sendable {
    public var id: UInt64
    public var productID: UInt16
    public var kind: BoardDefinition.BootloaderKind
    /// `bcdDevice`: the bootloader's version.
    public var version: UInt16

    public init(id: UInt64, productID: UInt16, kind: BoardDefinition.BootloaderKind, version: UInt16) {
        self.id = id
        self.productID = productID
        self.kind = kind
        self.version = version
    }
}

public enum ConnectedDevice: Hashable, Sendable {
    case keyboard(KeyboardDevice)
    case bootloader(BootloaderDevice)

    public var id: UInt64 {
        switch self {
        case let .keyboard(k): k.id
        case let .bootloader(b): b.id
        }
    }
}

public enum DeviceEvent: Hashable, Sendable {
    case attached(ConnectedDevice)
    case detached(id: UInt64)
}

/// Read-only USB presence for a board's normal-mode and bootloader product ids.
public protocol DeviceWatcher: Sendable {
    /// Devices already present arrive first as `.attached`. Ends when the consuming task is cancelled.
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent>
}

/// Errors from the live connection.
public enum DeviceError: Error, Hashable, Sendable, LocalizedError {
    /// Another app (Keymapp) has the keyboard's raw-HID interface seized.
    case heldByAnotherApp
    /// Hardware access is switched off until the user approves it (ADR 0012).
    case hardwareAccessOff
    case notFound
    /// The keyboard is connected but no live session is paired (it is still pairing, or in flash mode), so it can't
    /// take commands.
    case notLive
    /// A command value the keyboard wouldn't bounds-check (ADR 0038).
    case outOfRange
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .heldByAnotherApp:
            String(localized: "In use by Keymapp. Quit Keymapp or disconnect it there; Sextant connects automatically.")
        case .hardwareAccessOff: String(localized: "Live keyboard access is off.")
        case .notFound: String(localized: "No keyboard.")
        case .notLive: String(localized: "The keyboard isn’t connected live yet.")
        case .outOfRange: String(localized: "The keyboard has no such layer or light.")
        case let .io(detail): String(localized: "The keyboard connection failed. \(detail)")
        }
    }
}

/// What the keyboard reports over the live connection (Oryx raw-HID protocol).
public enum LiveEvent: Hashable, Sendable {
    case firmwareSerial(String)
    case protocolVersion(UInt8)
    /// The highest active layer.
    case layer(Int)
    case keyDown(row: Int, column: Int)
    case keyUp(row: Int, column: Int)
    /// Whether a host holds the board's lights, in reply to ``KeyboardCommand/lighting(_:)``.
    case lighting(Bool)
    /// The firmware refused a command (an Oryx error code, such as `0xFF` for an unknown command).
    case error(UInt8)
    /// The stream ends after this.
    case ended(DeviceError?)
}

/// Everything Sextant may send to a keyboard over the live connection (ADR 0038). Nothing else is ever encoded: not
/// disconnect, brightness steps, the status LEDs or automouse.
public enum KeyboardCommand: Hashable, Sendable {
    /// Moves the keyboard to a layer, like TO(n): momentary layers drop, the default layer stays.
    case moveToLayer(Int)
    /// Takes the board's lights (true) or gives them back (false), which reloads the board's own lighting.
    case lighting(Bool)
    /// One light, by key index; takes the lights.
    case setLED(index: Int, red: UInt8, green: UInt8, blue: UInt8)
    /// Every light; takes the lights.
    case setAllLEDs(red: UInt8, green: UInt8, blue: UInt8)

    /// False for values the firmware doesn't bounds-check: it shifts 1 by the layer, which is undefined from 32 on,
    /// and indexes its LED array unchecked. A layer below 32 can still lie past the build's 8- or 16-bit layer state,
    /// which then truncates to no layer at all and drops the board to its default layer: callers clamp to the layers
    /// of the layout on the keyboard.
    public func isAllowed(on board: BoardDefinition) -> Bool {
        switch self {
        case let .moveToLayer(layer): (0..<32).contains(layer)
        case let .setLED(index, _, _, _): (0..<board.keyCount).contains(index)  // LED index = key index (BoardDefinition)
        case .lighting, .setAllLEDs: true
        }
    }
}

/// One report the live link wrote or read, for the Developer raw-HID log (ADR 0045). The protocol carries matrix
/// positions, never characters.
public struct HIDTraceEntry: Hashable, Sendable {
    public enum Direction: Hashable, Sendable { case sent, received }

    public var date: Date
    public var direction: Direction
    /// The report up to its stop byte; a sent one without its zero padding.
    public var bytes: [UInt8]
    /// What a received report means, when it means something.
    public var event: LiveEvent?

    public init(date: Date = .now, direction: Direction, bytes: [UInt8], event: LiveEvent? = nil) {
        self.date = date
        self.direction = direction
        self.bytes = bytes
        self.event = event
    }
}

/// The live connection to a keyboard in normal mode.
public protocol KeyboardLink: Sendable {
    /// Opens the raw-HID interface (never seized), identifies and pairs, then streams events until the
    /// consuming task is cancelled or the device goes away. Ends with `.ended`. Writes `commands` only once paired,
    /// and only those ``KeyboardCommand/isAllowed(on:)`` accepts; it drops the rest.
    func session(
        with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>
    ) -> AsyncStream<LiveEvent>
}

// MARK: - Flashing

public struct FlashProgress: Hashable, Sendable {
    public enum Phase: String, Hashable, Sendable { case erasing, writing, leaving }
    public var phase: Phase
    /// Pages erased or bytes written so far, and the total for the phase.
    public var done: Int
    public var total: Int

    public init(phase: Phase, done: Int, total: Int) {
        self.phase = phase
        self.done = done
        self.total = total
    }
}

/// Errors from flashing (spec §7.3 "Flashing didn't finish").
public enum FlashError: Error, Equatable, Sendable, LocalizedError {
    case hardwareAccessOff
    case imageRejected(FirmwareImageError)
    case checksumMismatch
    case deviceNotFound
    case deviceBusy
    /// The bootloader reported `dfuERROR` (bStatus, at an address).
    case dfuError(status: UInt8, address: UInt32)
    /// Status polling hit its cap.
    case timeout(address: UInt32)
    case transfer(String)

    public var errorDescription: String? {
        switch self {
        case .hardwareAccessOff:
            String(
                localized: """
                    Flashing is turned off on this Mac, so the firmware was built but the keyboard was never put in \
                    flash mode. Nothing on the keyboard changed.
                    """)
        case let .imageRejected(reason): String(localized: "Sextant won't flash this image: \(reason.localizedDescription)")
        case .checksumMismatch: String(localized: "Sextant won't flash this image: its checksum doesn't match the build.")
        case .deviceNotFound, .deviceBusy, .dfuError, .timeout, .transfer:
            String(localized: "Flashing didn't finish. Nothing is broken: put the keyboard in flash mode again to retry.")
        }
    }
}

/// Writes an image to a bootloader. Implementations enforce the flasher guards (AGENTS.md, ADR 0013).
public protocol Flasher: Sendable {
    /// False when flashing is switched off (ADR 0012): Build & Flash then stops before asking for flash mode.
    var isEnabled: Bool { get }
    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError)
}

extension Flasher {
    public var isEnabled: Bool { true }
}
