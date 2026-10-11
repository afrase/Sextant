import Clocks
import CryptoKit
import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantDevice

/// A DfuSe bootloader in memory: records every request and erases and writes a model of the flash window.
final class FakeDfuSe: USBControlTransport, Sendable {
    enum Request: Equatable, Sendable {
        case out(request: UInt8, value: UInt16, data: [UInt8])
        case `in`(request: UInt8, length: Int)
    }

    struct Behaviour: Sendable {
        var startsInError = false
        var clearFixesError = true
        /// GETSTATUS replies that say DNBUSY after each download.
        var busyPolls = 1
        var pollTimeoutMS = 20
        /// The download (1-based) after which the bootloader reports dfuERROR.
        var errorAfterDownload: Int?
        var alwaysBusy = false
        /// Resets on the leave request, failing it and every request after.
        var dropsOffOnLeave = false
    }

    private struct State: Sendable {
        var requests: [Request] = []
        var flash = [UInt8](repeating: 0, count: Int(BoardDefinition.voyager.flashEnd - BoardDefinition.voyager.flashStart))
        var pointer: UInt32 = 0
        var busy = 0
        var error = false
        var downloads = 0
        var wroteUnerased = false
        var gone = false
    }

    let behaviour: Behaviour
    private let state: Locked<State>

    init(_ behaviour: Behaviour = Behaviour()) {
        self.behaviour = behaviour
        state = Locked(State(error: behaviour.startsInError))
    }

    var requests: [Request] { state.value.requests }
    var flash: [UInt8] { state.value.flash }
    var wroteUnerased: Bool { state.value.wroteUnerased }
    var downloads: [(value: UInt16, data: [UInt8])] {
        requests.compactMap { if case let .out(1, value, data) = $0 { (value, data) } else { nil } }
    }

    func controlOut(request: UInt8, value: UInt16, data: [UInt8]) throws(FlashError) {
        if behaviour.dropsOffOnLeave, request == 1, value == 2, data.isEmpty { state.withLock { $0.gone = true } }
        guard !state.value.gone else { throw .transfer("Device gone") }
        state.withLock { s in
            s.requests.append(.out(request: request, value: value, data: data))
            if request == 4, behaviour.clearFixesError { s.error = false }
            guard request == 1 else { return }
            s.downloads += 1
            s.busy = behaviour.busyPolls
            if s.downloads == behaviour.errorAfterDownload { s.error = true }
            let start = BoardDefinition.voyager.flashStart
            // Out-of-window or malformed requests are only recorded, so a broken guard fails a test instead of trapping.
            if value == 0 {
                guard data.count == 5 else { return }
                let address = UInt32(data[1]) | UInt32(data[2]) << 8 | UInt32(data[3]) << 16 | UInt32(data[4]) << 24
                guard (start..<BoardDefinition.voyager.flashEnd).contains(address) else { return }
                if data[0] == 0x21 {
                    s.pointer = address
                } else {
                    let page = Int(address - start) / 2048 * 2048
                    s.flash.replaceSubrange(page..<page + 2048, with: repeatElement(0xFF, count: 2048))
                }
            } else {
                guard s.pointer >= start, Int(s.pointer - start) + data.count <= s.flash.count else { return }
                let offset = Int(s.pointer - start)
                if s.flash[offset..<offset + data.count].contains(where: { $0 != 0xFF }) { s.wroteUnerased = true }
                s.flash.replaceSubrange(offset..<offset + data.count, with: data)
            }
        }
    }

    func controlIn(request: UInt8, value: UInt16, length: Int) throws(FlashError) -> [UInt8] {
        guard !state.value.gone else { throw .transfer("Device gone") }
        return state.withLock { s in
            s.requests.append(.in(request: request, length: length))
            let busy = behaviour.alwaysBusy || s.busy > 0
            s.busy -= 1
            let bState: UInt8 = s.error ? 10 : busy ? 4 : s.downloads == 0 ? 2 : 5
            let poll = behaviour.pollTimeoutMS
            return [s.error ? 0x0A : 0, UInt8(poll & 0xFF), UInt8(poll >> 8 & 0xFF), UInt8(poll >> 16 & 0xFF), bState, 0]
        }
    }

