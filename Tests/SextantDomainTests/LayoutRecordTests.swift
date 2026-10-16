import Foundation
import SextantDomain
import Testing

/// The layout record a Sextant build stores (ADR 0061): what it holds, and reading back whatever a firmware answers
/// without trapping.
struct LayoutRecordTests {
    let ids = [UUID(), UUID()]

    @Test func roundTripsTheUsersLayout() throws {
        let layout = try Fixtures.layout("my-layout-KlgM7-full.json")
        let record = LayoutRecord(layout: layout, libraryIDs: ids)
        let bytes = try record.encoded()
        let firstID = withUnsafeBytes(of: ids[0].uuid) { Array($0) }
        #expect(Array(bytes.prefix(5)) == [0x53, 0x58, 0x4C, 0x01, 0x02])
        #expect(Array(bytes[5..<21]) == firstID)
        #expect(bytes.count < record.json.count / 2, "compressed")
        let decoded = try LayoutRecord(decoding: bytes)
        #expect(decoded == record)
        #expect(decoded.libraryIDs == ids)
        #expect(try decoded.layout() == layout)
    }

    /// The fingerprint is the CRC of the layout's sorted-keys JSON without macro drafts, as in a Sextant serial
    /// (ADR 0019): a record names the build that stores it.
    @Test func theFingerprintIsTheSerials() throws {
        let layout = try Fixtures.layout()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try encoder.encode(layout)
        var drafted = layout
        drafted.addMacroDraft(Macro(steps: [MacroStep(code: "KC_A")]))
        #expect(layout.firmwareJSON() == json)
        #expect(drafted.firmwareJSON() == json, "macro drafts are never compiled")
        let record = LayoutRecord(layout: drafted, libraryIDs: ids)
        #expect(record.json == json)
        #expect(record.fingerprint == FirmwareImage.crc(json))
        #expect(try LayoutRecord(decoding: record.encoded()).fingerprint == record.fingerprint)
    }

    @Test func keepsAtMostSixteenIDs() throws {
        let many = (0..<20).map { _ in UUID() }
        var record = LayoutRecord(json: Data("{}".utf8), libraryIDs: many)
        #expect(record.libraryIDs == Array(many.prefix(16)))
        record.libraryIDs = many
        let bytes = try record.encoded()
        #expect(bytes[4] == 16)
        #expect(try LayoutRecord(decoding: bytes).libraryIDs == Array(many.prefix(16)))
    }

    @Test func refusesToEncodeWhatNoReaderTakes() {
        #expect(throws: LayoutRecordError.malformed) { _ = try LayoutRecord(json: Data("{}".utf8), libraryIDs: []).encoded() }
        #expect(throws: LayoutRecordError.unreadableLayout) { _ = try LayoutRecord(json: Data(), libraryIDs: ids).encoded() }
        let huge = Data(repeating: 0x20, count: LayoutRecord.maximumJSONSize + 1)
        #expect(throws: LayoutRecordError.tooLarge(huge.count)) { _ = try LayoutRecord(json: huge, libraryIDs: ids).encoded() }
    }

    /// A record over 32 KiB isn't stored; Build & Flash then builds without one (ADR 0061).
    @Test func refusesARecordOverTheMaximumSize() throws {
        var generator = SplitMix64(seed: 61)
        let noise = Data((0..<40_000).map { _ in UInt8.random(in: 0...255, using: &generator) })
        do throws(LayoutRecordError) {
            _ = try LayoutRecord(json: noise, libraryIDs: ids).encoded()
            Issue.record("encoded \(noise.count) random bytes into a record")
        } catch {
            guard case let .tooLarge(size) = error else {
                Issue.record("threw \(error)")
                return
            }
            #expect(size > LayoutRecord.maximumSize)
        }
        #expect(try LayoutRecord(json: noise.prefix(20_000), libraryIDs: ids).encoded().count <= LayoutRecord.maximumSize)
    }

    @Test func aNewerFormatSaysSo() throws {
        var parts = Parts(try LayoutRecord(layout: Fixtures.layout(), libraryIDs: ids).encoded())
        parts.head[3] = 2
        #expect(throws: LayoutRecordError.newerFormat(2)) { _ = try LayoutRecord(decoding: parts.bytes) }
        #expect(throws: LayoutRecordError.newerFormat(0xFF)) { _ = try LayoutRecord(decoding: [0x53, 0x58, 0x4C, 0xFF]) }
    }

    @Test(arguments: Damage.allCases)
    func refusesADamagedRecord(_ damage: Damage) throws {
        let bytes = try damaged(damage)
        #expect(throws: LayoutRecordError.malformed) { _ = try LayoutRecord(decoding: bytes) }
    }

