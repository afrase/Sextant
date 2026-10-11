import Foundation
import SextantDomain
import Testing

/// Image validation against the real Oryx builds in `docs/research/oryx-examples/sources/*.zip`, unzipped at test
/// time (the `.bin` files are never committed on their own).
struct FirmwareImageTests {
    static let builds = ["KlgM7-40xJ7M", "JRGQm", "e5Rrr", "m9dpx", "XlrR4"]
    let board = BoardDefinition.voyager

    @Test(arguments: builds)
    func realBuildsPassForTheirBootloaderOnly(_ build: String) throws {
        let image = try Self.image(build)
        try image.validate(forBootloaderPID: 0x0791, board: board)
        // A single STM32 image is refused on a GD32 bootloader.
        #expect(throws: FirmwareImageError.wrongProduct(image: 0x0791, bootloader: 0x1791)) {
            try image.validate(forBootloaderPID: 0x1791, board: board)
        }
        #expect(throws: FirmwareImageError.unknownBootloader(0x0792)) { try image.validate(forBootloaderPID: 0x0792, board: board) }
    }

    @Test func refusesATamperedCRC() throws {
        var data = try Self.image("KlgM7-40xJ7M").data
        data[data.count - 1] ^= 0xFF
        #expect(throws: FirmwareImageError.badCRC(expected: 0x2E4F_09FD, actual: 0xD14F_09FD)) {
            try FirmwareImage(data: data).validate(forBootloaderPID: 0x0791, board: board)
        }
    }

    /// An Oryx dual image (research 02 §8.4) whose final suffix names the GD32 bootloader and whose CRC covers the
    /// whole file: everything else passes, so only the inner STM32 suffix stops it.
    @Test func refusesADualImageOnAGD32Bootloader() throws {
        let stm32 = try Self.image("KlgM7-40xJ7M")
        let dual = FirmwareImage.withSuffix(stm32.data + stm32.payload, vendorID: 0x3297, productID: 0x1791)
        #expect(throws: FirmwareImageError.embeddedSuffix) { try dual.validate(forBootloaderPID: 0x1791, board: board) }
    }

    @Test func refusesAnotherVendor() throws {
        let image = FirmwareImage.withSuffix(try Self.image("KlgM7-40xJ7M").payload, vendorID: 0x1234, productID: 0x0791)
        #expect(throws: FirmwareImageError.wrongVendor(0x1234)) { try image.validate(forBootloaderPID: 0x0791, board: board) }
    }

    @Test func refusesAPayloadLargerThanTheFlashWindow() throws {
        let limit = Int(board.flashEnd - board.flashStart)
        var payload = try Self.image("KlgM7-40xJ7M").payload
        payload.append(Data(count: limit + 1 - payload.count))
        let image = FirmwareImage.withSuffix(payload, vendorID: 0x3297, productID: 0x0791)
        #expect(throws: FirmwareImageError.tooLarge(bytes: limit + 1, limit: limit)) {
            try image.validate(forBootloaderPID: 0x0791, board: board)
        }
    }

    @Test func refusesAStackPointerOutsideRAM() throws {
        let image = try Self.patched(word: 0, to: 0x3000_0000)
        #expect(throws: FirmwareImageError.badStackPointer(0x3000_0000)) { try image.validate(forBootloaderPID: 0x0791, board: board) }
    }

    /// Even (not Thumb), inside the bootloader, and past the application window.
    @Test(arguments: [0x0800_22BC, 0x0800_0101, 0x0802_0001] as [UInt32])
    func refusesABadResetVector(_ vector: UInt32) throws {
        let image = try Self.patched(word: 4, to: vector)
        #expect(throws: FirmwareImageError.badResetVector(vector)) { try image.validate(forBootloaderPID: 0x0791, board: board) }
    }

    /// The user's build with one little-endian vector-table word replaced, re-suffixed so only that word is wrong.
    private static func patched(word offset: Int, to value: UInt32) throws -> FirmwareImage {
        var payload = try image("KlgM7-40xJ7M").payload
        for i in 0..<4 { payload[offset + i] = UInt8(value >> (8 * i) & 0xFF) }
        return FirmwareImage.withSuffix(payload, vendorID: 0x3297, productID: 0x0791)
    }

    /// Unzips the build's `.bin` into a temporary folder and reads it.
    private static func image(_ build: String) throws -> FirmwareImage {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sextant-bin-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", "-j", Fixtures.examples.appending(path: "sources/\(build)-source.zip").path, "*.bin", "-d", folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        try #require(unzip.terminationStatus == 0)
        let bins = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter {
            $0.pathExtension == "bin"
        }
        try #require(bins.count == 1)
        return FirmwareImage(data: try Data(contentsOf: bins[0]))
    }
}
