import Foundation

extension KeyboardLayout {
    /// The JSON a build's identity and its stored record are made from: sorted keys, without macro drafts, which are
    /// never compiled (ADR 0042). Empty only if encoding fails (NaN settings, which imports can't produce).
    public func firmwareJSON() -> Data {
        var layout = self
        layout.macroDrafts = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // shortcut: encoding only fails on NaN settings, which JSON imports can't produce; upgrade if a UI can set one.
        return (try? encoder.encode(layout)) ?? Data()
    }
}

/// Why a layout record can't be made or read (ADR 0061).
public enum LayoutRecordError: Error, Equatable, Sendable, LocalizedError {
    /// The encoded record is over ``LayoutRecord/maximumSize`` bytes, or its JSON over
    /// ``LayoutRecord/maximumJSONSize``.
    case tooLarge(Int)
    /// A newer Sextant wrote it.
    case newerFormat(UInt8)
    /// Not a record: wrong magic, sizes, ids or compressed data.
    case malformed
    /// The JSON inside isn't a layout this Sextant can read.
    case unreadableLayout

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(bytes):
            String(localized: "The layout takes \(bytes) bytes in the firmware, more than the \(LayoutRecord.maximumSize) it can store.")
        case .newerFormat: String(localized: "A newer version of Sextant stored this layout. Update Sextant to read it.")
        case .malformed: String(localized: "The layout stored in the keyboard's firmware is damaged.")
        case .unreadableLayout: String(localized: "The layout stored in the keyboard's firmware isn't one this Sextant can read.")
        }
    }
}

/// The layout a Sextant build stores in its firmware, so Sextant on any Mac can read it back over raw HID (ADR 0061).
///
/// Read back, a record is untrusted input (any firmware could answer), so decoding checks every size before trusting
/// it, refuses a declared JSON over ``maximumJSONSize`` or of another length than it inflates to, and never traps.
public struct LayoutRecord: Hashable, Sendable {
    /// The largest encoded record a build stores, in bytes.
    public static let maximumSize = 32 * 1024
    public static let currentVersion: UInt8 = 1
    /// The most library ids a record holds.
    public static let maximumIDs = 16
    /// The largest JSON a record may declare (1 MiB), so a small record can't make a reader inflate a huge one.
    public static let maximumJSONSize = 1_048_576
    /// The largest record a reader takes: the raw-HID reply's size field has 16 bits.
    private static let maximumReadSize = 65_535
    /// "SXL".
    private static let magic: [UInt8] = [0x53, 0x58, 0x4C]

    /// The library ids this layout has: the building Mac's own entry id first, then the ids it is linked to on other
    /// Macs (`LibraryEntry.aliases`). 1...16 of them; ids beyond 16 are dropped.
    public var libraryIDs: [UUID]
    /// ``KeyboardLayout/firmwareJSON()``: its CRC (``fingerprint``) is a Sextant serial's fingerprint.
    public var json: Data

    public init(layout: KeyboardLayout, libraryIDs: [UUID]) {
        self.init(json: layout.firmwareJSON(), libraryIDs: libraryIDs)
    }

    public init(json: Data, libraryIDs: [UUID]) {
        self.json = json
        self.libraryIDs = Array(libraryIDs.prefix(Self.maximumIDs))
    }

    /// Reads an encoded record, checking every size before trusting it.
    public init(decoding bytes: [UInt8]) throws(LayoutRecordError) {
        guard bytes.count >= 4, bytes.starts(with: Self.magic) else { throw .malformed }
        guard bytes[3] <= Self.currentVersion else { throw .newerFormat(bytes[3]) }
        guard bytes[3] == Self.currentVersion, bytes.count >= 5, bytes.count <= Self.maximumReadSize else { throw .malformed }
        let count = Int(bytes[4])
        let lengthAt = 5 + count * 16
        // At least one compressed byte after the ids and the length.
        guard (1...Self.maximumIDs).contains(count), bytes.count > lengthAt + 4 else { throw .malformed }
        let ids = (0..<count).map { i in Self.uuid(Array(bytes[(5 + i * 16)..<(21 + i * 16)])) }
        let length = bytes[lengthAt..<lengthAt + 4].reduce(0) { ($0 << 8) | Int($1) }
        guard (1...Self.maximumJSONSize).contains(length) else { throw .malformed }
        let json: Data
        // Foundation's decoder decides whether bytes after the compressed stream are an error; either way the JSON must
        // be exactly as long as declared.
        do { json = try Self.inflate(Data(bytes[(lengthAt + 4)...])) } catch { throw .malformed }
        guard json.count == length else { throw .malformed }
        self.init(json: json, libraryIDs: ids)
    }

    /// `53 58 4C` ("SXL"), version, id count n (1...16, extra ids dropped), n × 16 UUID bytes, the JSON's length (UInt32
    /// big-endian), then the JSON compressed with Foundation's `.zlib` (raw DEFLATE).
    public func encoded() throws(LayoutRecordError) -> [UInt8] {
        let ids = libraryIDs.prefix(Self.maximumIDs)
        guard !ids.isEmpty else { throw .malformed }
        guard !json.isEmpty else { throw .unreadableLayout }
        guard json.count <= Self.maximumJSONSize else { throw .tooLarge(json.count) }
        let compressed: Data
        do { compressed = try Self.deflate(json) } catch { throw .malformed }
        var bytes = Self.magic + [Self.currentVersion, UInt8(ids.count)]
        for id in ids { bytes += withUnsafeBytes(of: id.uuid) { Array($0) } }
        let length = UInt32(json.count)
        bytes += [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: length >> $0) }
        bytes += compressed
        guard bytes.count <= Self.maximumSize else { throw .tooLarge(bytes.count) }
        return bytes
    }

    /// Decodes the JSON as a layout.
    public func layout() throws(LayoutRecordError) -> KeyboardLayout {
        do { return try JSONDecoder().decode(KeyboardLayout.self, from: json) } catch { throw .unreadableLayout }
    }

    /// `FirmwareImage.crc(json)`: equals the fingerprint in the serial of the build that stored it.
    public var fingerprint: UInt32 { FirmwareImage.crc(json) }

    /// A UUID from exactly 16 bytes.
    private static func uuid(_ b: [UInt8]) -> UUID {
        UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    // Foundation offers raw DEFLATE only on NSData, and the domain imports nothing but Foundation (ADR 0008).

    private static func deflate(_ data: Data) throws -> Data {
        // swiftlint:disable:next legacy_objc_type
        try (data as NSData).compressed(using: .zlib) as Data
    }

    private static func inflate(_ data: Data) throws -> Data {
        // swiftlint:disable:next legacy_objc_type
        try (data as NSData).decompressed(using: .zlib) as Data
    }
}
