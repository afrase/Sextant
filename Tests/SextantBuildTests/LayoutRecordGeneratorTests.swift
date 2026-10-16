import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// The layout record in a build (ADR 0061): `sextant_layout.c` and the two `rules.mk` lines that link it in front of
/// `zsa/oryx`, only when the identity carries a record.
struct LayoutRecordGeneratorTests {
    let id = UUID()

    func userLayout() throws -> KeyboardLayout {
        try KeyboardLayout(oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.examples.appending(path: "my-layout-KlgM7-full.json")))
    }

    /// The identity of a Sextant build of `layout`, storing its record.
    func storing(_ layout: KeyboardLayout) -> FirmwareIdentity {
        var identity = FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil)
        identity.record = LayoutRecord(layout: layout, libraryIDs: [id])
        return identity
    }

    @Test func aRecordAddsItsSourceAndTwoRules() throws {
        let layout = try userLayout()
        let plain = try QMKGenerator().generate(layout, identity: FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil))
        let stored = try QMKGenerator().generate(layout, identity: storing(layout))
        #expect(plain.files["sextant_layout.c"] == nil)
        #expect(Set(stored.files.keys) == Set(plain.files.keys).union(["sextant_layout.c"]))
        let rules = "SRC += sextant_layout.c\noverride EXTRALDFLAGS += -Wl,--wrap=raw_hid_receive\n"
        #expect(stored.files["rules.mk"] == (plain.files["rules.mk"] ?? "") + rules)
        for name in plain.files.keys where name != "rules.mk" {
            #expect(stored.files[name] == plain.files[name], "\(name)")
        }
        #expect(stored.sourceMap == plain.sourceMap)
    }

    /// The record's fingerprint is the one in the serial the same build reports (ADR 0019), drafts or not: a record
    /// read back names the build that stored it.
    @Test func theRecordsFingerprintIsTheSerials() throws {
        var layout = try userLayout()
        layout.updateKey(layer: 0, index: 1) { $0 = Key("KC_Q") }
        layout.addMacroDraft(Macro(steps: [MacroStep(code: "KC_A")]))
        let identity = storing(layout)
        let record = try #require(identity.record)
        #expect(identity.serial == "sx-\(id.uuidString.prefix(8))-" + String(format: "%08X", record.fingerprint))
    }

    @Test func theSourceHoldsTheEncodedRecord() throws {
        let layout = try userLayout()
        let identity = storing(layout)
        let bytes = try #require(identity.record).encoded()
        let source = try #require(try QMKGenerator().generate(layout, identity: identity).files["sextant_layout.c"])
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let header = "static const uint8_t sextant_layout[\(bytes.count)] = {"
        let start = try #require(lines.firstIndex { $0 == header })
        let end = try #require(lines[start...].firstIndex(of: "};"))
        let rows = lines[(start + 1)..<end]
        let stored = rows.flatMap { row in row.matches(of: /0x([0-9A-F]{2})/).compactMap { UInt8($0.1, radix: 16) } }
        #expect(stored == bytes)
        #expect(rows.allSatisfy { $0.matches(of: /0x/).count <= 16 }, "16 bytes a line")
    }

    /// Build & Flash leaves out a record that doesn't fit; the generator refuses one anyway.
    @Test func refusesARecordTooLargeToStore() throws {
        let layout = try userLayout()
        var identity = FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil)
        // Bytes that don't compress (a linear congruential generator's top bits).
        var noise = Data()
        var state: UInt64 = 61
        for _ in 0..<40_000 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            noise.append(UInt8(truncatingIfNeeded: state >> 56))
        }
        identity.record = LayoutRecord(json: noise, libraryIDs: [id])
        #expect(throws: GeneratorError.unsupported("storing a layout this large in the firmware", nil)) {
            _ = try QMKGenerator().generate(layout, identity: identity)
        }
    }
}

/// `sextant_layout.c` compiled with the host C compiler against stubs of QMK's headers, `zsa/oryx` and
/// `raw_hid_send`, then fed reports: the wire format the live link reads (ADR 0061). The firmware links it with
/// `--wrap=raw_hid_receive`, which Apple's linker doesn't have, so the stub harness defines `__real_raw_hid_receive`.
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/cc"), "needs a C compiler at /usr/bin/cc"))
struct LayoutRecordHandlerTests {
    @Test func answersReadsAndPassesEverythingElseOn() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sextant-record-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let record = try Self.compile(in: dir)