    /// Foundation's decoder decides about bytes after the compressed stream: the result is the same record or
    /// `malformed`, never another record.
    @Test func bytesAfterTheCompressedStream() throws {
        let record = LayoutRecord(layout: try Fixtures.layout(), libraryIDs: ids)
        let bytes = try record.encoded() + [0x00, 0x53, 0xFF]
        do throws(LayoutRecordError) {
            let decoded = try LayoutRecord(decoding: bytes)
            #expect(decoded == record)
        } catch {
            #expect(error == .malformed)
        }
    }

    @Test func jsonThatIsntALayoutIsUnreadable() {
        #expect(throws: LayoutRecordError.unreadableLayout) { _ = try LayoutRecord(json: Data("{}".utf8), libraryIDs: ids).layout() }
        #expect(throws: LayoutRecordError.unreadableLayout) { _ = try LayoutRecord(json: Data("no".utf8), libraryIDs: ids).layout() }
    }

    /// Whatever a firmware answers, decoding throws or returns a record: it never traps.
    @Test func neverTrapsOnNoise() throws {
        let valid = try LayoutRecord(layout: Fixtures.layout(), libraryIDs: ids).encoded()
        var generator = SplitMix64(seed: 0x5358_4C01)
        for _ in 0..<400 {
            var bytes = Array(valid.prefix(Int.random(in: 0...valid.count, using: &generator)))
            for _ in 0..<Int.random(in: 0...8, using: &generator) where !bytes.isEmpty {
                let index = Int.random(in: 0..<bytes.count, using: &generator)
                bytes[index] = UInt8.random(in: 0...255, using: &generator)
            }
            if let record = try? LayoutRecord(decoding: bytes) { _ = try? record.layout() }
        }
        for _ in 0..<400 {
            let noise = (0..<Int.random(in: 0...300, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator) }
            _ = try? LayoutRecord(decoding: [0x53, 0x58, 0x4C, 0x01] + noise)
        }
    }

    // MARK: Helpers

    /// Ways to break a record.
    enum Damage: String, CaseIterable, Sendable {
        case empty, oneByte, magicOnly, noIDCount, wrongMagic, versionZero, noIDs, seventeenIDs, idsPastTheEnd
        case lengthZero, lengthOverOneMiB, lengthOneShort, lengthOneLong
        case noCompressedBytes, truncatedDeflate, notDeflate, overSixtyFourKiB
    }

    /// The user's layout as a record, with `damage` done to it.
    func damaged(_ damage: Damage) throws -> [UInt8] {
        var parts = Parts(try LayoutRecord(layout: Fixtures.layout(), libraryIDs: ids).encoded())
        switch damage {
        case .empty: return []
        case .oneByte: return [0x53]
        case .magicOnly: return [0x53, 0x58, 0x4C]
        case .noIDCount: return [0x53, 0x58, 0x4C, 0x01]
        case .wrongMagic: parts.head[0] = 0x54
        case .versionZero: parts.head[3] = 0
        case .noIDs:
            parts.count = 0
            parts.ids = []
        case .seventeenIDs:
            parts.count = 17
            parts.ids += Array(repeating: 0xAB, count: 15 * 16)
        case .idsPastTheEnd:
            // Three ids declared, one there: the length and compressed bytes would start past the end.
            var bytes: [UInt8] = [0x53, 0x58, 0x4C, 0x01, 0x03]
            bytes += Array(repeating: 0xAB, count: 16)
            bytes += [0x00, 0x00, 0x00, 0x02, 0xAB, 0x06, 0x00]
            return bytes
        case .lengthZero: parts.length = 0
        case .lengthOverOneMiB: parts.length = UInt32(LayoutRecord.maximumJSONSize + 1)
        case .lengthOneShort: parts.length -= 1
        case .lengthOneLong: parts.length += 1
        case .noCompressedBytes: parts.compressed = []
        case .truncatedDeflate: parts.compressed.removeLast(parts.compressed.count / 2)
        case .notDeflate: parts.compressed = Array(repeating: 0xFF, count: 64)
        case .overSixtyFourKiB: parts.compressed += Array(repeating: 0, count: 70_000)
        }
        return parts.bytes
    }

    /// An encoded record, cut into the parts a damaged one changes.
    struct Parts {
        var head: [UInt8]
        var count: UInt8
        var ids: [UInt8]
        var length: UInt32
        var compressed: [UInt8]

        init(_ bytes: [UInt8]) {
            let lengthAt = 5 + Int(bytes[4]) * 16
            head = Array(bytes.prefix(4))
            count = bytes[4]
            ids = Array(bytes[5..<lengthAt])
            length = bytes[lengthAt..<lengthAt + 4].reduce(0) { ($0 << 8) | UInt32($1) }
            compressed = Array(bytes[(lengthAt + 4)...])
        }

        var bytes: [UInt8] {
            var out = head
            out.append(count)
            out += ids
            out += [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: length >> $0) }
            out += compressed
            return out
        }
    }
}

/// A seeded generator (SplitMix64), so the noise is the same on every run.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
