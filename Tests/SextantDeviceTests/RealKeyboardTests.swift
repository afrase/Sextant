import Foundation
import SextantApplication
import SextantDevice
import SextantDomain
import Testing

/// The live writes on a real, plugged-in Voyager, through the app's own path (USB presence, the raw-HID link,
/// `LiveSession`). Off unless `SEXTANT_REAL_KEYBOARD=1`, because it writes to the keyboard: pairing, one layer move and
/// back, and an RGB preview that gives the lights back. Run it only with the user's OK (AGENTS.md); it leaves the
/// keyboard on the layer it found and with its own lighting.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SEXTANT_REAL_KEYBOARD"] == "1"), .serialized)
@MainActor
struct RealKeyboardTests {
    @Test func movesTheLayerAndPreviewsLightsThenPutsBothBack() async throws {
        let live = LiveSession(
            watcher: IOKitDeviceWatcher(), link: RawHIDLink(), followsOnConnect: { false }, secureInputProbe: { false })
        live.start()
        defer { live.stop() }
        try await until("the keyboard shows up") { if case .liveOff = live.connection { true } else { false } }

        var replies: [LiveActivity] = []
        let feed = live.activity()
        let listener = Task { @MainActor in for await event in feed { replies.append(event) } }
        defer { listener.cancel() }

        live.startLive()
        try await until("Live View pairs and reports a layer") { live.canSend && live.activeLayer != nil }
        let start = try #require(live.activeLayer)
        let other = start == 1 ? 0 : 1
        print("paired: serial \(live.firmwareSerial ?? "?"), protocol \(live.protocolVersion.map(String.init) ?? "?"), layer \(start)")

        try live.send(.moveToLayer(other))
        try await until("the keyboard reports layer \(other)") { live.activeLayer == other }
        try live.send(.moveToLayer(start))
        try await until("the keyboard is back on layer \(start)") { live.activeLayer == start }
        print("layer moves: \(start) → \(other) → \(start)")

        // Claimed first, as LightingPreview does: only `05 01` gets the keyboard's `08 01`.
        try live.send(.lighting(true))
        try await until("the keyboard acknowledges the takeover") { replies.contains(.lighting(true)) }
        try live.send(.setAllLEDs(red: 0, green: 60, blue: 160))
        try await Task.sleep(for: .seconds(1.5))
        try live.send(.setLED(index: 0, red: 255, green: 120, blue: 0))
        try await Task.sleep(for: .seconds(1.5))
        await live.releaseLightsAndWait()
        try await until("the keyboard acknowledges the lights back") { replies.contains(.lighting(false)) }
        print("lighting replies: \(replies.filter { if case .lighting = $0 { true } else { false } })")

        live.stopLive()
        #expect(!replies.contains { if case .refused = $0 { true } else { false } }, "\(replies)")
    }

    private func until(_ what: String, timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting until \(what)")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