        let offsets = Array(stride(from: 0, to: record.count, by: 24))
        let ends = [record.count, record.count + 1, 0xFFFF]
        let unknown: [UInt8] = [0x53, 0x02] + Self.zeros(30)
        let oryx: [UInt8] = [0x00, 0x01] + (2..<32).map { UInt8($0) }  // an Oryx command, with bytes after it
        let short: [UInt8] = [0x53, 0x01, 0x00]
        var reports: [[UInt8]] = (offsets + ends).map { offset in [0x53, 0x01] + Self.bigEndian(offset) + Self.zeros(28) }
        reports += [unknown, oryx, short]
        let replies = try Self.feed(reports, in: dir)
        try #require(replies.count == reports.count, "one line per report")

        var reassembled: [UInt8] = []
        for (offset, reply) in zip(offsets, replies) {
            let count = min(24, record.count - offset)
            let header: [UInt8] = [0x53, 0x01, 0x00] + Self.bigEndian(record.count) + Self.bigEndian(offset) + [UInt8(count)]
            #expect(reply.kind == "send" && reply.bytes.count == 32)
            #expect(Array(reply.bytes.prefix(8)) == header)
            #expect(reply.bytes.dropFirst(8 + count).allSatisfy { $0 == 0 })
            reassembled += reply.bytes.dropFirst(8).prefix(count)
        }
        #expect(reassembled == record, "every part reassembles the record")
        for (offset, reply) in zip(ends, replies.dropFirst(offsets.count)) {
            let end: [UInt8] = [0x53, 0x01, 0x01] + Self.bigEndian(record.count) + Self.bigEndian(offset) + Self.zeros(25)
            #expect(reply.kind == "send" && reply.bytes == end, "offset \(offset) is at or past the end")
        }
        let rest = Array(replies.suffix(3))
        let unknownReply: [UInt8] = [0x53, 0x02, 0x02] + Self.zeros(29)
        #expect(rest[0].kind == "send" && rest[0].bytes == unknownReply, "unknown request")
        #expect(rest[1].kind == "real" && rest[1].bytes == oryx, "zsa/oryx gets its report unchanged")
        #expect(rest[2].kind == "real" && rest[2].bytes == short, "too short to be a read")
    }

    // MARK: Helpers

    struct Reply {
        /// `send` (the handler answered) or `real` (it passed the report on to zsa/oryx).
        var kind: String
        var bytes: [UInt8]
    }

    /// Writes the generated `sextant_layout.c` and the stubs into `dir`, compiles them, and returns the encoded record.
    static func compile(in dir: URL) throws -> [UInt8] {
        let layout = try KeyboardLayout(
            oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.examples.appending(path: "my-layout-KlgM7-full.json")))
        let id = UUID()
        var identity = FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil)
        identity.record = LayoutRecord(layout: layout, libraryIDs: [id])
        let record = try #require(identity.record).encoded()
        var files = ["harness.c": harness, "keyboard.h": "#pragma once\n#include <stdint.h>\n", "raw_hid.h": rawHIDHeader]
        files["sextant_layout.c"] = try QMKGenerator().generate(layout, identity: identity).files["sextant_layout.c"]
        for (name, text) in files { try Data(text.utf8).write(to: dir.appending(path: name)) }
        // The warnings sextant_layout.c must build without (QMK adds -Werror and -Wstrict-prototypes of its own).
        let flags = ["-std=gnu11", "-Wall", "-Wextra", "-Werror", "-Wstrict-prototypes", "-Wmissing-prototypes"]
        let arguments = flags + ["-DQMK_KEYBOARD_H=\"keyboard.h\"", "-I", dir.path, "-o", "harness", "sextant_layout.c", "harness.c"]
        let result = try run("/usr/bin/cc", arguments, in: dir)
        try #require(result.status == 0, "cc: \(result.output)")
        return record
    }

    /// Sends each report to the compiled handler and returns what it did with each.
    static func feed(_ reports: [[UInt8]], in dir: URL) throws -> [Reply] {
        let input = dir.appending(path: "reports.txt")
        let text = reports.map { report in report.map { String(format: "%02X", $0) }.joined(separator: " ") + "\n" }.joined()
        try Data(text.utf8).write(to: input)
        let result = try run(dir.appending(path: "harness").path, [], input: input, in: dir)
        try #require(result.status == 0, "harness: \(result.output)")
        return result.output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ")
            guard fields.count >= 2, let length = Int(fields[1]) else { return nil }
            let bytes = fields.dropFirst(2).compactMap { UInt8($0, radix: 16) }
            return bytes.count == length ? Reply(kind: String(fields[0]), bytes: bytes) : nil
        }
    }

    /// Runs `executable` to its end with its input from `input`, and returns its exit status and output.
    static func run(
        _ executable: String, _ arguments: [String], input: URL? = nil, in dir: URL
    ) throws -> (status: Int32, output: String) {
        let output = dir.appending(path: "output-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = dir
        process.standardOutput = handle
        process.standardError = handle
        if let input { process.standardInput = try FileHandle(forReadingFrom: input) }
        try process.run()
        process.waitUntilExit()
        try handle.close()
        let text = try String(contentsOf: output, encoding: .utf8)
        return (process.terminationStatus, text)
    }

    static func bigEndian(_ value: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)] }

    static func zeros(_ count: Int) -> [UInt8] { Array(repeating: 0, count: count) }

    static let rawHIDHeader = """
        #pragma once
        #include <stdint.h>

        void raw_hid_receive(uint8_t *data, uint8_t length);
        void raw_hid_send(uint8_t *data, uint8_t length);

        """

    /// Stands in for zsa/oryx (`__real_raw_hid_receive`) and QMK's `raw_hid_send`, printing what each gets, and feeds
    /// the handler one report per input line: hex bytes separated by spaces, its length the number of bytes.
    static let harness = #"""
        #include <stdint.h>
        #include <stdio.h>
        #include <string.h>
        #include "raw_hid.h"

        void __real_raw_hid_receive(uint8_t *data, uint8_t length);
        void __wrap_raw_hid_receive(uint8_t *data, uint8_t length);

        static void print_report(const char *label, const uint8_t *data, uint8_t length) {
            printf("%s %u", label, (unsigned)length);
            for (unsigned i = 0; i < length; i++) printf(" %02X", data[i]);
            printf("\n");
        }

        void __real_raw_hid_receive(uint8_t *data, uint8_t length) {
            print_report("real", data, length);
        }

        void raw_hid_send(uint8_t *data, uint8_t length) {
            print_report("send", data, length);
        }

        int main(void) {
            char line[512];
            while (fgets(line, sizeof(line), stdin) != NULL) {
                uint8_t report[32];
                memset(report, 0, sizeof(report));
                uint8_t length = 0;
                unsigned value = 0;
                int used = 0;
                const char *p = line;
                while (length < 32 && sscanf(p, "%x%n", &value, &used) == 1) {
                    report[length++] = (uint8_t)value;
                    p += used;
                }
                __wrap_raw_hid_receive(report, length);
            }
            return 0;
        }

        """#
}

/// A real build with the record (ADR 0061), with the toolchain `RealToolchainTests` sets up: it links only if
/// `rules.mk`'s `--wrap=raw_hid_receive` reaches the linker, since nothing else defines `__real_raw_hid_receive`.
/// Off unless `SEXTANT_REAL_TOOLCHAIN=1` and the toolchain is installed; nothing reaches a keyboard.
@Suite(.enabled(if: LayoutRecordRealBuildTests.canBuild, "needs SEXTANT_REAL_TOOLCHAIN=1 and the set-up toolchain"))
struct LayoutRecordRealBuildTests {
    static var canBuild: Bool { ProcessInfo.processInfo.environment["SEXTANT_REAL_TOOLCHAIN"] == "1" && ToolchainInstaller().isInstalled }

    @Test func buildsTheUsersLayoutWithItsRecord() async throws {
        let layout = try KeyboardLayout(
            oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.examples.appending(path: "my-layout-KlgM7-full.json")))
        let id = UUID()
        var identity = FirmwareIdentity(layout: layout, libraryID: id, importedLayout: nil)
        identity.record = LayoutRecord(layout: layout, libraryIDs: [id])
        let record = try #require(identity.record).encoded()
        let source = try QMKGenerator().generate(layout, identity: identity)
        var log: [String] = []
        var result: BuildEvent?
        for await event in NativeToolchain(installer: ToolchainInstaller()).build(source, board: .voyager) {
            switch event {
            case let .output(line): log.append(line)
            case .finished, .failed: result = event
            default: break
            }
        }
        guard case let .finished(artifact)? = result else {
            Issue.record("build: \(String(describing: result))\n\(log.suffix(60).joined(separator: "\n"))")
            return
        }
        try FirmwareImage(data: artifact.image).validate(forBootloaderPID: 0x0791, board: .voyager)
        #expect(log.contains { $0.contains("sextant_layout.c") })
        #expect(log.contains { $0.contains("navigator_trackpad.c") }, "the Navigator trackpad stays in")
        #expect(artifact.image.range(of: Data(record)) != nil, "the record is in the image as it was encoded")
        #expect(artifact.image.range(of: Data(identity.serial.utf8)) != nil)
    }
}
