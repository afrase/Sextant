import CoreGraphics  // value types only (CGPoint, CGSize, CGRect); ADR 0008
import Foundation

/// Everything Sextant knows about a board model as data: keys, matrix, LEDs, USB identity and flash window.
///
/// Only this type knows the Voyager's key count, PIDs and addresses (research 00 §8). The Oryx key index
/// is the identity: index N = QMK label `kNN` = RGB LED index N.
public struct BoardDefinition: Hashable, Sendable {
    /// Per-key facts, ordered by Oryx index.
    public struct KeyInfo: Hashable, Sendable {
        /// Oryx key index (= QMK `kNN` = LED index).
        public var index: Int
        /// Firmware matrix position, as live key events report it.
        public var matrixRow: Int
        public var matrixColumn: Int
        /// Oryx's column stagger as a CSS `translateY` percentage (−15 or −30 on raised columns).
        public var staggerPercent: Double
        public var isHomeRow: Bool
        /// QMK `keyboard.json` position in key units (reference only).
        public var qmkPosition: CGPoint
        /// LED coordinate in QMK's 224×64 RGB-matrix space (reference only).
        public var ledPoint: CGPoint
        /// The half the key is on, and the finger that types it in touch typing (the Heatmap's hands and fingers).
        public var hand: Hand
        public var finger: Finger
    }

    /// A half of a split board.
    public enum Hand: String, CaseIterable, Hashable, Sendable { case left, right }

    /// The finger that presses a key: the two outer columns of each half are the pinky's, the two inner ones the index
    /// finger's, and the thumb cluster the thumb's (scripts/gen-board-definition.py).
    public enum Finger: String, CaseIterable, Hashable, Sendable { case pinky, ring, middle, index, thumb }

    /// The MCU behind a bootloader product id.
    public enum BootloaderKind: String, Hashable, Sendable { case stm32, gd32 }

    /// Oryx geometry name, e.g. `voyager`.
    public var name: String
    /// Name shown to people ("ZSA Voyager").
    public var displayName: String
    public var keys: [KeyInfo]
    /// `LAYOUT(...)` argument order, as Oryx indices.
    public var layoutOrder: [Int]
    public var matrixRows: Int
    public var matrixColumns: Int
    public var vendorID: UInt16
    /// Product ids in normal (keyboard) mode.
    public var productIDs: Set<UInt16>
    /// Product ids of the bootloader, by MCU.
    public var bootloaderProductIDs: [UInt16: BootloaderKind]
    /// Raw-HID usage page and usage of the Oryx protocol interface.
    public var rawHIDUsagePage: UInt16
    public var rawHIDUsage: UInt16
    /// First writable flash address (the bootloader lives below it; never touch).
    public var flashStart: UInt32
    /// Exclusive upper bound flashers accept.
    public var flashEnd: UInt32
    /// End of the linker's application window; a reset vector must point below it.
    public var applicationEnd: UInt32
    /// Flash page (erase unit) and DFU transfer size, in bytes.
    public var flashPageSize: Int
    /// RAM range an image's initial stack pointer must fall in.
    public var ramRange: ClosedRange<UInt32>
    /// The key the reset button sits above, on the case's top edge (spec §7.3, flash-mode card A).
    public var resetButtonKey: Int

    public var keyCount: Int { keys.count }

    /// Oryx index for a matrix position, or nil for an unused cell.
    public func keyIndex(matrixRow row: Int, column: Int) -> Int? {
        keys.first { $0.matrixRow == row && $0.matrixColumn == column }?.index
    }

    /// Every board Sextant knows (ADR 0017). Adding a board is adding its definition here.
    public static let all: [Self] = [.voyager]

    /// The board for an Oryx geometry name, e.g. `voyager`.
    public static func named(_ name: String) -> Self? { all.first { $0.name == name } }

    /// The ZSA Voyager.
    public static let voyager = Self(
        name: "voyager",
        displayName: "ZSA Voyager",
        keys: voyagerKeys,
        layoutOrder: voyagerLayoutOrder,
        matrixRows: 12,
        matrixColumns: 7,
        vendorID: 0x3297,
        productIDs: [0x1977, 0x1978],
        bootloaderProductIDs: [0x0791: .stm32, 0x1791: .gd32],
        rawHIDUsagePage: 0xFF60,
        rawHIDUsage: 0x61,
        flashStart: 0x0800_2000,
        flashEnd: 0x0804_2000,
        applicationEnd: 0x0802_0000,
        flashPageSize: 2048,
        ramRange: 0x2000_0000...0x2000_8000,
        // zsa.io/go: "a dedicated reset button, on the top edge, near the '3' key in the default layout".
        resetButtonKey: 3)
}
