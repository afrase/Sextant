import Clocks
import SextantApplication
import SextantDomain
import Testing

@testable import SextantDevice

/// The lighting preview's reports as RawHIDLink writes them (ADR 0051), on FakeHID: nothing here touches a keyboard.
@MainActor
struct LightingPreviewWireTests {
    /// A Voyager already plugged in.
    private struct OneKeyboard: DeviceWatcher {
        func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
            AsyncStream { $0.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: "KlgM7/40xJ7M")))) }
        }
    }

    final class Window {}

    /// Polls `condition` on the main actor, where the live session lives, for up to five seconds.
    private func settled(_ condition: () -> Bool) async throws {
        for _ in 0..<5_000 where !condition() { try await Task.sleep(for: .milliseconds(1)) }
        #expect(condition(), "timed out")
    }

    @Test func takesFillsSetsAndGivesTheLightsBackInOrder() async throws {
        // Replies by write: the version, nothing for the serial query, then pairing; the keyboard acknowledges 05 01.
        let hid = FakeHID(
            script: [
                [report(0xFE, 0x05, 0xFE)], [], [report(0x04, 0xFE), report(0x05, 0x00, 0xFE)], [report(0x08, 0x01)],
            ])
        let live = LiveSession(
            watcher: OneKeyboard(), link: RawHIDLink(clock: ImmediateClock(), makeTransport: { _, _ in hid }), secureInputProbe: { false })
        let preview = LightingPreview(live: live, clock: ImmediateClock())
        let window = Window()
        live.start()
        preview.start()
        defer { live.stop() }
        try await settled { live.connection != .noKeyboard }
        live.startLive()
        try await settled { live.canSend }

        let blue = HexColor(red: 0, green: 0, blue: 1)
        var frame: [HexColor?] = Array(repeating: blue, count: 52)
        frame[3] = HexColor(red: 1, green: 0, blue: 0)
        frame[51] = nil
        try preview.claim(for: window, title: "Layout")
        preview.show(frame, for: window, title: "Layout")
        try await settled { hid.sent.value.count == 7 }
        preview.release(for: window)
        try await settled { hid.sent.value.count == 8 }

        func padded(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: 32 - bytes.count) }
        #expect(
            Array(hid.sent.value.dropFirst(3))
                == [
                    [0x05, 0x01], [0x09, 0x00, 0x00, 0xFF], [0x06, 0x03, 0xFF, 0x00, 0x00], [0x06, 0x33, 0x00, 0x00, 0x00],
                    [0x05, 0x00],
                ].map(padded))
        #expect(hid.sent.value.allSatisfy { ![0x07, 0x08, 0x0A].contains($0[0]) }, "never status LEDs or brightness steps")
    }
}
