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
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .heldByAnotherApp:
            String(localized: "In use by Keymapp. Quit Keymapp or disconnect it there; Sextant connects automatically.")
        case .hardwareAccessOff: String(localized: "Live keyboard access is off.")
        case .notFound: String(localized: "No keyboard.")
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
    /// The stream ends after this.
    case ended(DeviceError?)
}

/// The live connection to a keyboard in normal mode.
public protocol KeyboardLink: Sendable {
    /// Opens the raw-HID interface (never seized), identifies and pairs, then streams events until the
    /// consuming task is cancelled or the device goes away. Ends with `.ended`.
    func session(with device: KeyboardDevice, board: BoardDefinition) -> AsyncStream<LiveEvent>
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
                    Flashing is turned off in this version of Sextant, so the firmware was built but not written. \
                    Nothing on the keyboard changed.
                    """)
        case let .imageRejected(reason): String(localized: "Sextant won't flash this image: \(reason.localizedDescription)")
        case .checksumMismatch: String(localized: "Sextant won't flash this image: its checksum doesn't match the build.")
        case .deviceNotFound, .deviceBusy, .dfuError, .timeout, .transfer:
            String(localized: "Flashing didn't finish. Nothing is broken: put the keyboard in flash mode again to retry.")
        }
    }
}

/// Writes an image to a bootloader. Implementations enforce the flasher guards (CLAUDE.md, ADR 0013).
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