    func close() {}
}

/// A valid image (vector table inside RAM and the application window) with its md5.
func testImage(payload size: Int, productID: UInt16 = 0x0791) -> (image: FirmwareImage, md5: String) {
    var payload = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 7) })
    for i in 0..<4 {
        payload[i] = UInt8(0x2000_0400 >> (8 * i) & 0xFF)
        payload[4 + i] = UInt8(0x0800_22BD >> (8 * i) & 0xFF)
    }
    let image = FirmwareImage.withSuffix(payload, vendorID: 0x3297, productID: productID)
    return (image, Insecure.MD5.hash(data: image.data).map { String(format: "%02x", $0) }.joined())
}

/// A DfuSe command: the command byte and a little-endian address.
func command(_ code: UInt8, _ address: UInt32) -> [UInt8] {
    [code, UInt8(address & 0xFF), UInt8(address >> 8 & 0xFF), UInt8(address >> 16 & 0xFF), UInt8(address >> 24)]
}

struct DFUFlasherTests {
    let start = BoardDefinition.voyager.flashStart
    let getStatus = FakeDfuSe.Request.in(request: 3, length: 6)
    let opened = Locked(false)
    let progress = Locked<[FlashProgress]>([])

    /// `cancelOnAttempt` cancels the calling task from inside that open attempt; `onProgress` sees every report.
    func flash(
        _ image: FirmwareImage, md5: String, productID: UInt16 = 0x0791, on fake: FakeDfuSe, notFoundFirst: Int = 0,
        cancelOnAttempt: Int? = nil, onProgress: @escaping @Sendable (FlashProgress) -> Void = { _ in }
    ) async throws(FlashError) {
        let opened = opened, progress = progress
        let attempts = Locked(0)
        let flasher = DFUFlasher(clock: ImmediateClock()) { _, _ throws(FlashError) in
            attempts.value += 1
            if attempts.value == cancelOnAttempt { withUnsafeCurrentTask { $0?.cancel() } }
            guard attempts.value > notFoundFirst else { throw .deviceNotFound }
            opened.value = true
            return fake
        }
        let device = BootloaderDevice(id: 1, productID: productID, kind: .stm32, version: 0x0100)
        try await flasher.flash(image, md5: md5, to: device, board: .voyager) {
            progress.value.append($0)
            onProgress($0)
        }
    }

