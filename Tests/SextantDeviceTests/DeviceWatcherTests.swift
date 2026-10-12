import SextantApplication
import SextantDomain
import Synchronization
import Testing

@testable import SextantDevice

/// Presence notifications from a script instead of IOKit.
final class FakePresence: USBPresenceSource {
    let script: [USBPresence]
    let finishes: Bool
    let requested = Locked<Set<UInt16>>([])
    let terminated = Locked(false)

    init(_ script: [USBPresence], finishes: Bool = true) {
        self.script = script
        self.finishes = finishes
    }

    func presence(vendorID: UInt16, productIDs: Set<UInt16>) -> AsyncStream<USBPresence> {
        requested.value = productIDs
        return AsyncStream { continuation in
            script.forEach { continuation.yield($0) }
            continuation.onTermination = { _ in self.terminated.value = true }
            if finishes { continuation.finish() }
        }
    }
}

struct DeviceWatcherTests {
    @Test func mapsPresenceToKeyboardsAndBootloaders() async {
        let source = FakePresence([
            .matched(USBDeviceRecord(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M", bcdDevice: 0x0001)),
            .matched(USBDeviceRecord(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M", bcdDevice: 0x0001)),
            .matched(USBDeviceRecord(id: 2, productID: 0x0791, serial: nil, bcdDevice: 0x0102)),
            .matched(USBDeviceRecord(id: 3, productID: 0x1791, serial: nil, bcdDevice: 0x0200)),
            .matched(USBDeviceRecord(id: 4, productID: 0x9999, serial: nil, bcdDevice: 0)),
            .terminated(id: 4),
            .terminated(id: 9),
            .terminated(id: 1),
            .terminated(id: 2),
        ])
        var events: [DeviceEvent] = []
        for await event in IOKitDeviceWatcher(source: source).events(for: .voyager) { events.append(event) }
        #expect(
            events == [
                .attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M"))),
                .attached(.bootloader(BootloaderDevice(id: 2, productID: 0x0791, kind: .stm32, version: 0x0102))),
                .attached(.bootloader(BootloaderDevice(id: 3, productID: 0x1791, kind: .gd32, version: 0x0200))),
                .detached(id: 1),
                .detached(id: 2),
            ])
        #expect(source.requested.value == [0x1977, 0x1978, 0x0791, 0x1791])
    }

    @Test func cancellingTheConsumerReleasesTheSource() async throws {
        let source = FakePresence([.matched(USBDeviceRecord(id: 1, productID: 0x1977, serial: nil, bcdDevice: 1))], finishes: false)
        let received = Locked(0)
        let consumer = Task {
            for await _ in IOKitDeviceWatcher(source: source).events(for: .voyager) { received.value += 1 }
        }
        try await waitUntil { received.value == 1 }
        consumer.cancel()
        try await waitUntil { source.terminated.value }
    }
}

/// A value shared between a test and the fakes it drives.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>
    init(_ value: Value) { mutex = Mutex(value) }
    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
    func withLock<R: Sendable>(_ body: (inout Value) -> R) -> R { mutex.withLock { body(&$0) } }
}

/// Polls `condition` for up to five seconds: a loaded CI runner can take more than one.
func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<5_000 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out")
}
