import CryptoKit
import Foundation
import IOKit
import IOUSBHost
import SextantApplication
import SextantDomain
import os

/// Class requests on EP0 to the DFU interface (interface 0). Calls are synchronous and time out.
protocol USBControlTransport {
    /// Host-to-device (bmRequestType 0x21).
    func controlOut(request: UInt8, value: UInt16, data: [UInt8]) throws(FlashError)
    /// Device-to-host (bmRequestType 0xA1); returns the bytes received, at most `length`.
    func controlIn(request: UInt8, value: UInt16, length: Int) throws(FlashError) -> [UInt8]
    func close()
}

/// Flashes ZSA's Ignition bootloader with DFU 1.1 + ST DfuSe (research 02 §8.5, §10.3). Writes to the keyboard,
/// so the composition root wires it only after the user approves (ADR 0012).
///
/// Before the first transfer it re-validates the image for the connected bootloader and checks its md5; every
/// download is then checked against the flash window, and MASS_ERASE can't be expressed (AGENTS.md, ADR 0013).
public actor DFUFlasher: Flasher {
    private let queue = DispatchSerialQueue(label: "com.sextant.device.dfu")
    private let clock: any Clock<Duration>
    private let open: @Sendable (BootloaderDevice, BoardDefinition) throws(FlashError) -> any USBControlTransport
    private var flashing = false
    private let log = Logger(subsystem: "com.sextant.app", category: "device")

    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    public init() {
        self.init(clock: ContinuousClock()) { device, board throws(FlashError) in try IOUSBHostTransport(device: device, board: board) }
    }

    init(
        clock: any Clock<Duration>,
        open: @escaping @Sendable (BootloaderDevice, BoardDefinition) throws(FlashError) -> any USBControlTransport
    ) {
        self.clock = clock
        self.open = open
    }

    public func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) {
        guard !flashing else { throw .deviceBusy }
        // Also refuses an unknown bootloader and every image for a GD32 bootloader (0x1791) for now.
        do { try image.validate(forBootloaderPID: device.productID, board: board) } catch { throw .imageRejected(error) }
        let digest = Insecure.MD5.hash(data: image.data).map { String(format: "%02x", $0) }.joined()
        guard digest == md5.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { throw .checksumMismatch }

        guard !Task.isCancelled else { throw .transfer("Canceled") }

        flashing = true
        defer { flashing = false }
        let transport = try await openWhenReady(device, board: board)
        guard !Task.isCancelled else {
            transport.close()
            throw .transfer("Canceled")
        }
        // Until the first erase a cancel leaves the keyboard waiting in flash mode. After it, stopping leaves the
        // keyboard without firmware, so the write runs in its own task and finishes even if the caller is cancelled.
        let result = await Task { () async -> Result<Void, FlashError> in
            do throws(FlashError) {
                try await self.write(image.payload, with: transport, board: board, clock: self.clock, progress: progress)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        if case let .failure(error) = result { log.error("Flash failed: \(String(describing: error), privacy: .public)") }
        try result.get()
    }

    private func write(
        _ payload: Data, with transport: any USBControlTransport, board: BoardDefinition, clock: some Clock<Duration>,
        progress: @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) {
        defer { transport.close() }
        var dfu = DfuSe(transport: transport, board: board, clock: clock)
        try await dfu.write(payload, progress: progress)
    }

    /// The bootloader's interface 0 is published a little after the device the watcher reports (zapp waits 500 ms
    /// after hotplug), so a missing interface is retried for up to a second.
    private func openWhenReady(
        _ device: BootloaderDevice, board: BoardDefinition
    ) async throws(FlashError) -> sending any USBControlTransport {
        for _ in 1..<10 {
            do {
                return try open(device, board)
            } catch .deviceNotFound {
                do { try await clock.sleep(for: .milliseconds(100)) } catch { throw .transfer("Canceled") }
            }
        }
        return try open(device, board)
    }
}

/// DFU 1.1 and ST DfuSe (AN3156) requests, with the flasher guards on every download.
/// The async methods are `nonisolated(nonsending)` so their synchronous transfers block the flasher's queue, not the pool.
struct DfuSe<C: Clock<Duration>> {
    static var dnload: UInt8 { 1 }
    static var getStatus: UInt8 { 3 }
    static var clearStatus: UInt8 { 4 }
    static var setAddress: UInt8 { 0x21 }
    static var erasePage: UInt8 { 0x41 }
    static var stateBusy: UInt8 { 4 }
    static var stateError: UInt8 { 10 }
    /// Polls per wait, the time a wait may take, and the longest single sleep. zapp and Oryx loop forever or
    /// carry on silently; Sextant fails instead (research 02 verification O1).
    static var maxPolls: Int { 1_000 }
    static var maxWait: Duration { .seconds(5) }
    static var maxPollInterval: Duration { .seconds(2) }

    let transport: any USBControlTransport
    let board: BoardDefinition
    let clock: C
    /// The DfuSe address pointer, as the last SET_ADDRESS left it.
    private(set) var pointer: UInt32?

    init(transport: any USBControlTransport, board: BoardDefinition, clock: C) {
        self.transport = transport
        self.board = board
        self.clock = clock
    }

    private var window: Range<UInt32> { board.flashStart..<board.flashEnd }

    /// Erases from `flashStart` over the payload rounded up to a page plus one page (capped at `flashEnd`), writes
    /// it in page-sized blocks, then leaves the bootloader (02 §8.5, Sextant's choices).
    nonisolated(nonsending) mutating func write(_ payload: Data, progress: @Sendable (FlashProgress) -> Void) async throws(FlashError) {
        try clearErrorOnce()
        let page = board.flashPageSize
        let eraseEnd = min(board.flashStart + UInt32((payload.count + page - 1) / page * page + page), board.flashEnd)
        let pages = Array(stride(from: board.flashStart, to: eraseEnd, by: page))
        for (i, address) in pages.enumerated() {
            try await command(Self.erasePage, at: address)
            progress(FlashProgress(phase: .erasing, done: i + 1, total: pages.count))
        }
        for offset in stride(from: 0, to: payload.count, by: page) {
            let address = board.flashStart + UInt32(offset)
            let block = Array(payload.dropFirst(offset).prefix(page))
            try await command(Self.setAddress, at: address)
            try download(value: 2, block)
            try await waitWhileBusy(at: address)
            progress(FlashProgress(phase: .writing, done: offset + block.count, total: payload.count))
        }
        progress(FlashProgress(phase: .leaving, done: 0, total: 1))
        // zapp's settle time before leaving; the "zapp form" leave is SET_ADDRESS(start) + an empty block.
        try? await clock.sleep(for: .seconds(1))
        try await command(Self.setAddress, at: board.flashStart)
        // The bootloader resets into the new firmware here and may drop off the bus mid-request (02 §8.5 step 8).
        try? download(value: 2, [])
        _ = try? status()
    }

    /// GETSTATUS, and one CLRSTATUS when the bootloader starts in dfuERROR. Still dfuERROR after that is failure.
    func clearErrorOnce() throws(FlashError) {
        guard try status().state == Self.stateError else { return }
        try transport.controlOut(request: Self.clearStatus, value: 0, data: [])
        let after = try status()
        if after.state == Self.stateError { throw .dfuError(status: after.status, address: board.flashStart) }
    }

    /// A DfuSe command (SET_ADDRESS or ERASE_PAGE), then a wait while the bootloader is busy.
    nonisolated(nonsending) mutating func command(_ code: UInt8, at address: UInt32) async throws(FlashError) {
        try download(
            value: 0, [code, UInt8(address & 0xFF), UInt8(address >> 8 & 0xFF), UInt8(address >> 16 & 0xFF), UInt8(address >> 24)])
        try await waitWhileBusy(at: address)
    }

    /// Every DNLOAD passes through here. A command must be exactly SET_ADDRESS or ERASE_PAGE plus an address inside
    /// the flash window, so a bare 0x41 (MASS_ERASE) can't be sent; a data block must land inside the window.
    mutating func download(value: UInt16, _ data: [UInt8]) throws(FlashError) {
        switch value {
        case 0:
            guard data.count == 5, data[0] == Self.setAddress || data[0] == Self.erasePage else {
                throw .transfer("Refused DfuSe command \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            }
            let address = UInt32(data[1]) | UInt32(data[2]) << 8 | UInt32(data[3]) << 16 | UInt32(data[4]) << 24
            guard window.contains(address), data[0] == Self.setAddress || address.isMultiple(of: UInt32(board.flashPageSize)) else {
                throw .transfer("Refused address \(String(format: "0x%08X", address))")
            }
            if data[0] == Self.setAddress { pointer = address }
        case 2:
            guard let pointer, data.count <= board.flashPageSize, UInt64(pointer) + UInt64(data.count) <= UInt64(board.flashEnd) else {
                throw .transfer("Refused a \(data.count)-byte block at \(pointer.map { String(format: "0x%08X", $0) } ?? "no address")")
            }
        default:
            throw .transfer("Refused DNLOAD block \(value)")
        }
        try transport.controlOut(request: Self.dnload, value: value, data: data)
    }

    /// GETSTATUS until the bootloader leaves DNBUSY, sleeping its bwPollTimeout (1 ms to 2 s) between polls.
    nonisolated(nonsending) func waitWhileBusy(at address: UInt32) async throws(FlashError) {
        let deadline = clock.now.advanced(by: Self.maxWait)
        for _ in 0..<Self.maxPolls {
            let s = try status()
            if s.state == Self.stateError { throw .dfuError(status: s.status, address: address) }
            guard s.state == Self.stateBusy else { return }
            guard clock.now < deadline else { break }
            do {
                try await clock.sleep(for: min(max(s.pollTimeout, .milliseconds(1)), Self.maxPollInterval))
            } catch {
                throw .transfer("Canceled")
            }
        }
        throw .timeout(address: address)
    }

    /// DFU_GETSTATUS: bStatus, bwPollTimeout (LE24, ms), bState, iString.
    func status() throws(FlashError) -> (status: UInt8, pollTimeout: Duration, state: UInt8) {
        let bytes = try transport.controlIn(request: Self.getStatus, value: 0, length: 6)
        guard bytes.count == 6 else { throw .transfer("Short DFU status (\(bytes.count) bytes)") }
        return (bytes[0], .milliseconds(Int(bytes[1]) | Int(bytes[2]) << 8 | Int(bytes[3]) << 16), bytes[4])
    }
}

// MARK: - IOUSBHost

/// EP0 requests through `IOUSBHostInterface` (interface 0 of the bootloader), synchronous with a timeout.
private final class IOUSBHostTransport: USBControlTransport {
    /// zapp's per-transfer timeout.
    private static let timeout: TimeInterval = 5
    private let interface: IOUSBHostInterface

    init(device: BootloaderDevice, board: BoardDefinition) throws(FlashError) {
        let usb = IORegistryEntryIDMatching(device.id).map { IOServiceGetMatchingService(kIOMainPortDefault, $0) } ?? 0
        guard usb != 0 else { throw .deviceNotFound }
        defer { IOObjectRelease(usb) }
        // The image was validated for `device.productID`; make sure that is the device being opened.
        guard Self.number(usb, "idVendor") == Int(board.vendorID), Self.number(usb, "idProduct") == Int(device.productID) else {
            throw .deviceNotFound
        }
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(usb, kIOServicePlane, &children) == KERN_SUCCESS else { throw .deviceNotFound }
        defer { IOObjectRelease(children) }
        var found: IOUSBHostInterface?
        while found == nil, case let child = IOIteratorNext(children), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOUSBHostInterface") != 0, Self.number(child, "bInterfaceNumber") == 0 else { continue }
            do {
                found = try IOUSBHostInterface(__ioService: child, options: [], queue: nil, interestHandler: nil)
            } catch {
                // Exclusive access: another app (Keymapp, a browser) holds the interface.
                throw (error as NSError).code == Int(kIOReturnExclusiveAccess) ? .deviceBusy : .transfer(error.localizedDescription)
            }
        }
        guard let found else { throw .deviceNotFound }
        interface = found
    }

    func controlOut(request: UInt8, value: UInt16, data: [UInt8]) throws(FlashError) {
        let buffer = NSMutableData(bytes: data, length: data.count)
        _ = try send(
            IOUSBDeviceRequest(bmRequestType: 0x21, bRequest: request, wValue: value, wIndex: 0, wLength: UInt16(data.count)), buffer)
    }

    func controlIn(request: UInt8, value: UInt16, length: Int) throws(FlashError) -> [UInt8] {
        let buffer = NSMutableData(length: length) ?? NSMutableData()
        let count = try send(
            IOUSBDeviceRequest(bmRequestType: 0xA1, bRequest: request, wValue: value, wIndex: 0, wLength: UInt16(length)), buffer)
        return [UInt8]((buffer as Data).prefix(count))
    }

    func close() { interface.destroy() }

    private static func number(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }

    private func send(_ request: IOUSBDeviceRequest, _ data: NSMutableData) throws(FlashError) -> Int {
        var transferred = 0
        do {
            try interface.__send(
                request, data: data.length == 0 ? nil : data, bytesTransferred: &transferred, completionTimeout: Self.timeout)
        } catch {
            throw .transfer(error.localizedDescription)
        }
        return transferred
    }
}