    @Test func erasesWritesAndLeaves() async throws {
        let fake = FakeDfuSe()
        let (image, md5) = testImage(payload: 5_000)
        try await flash(image, md5: md5, on: fake)

        // 5,000 bytes round up to 3 pages, plus one.
        let commands = fake.downloads.filter { $0.value == 0 }.map(\.data)
        #expect(
            commands == [
                command(0x41, start), command(0x41, start + 0x800), command(0x41, start + 0x1000), command(0x41, start + 0x1800),
                command(0x21, start), command(0x21, start + 0x800), command(0x21, start + 0x1000), command(0x21, start),
            ])
        #expect(fake.downloads.filter { $0.value == 2 }.map(\.data.count) == [2048, 2048, 904, 0])
        #expect(fake.requests.first == getStatus && fake.requests.last == getStatus)
        #expect(Data(fake.flash.prefix(5_000)) == image.payload)
        #expect(!fake.wroteUnerased)
        #expect(
            progress.value == [
                FlashProgress(phase: .erasing, done: 1, total: 4), FlashProgress(phase: .erasing, done: 2, total: 4),
                FlashProgress(phase: .erasing, done: 3, total: 4), FlashProgress(phase: .erasing, done: 4, total: 4),
                FlashProgress(phase: .writing, done: 2048, total: 5_000), FlashProgress(phase: .writing, done: 4096, total: 5_000),
                FlashProgress(phase: .writing, done: 5_000, total: 5_000), FlashProgress(phase: .leaving, done: 0, total: 1),
            ])
    }

    /// The interface appears a little after the device: retried for a second, then given up.
    @Test func waitsForTheInterfaceAfterAttach() async throws {
        let (image, md5) = testImage(payload: 5_000)
        try await flash(image, md5: md5, on: FakeDfuSe(), notFoundFirst: 3)
        #expect(opened.value)
        await #expect(throws: FlashError.deviceNotFound) { try await flash(image, md5: md5, on: FakeDfuSe(), notFoundFirst: 10) }
    }

    /// Cancelled while waiting for the interface: the wait stops and nothing reaches the keyboard.
    @Test func cancellingWhileWaitingForTheInterfaceSendsNothing() async {
        let fake = FakeDfuSe()
        let (image, md5) = testImage(payload: 5_000)
        // In a child task: cancelling the test's own task would end the test as cancelled.
        await #expect(throws: FlashError.transfer("Canceled")) {
            try await Task { try await flash(image, md5: md5, on: fake, notFoundFirst: 3, cancelOnAttempt: 1) }.value
        }
        #expect(!opened.value)
        #expect(fake.requests.isEmpty)
    }

    /// Cancelled after the first erase: stopping would leave the keyboard without firmware, so the flash finishes.
    @Test func cancellingAfterTheFirstEraseStillFinishesTheFlash() async throws {
        let fake = FakeDfuSe()
        let (image, md5) = testImage(payload: 5_000)
        let caller = Locked<Task<Void, any Error>?>(nil)
        let (started, start) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in started {}  // until `caller` holds this task
            try await flash(image, md5: md5, on: fake) {
                if $0 == FlashProgress(phase: .erasing, done: 1, total: 4) { caller.value?.cancel() }
            }
        }
        caller.value = task
        start.finish()
        try await task.value
        #expect(task.isCancelled)
        #expect(Data(fake.flash.prefix(5_000)) == image.payload)
    }

    @Test func aBootloaderThatResetsOnLeaveStillCountsAsFlashed() async throws {
        let fake = FakeDfuSe(.init(dropsOffOnLeave: true))
        let (image, md5) = testImage(payload: 5_000)
        try await flash(image, md5: md5, on: fake)
        #expect(Data(fake.flash.prefix(5_000)) == image.payload)
    }

    @Test func aFullWindowImageErasesUpToTheEndAndNoFurther() async throws {
        let fake = FakeDfuSe()
        let window = Int(BoardDefinition.voyager.flashEnd - start)
        let (image, md5) = testImage(payload: window)
        try await flash(image, md5: md5.uppercased(), on: fake)
        let erased = fake.downloads.filter { $0.value == 0 && $0.data[0] == 0x41 }.map(\.data)
        #expect(erased.count == window / 2048)
        #expect(erased.last == command(0x41, BoardDefinition.voyager.flashEnd - 2048))
        #expect(Data(fake.flash) == image.payload)
    }

    @Test func refusesAMismatchedChecksumBeforeOpening() async {
        let (image, _) = testImage(payload: 5_000)
        await #expect(throws: FlashError.checksumMismatch) {
            try await flash(image, md5: String(repeating: "0", count: 32), on: FakeDfuSe())
        }
        #expect(!opened.value)
    }

    @Test func refusesASingleSTM32ImageOnAGD32Bootloader() async {
        let (image, md5) = testImage(payload: 5_000)
        await #expect(throws: FlashError.imageRejected(.wrongProduct(image: 0x0791, bootloader: 0x1791))) {
            try await flash(image, md5: md5, productID: 0x1791, on: FakeDfuSe())
        }
        #expect(!opened.value)
    }

    /// An Oryx dual image whose final suffix names the GD32 bootloader is refused before the device is opened.
    @Test func refusesADualImageOnAGD32Bootloader() async {
        let (stm32, _) = testImage(payload: 5_000)
        let dual = FirmwareImage.withSuffix(stm32.data + stm32.payload, vendorID: 0x3297, productID: 0x1791)
        await #expect(throws: FlashError.imageRejected(.embeddedSuffix)) {
            try await flash(dual, md5: "", productID: 0x1791, on: FakeDfuSe())
        }
        #expect(!opened.value)
    }

    @Test func refusesAnUnknownBootloader() async {
        let (image, md5) = testImage(payload: 5_000, productID: 0x0792)
        await #expect(throws: FlashError.imageRejected(.unknownBootloader(0x0792))) {
            try await flash(image, md5: md5, productID: 0x0792, on: FakeDfuSe())
        }
        #expect(!opened.value)
    }

    @Test func refusesEveryDownloadOutsideTheRules() throws {
        let fake = FakeDfuSe()
        var dfu = DfuSe(transport: fake, board: .voyager, clock: ImmediateClock())
        let end = BoardDefinition.voyager.flashEnd
        let refused: [(value: UInt16, data: [UInt8])] = [
            (0, [0x41]),  // MASS_ERASE
            (0, command(0x41, 0x0800_0000)), (0, command(0x41, start - 1)), (0, command(0x41, end)), (0, command(0x21, 0xFFFF_FFFF)),
            (0, command(0x41, start + 1)),  // an erase must name a page start
            (0, command(0x92, start)),  // any other DfuSe command
            (0, [0x21, 0x00, 0x20, 0x00]),  // short
            (2, [0x00]),  // a block before any SET_ADDRESS
            (1, [0x00]),  // another block number
        ]
        for (value, data) in refused {
            #expect(throws: FlashError.self, "\(value) \(data)") { try dfu.download(value: value, data) }
        }
        #expect(fake.requests.isEmpty)

        try dfu.download(value: 0, command(0x21, start))
        #expect(throws: FlashError.self) { try dfu.download(value: 2, [UInt8](repeating: 0, count: 2049)) }  // over a page
        try dfu.download(value: 0, command(0x21, end - 1024))
        #expect(throws: FlashError.self) { try dfu.download(value: 2, [UInt8](repeating: 0, count: 2048)) }  // crosses the end
        try dfu.download(value: 2, [UInt8](repeating: 0, count: 1024))
        #expect(fake.downloads.map(\.data.count) == [5, 5, 1024])
    }

    @Test func dfuErrorStopsTheFlash() async {
        let fake = FakeDfuSe(.init(errorAfterDownload: 3))
        let (image, md5) = testImage(payload: 5_000)
        await #expect(throws: FlashError.dfuError(status: 0x0A, address: start + 0x1000)) { try await flash(image, md5: md5, on: fake) }
        #expect(fake.downloads.count == 3)
        #expect(fake.requests.last == getStatus)
    }

    @Test func clearsAnErrorOnceAtTheStart() async throws {
        let fake = FakeDfuSe(.init(startsInError: true))
        let (image, md5) = testImage(payload: 5_000)
        try await flash(image, md5: md5, on: fake)
        let clear = FakeDfuSe.Request.out(request: 4, value: 0, data: [])
        #expect(Array(fake.requests.prefix(3)) == [getStatus, clear, getStatus])
        #expect(fake.requests.filter { $0 == clear }.count == 1)
    }

    @Test func failsWhenTheErrorDoesNotClear() async {
        let fake = FakeDfuSe(.init(startsInError: true, clearFixesError: false))
        let (image, md5) = testImage(payload: 5_000)
        await #expect(throws: FlashError.dfuError(status: 0x0A, address: start)) { try await flash(image, md5: md5, on: fake) }
        #expect(fake.requests == [getStatus, .out(request: 4, value: 0, data: []), getStatus])
    }

    @Test func capsTheNumberOfPolls() async {
        let fake = FakeDfuSe(.init(pollTimeoutMS: 0, alwaysBusy: true))
        let (image, md5) = testImage(payload: 5_000)
        await #expect(throws: FlashError.timeout(address: start)) { try await flash(image, md5: md5, on: fake) }
        #expect(fake.requests.count == 1 + 1 + DfuSe<ImmediateClock<Duration>>.maxPolls)
    }

    /// bwPollTimeout of 4.6 hours is slept as 2 s, and a wait gives up after 5 s: polls at 0, 2, 4 and 6 s.
    @Test func capsEachSleepAndTheTimeAWaitTakes() async {
        let fake = FakeDfuSe(.init(pollTimeoutMS: 0xFF_FFFF, alwaysBusy: true))
        let (image, md5) = testImage(payload: 5_000)
        await #expect(throws: FlashError.timeout(address: start)) { try await flash(image, md5: md5, on: fake) }
        #expect(fake.requests.count == 1 + 1 + 4)
    }
}
