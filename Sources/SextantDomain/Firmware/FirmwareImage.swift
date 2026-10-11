import Foundation

/// Why an image was refused (spec §7.4: "Sextant won't flash this image" plus the reason; no override).
public enum FirmwareImageError: Error, Equatable, Sendable, LocalizedError {
    case tooShort
    case missingSuffix
    case badCRC(expected: UInt32, actual: UInt32)
    case wrongVendor(UInt16)
    case wrongProduct(image: UInt16, bootloader: UInt16)
    case unknownBootloader(UInt16)
    case tooLarge(bytes: Int, limit: Int)
    case badStackPointer(UInt32)
    case badResetVector(UInt32)

    public var errorDescription: String? {
        switch self {
        case .tooShort: String(localized: "The file is too short to be firmware.")
        case .missingSuffix: String(localized: "The file has no DFU suffix.")
        case let .badCRC(expected, actual):
            String(
                localized:
                    "The DFU suffix checksum is wrong (\(String(format: "%08X", actual)), expected \(String(format: "%08X", expected))).")
        case let .wrongVendor(v): String(localized: "The image is for USB vendor \(String(format: "%04X", v)), not this keyboard.")
        case let .wrongProduct(image, bootloader):
            String(
                localized:
                    "The image is for bootloader \(String(format: "%04X", image)), but the keyboard's is \(String(format: "%04X", bootloader))."
            )
        case let .unknownBootloader(pid): String(localized: "Bootloader \(String(format: "%04X", pid)) isn't one Sextant knows.")
        case let .tooLarge(bytes, limit): String(localized: "The image is \(bytes) bytes; this keyboard takes at most \(limit).")
        case let .badStackPointer(sp): String(localized: "The image's stack pointer \(String(format: "%08X", sp)) is outside RAM.")
        case let .badResetVector(rv):
            String(localized: "The image's start address \(String(format: "%08X", rv)) is outside the application area.")
        }
    }
}

/// A firmware file: payload plus its 16-byte DFU suffix (DFU 1.1 appendix B).
public struct FirmwareImage: Hashable, Sendable {
    /// The whole file.
    public let data: Data
    /// The bytes to write (the file without its suffix).
    public var payload: Data { data.prefix(data.count - 16) }

    public var suffixVendorID: UInt16 { le16(data.count - 12) }
    public var suffixProductID: UInt16 { le16(data.count - 14) }
    public var suffixCRC: UInt32 { le32(data.count - 4) }

    public init(data: Data) { self.data = Data(data) }

    /// The checks every flasher guard needs before the first transfer (CLAUDE.md, ADR 0013).
    /// A single STM32 image on a GD32 bootloader (`0x1791`) fails the product check.
    public func validate(forBootloaderPID pid: UInt16, board: BoardDefinition) throws(FirmwareImageError) {
        guard data.count > 16 + 8 else { throw .tooShort }
        let s = data.count - 16
        guard data[data.startIndex + s + 8] == 0x55, data[data.startIndex + s + 9] == 0x46, data[data.startIndex + s + 10] == 0x44,
            data[data.startIndex + s + 11] == 16
        else { throw .missingSuffix }
        let crc = Self.crc(data.prefix(data.count - 4))
        guard crc == suffixCRC else { throw .badCRC(expected: crc, actual: suffixCRC) }
        guard suffixVendorID == board.vendorID else { throw .wrongVendor(suffixVendorID) }
        guard board.bootloaderProductIDs[pid] != nil else { throw .unknownBootloader(pid) }
        guard suffixProductID == pid else { throw .wrongProduct(image: suffixProductID, bootloader: pid) }
        let limit = Int(board.flashEnd - board.flashStart)
        guard payload.count <= limit else { throw .tooLarge(bytes: payload.count, limit: limit) }
        let sp = le32(0), reset = le32(4)
        guard board.ramRange.contains(sp) else { throw .badStackPointer(sp) }
        guard reset & 1 == 1, (board.flashStart..<board.applicationEnd).contains(reset & ~1) else { throw .badResetVector(reset) }
    }

    /// The DFU suffix CRC: CRC-32 reflected (poly 0xEDB88320), init 0xFFFFFFFF, no final XOR.
    public static func crc(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
        }
        return crc
    }

    /// Appends a DFU suffix (for tests and for builds whose toolchain didn't add one).
    public static func withSuffix(_ payload: Data, vendorID: UInt16, productID: UInt16) -> FirmwareImage {
        var d = payload
        d.append(contentsOf: [0xFF, 0xFF, UInt8(productID & 0xFF), UInt8(productID >> 8), UInt8(vendorID & 0xFF), UInt8(vendorID >> 8)])
        d.append(contentsOf: [0x00, 0x01, 0x55, 0x46, 0x44, 16])
        let crc = crc(d)
        d.append(contentsOf: [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8((crc >> 16) & 0xFF), UInt8(crc >> 24)])
        return FirmwareImage(data: d)
    }

    private func le16(_ offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) | UInt16(data[i + 1]) << 8
    }

    private func le32(_ offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
    }
}
