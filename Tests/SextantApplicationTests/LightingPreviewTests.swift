import Clocks
import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

/// The keyboard lighting preview (ADR 0051) on FakeDeviceWatcher and FakeKeyboardLink: nothing here writes to a keyboard.
@MainActor
struct LightingPreviewTests {
    let watcher = FakeDeviceWatcher()
    let link = FakeKeyboardLink()
    /// The live session's debounce, reconnect backoff, write estimate (12 ms a write) and release wait.
    let liveClock = TestClock()
    let secureInput = Flag()
    let live: LiveSession
    let preview: LightingPreview
    let window = Owner()
    let other = Owner()

    final class Owner {}

    static let blue = HexColor(red: 0, green: 0, blue: 1)
    static let red = HexColor(red: 1, green: 0, blue: 0)
    static let green = HexColor(red: 0, green: 1, blue: 0)

    init() {
        let secureInput = secureInput
        live = LiveSession(watcher: watcher, link: link, clock: liveClock) { secureInput.isOn }
        preview = LightingPreview(live: live)
        live.start()
        preview.start()
    }

    /// Blue, keys 3 and 10 red, key 51 off.
    static var frame: [HexColor?] {
        var colors: [HexColor?] = Array(repeating: blue, count: 52)
        colors[3] = red
        colors[10] = red
        colors[51] = nil
        return colors
    }

    /// A keyboard plugged in, with Live View on and its session paired.
    func paired() async -> Bool {
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        guard await eventually({ live.connection != .noKeyboard }) else { return false }
        live.startLive()
        guard await eventually({ link.sessionCount == 1 }) else { return false }
        link.send(.layer(0))
        return await eventually {
            await liveClock.advance(by: .milliseconds(17))
            return live.canSend
        }
    }

    /// The commands the newest session received, once there are `count`.
    func sent(_ count: Int, session: Int = 0) async -> [KeyboardCommand] {
        _ = await eventually { (link.commands[safe: session]?.count ?? 0) >= count }
        return link.commands[safe: session] ?? []
    }

    /// Previews `frame` in `window` and lets its first batch be written.
    func previewing(_ frame: [HexColor?] = Self.frame) async throws -> [KeyboardCommand] {
        try #require(await paired())
        try preview.claim(for: window, title: "My MacOS Layout")
        preview.show(frame, for: window, title: "My MacOS Layout")
        let first = await sent(5)
        await liveClock.advance(by: .seconds(1))
        return first
    }

    static func led(_ i: Int, _ c: HexColor?, brightness: Double = 1) -> KeyboardCommand {
        let led = c.map { LEDColor($0, brightness: brightness) } ?? .off
        return .setLED(index: i, red: led.red, green: led.green, blue: led.blue)
    }

    // MARK: Frames

    @Test func theFirstFrameTakesTheLightsFillsThenSetsTheRest() async throws {
        let first = try await previewing()
        #expect(
            first == [
                .lighting(true), .setAllLEDs(red: 0, green: 0, blue: 255), Self.led(3, Self.red), Self.led(10, Self.red),
                Self.led(51, nil),
            ])
    }

    @Test func onePaintedKeySendsOneSetLED() async throws {
        _ = try await previewing()
        var frame = Self.frame
        frame[20] = Self.green
        preview.show(frame, for: window, title: "My MacOS Layout")
        #expect(await sent(6).dropFirst(5) == [Self.led(20, Self.green)])
        preview.show(frame, for: window, title: "My MacOS Layout")
        await liveClock.advance(by: .seconds(1))
        #expect(link.commands[0].count == 6, "an unchanged frame sends nothing")
    }

    @Test func framesWhileABatchIsWrittenWaitAndTheLatestWins() async throws {
        try #require(await paired())
        try preview.claim(for: window, title: "Layout")
        preview.show(Self.frame, for: window, title: "Layout")
        #expect(await sent(5).count == 5)
        var a = Self.frame
        a[5] = Self.green
        preview.show(a, for: window, title: "Layout")
        var b = Self.frame
        b[5] = Self.red
        b[6] = Self.green
        preview.show(b, for: window, title: "Layout")
        await liveClock.advance(by: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(20))
        #expect(link.commands[0].count == 5, "five writes may take 60 ms; the next frame waits for them")
        await liveClock.advance(by: .milliseconds(10))
        #expect(await sent(7).dropFirst(5) == [Self.led(5, Self.red), Self.led(6, Self.green)])
    }

    @Test func manyChangesFillAgainInsteadOfSettingEachLight() {
        let blue = LEDColor(Self.blue)
        let red = LEDColor(Self.red)
        let shown = Array(repeating: blue, count: 52)
        var target = Array(repeating: red, count: 52)
        target[0] = blue
        let commands = LightingPreview.commands(showing: target, over: shown)
        #expect(commands == [.setAllLEDs(red: 255, green: 0, blue: 0), .setLED(index: 0, red: 0, green: 0, blue: 255)])
        #expect(LightingPreview.commands(showing: target, over: target).isEmpty)
    }

    @Test func brightnessScalesOnTheMac() async throws {
        let orange = try #require(HexColor(hex: "#FF8000"))
        try #require(await paired())
        preview.setBrightness(0.5)
        try preview.claim(for: window, title: "Layout")
        preview.show(Array(repeating: orange, count: 52), for: window, title: "Layout")
        #expect(await sent(2) == [.lighting(true), .setAllLEDs(red: 128, green: 64, blue: 0)])
        await liveClock.advance(by: .seconds(1))
        preview.setBrightness(1)
        #expect(await sent(3).last == .setAllLEDs(red: 255, green: 128, blue: 0), "a new brightness fills again, without 05 01")
        preview.setBrightness(0)
        #expect(preview.brightness == LightingPreview.brightnessRange.lowerBound)
    }

    @Test func onlyTheBoardsLightsAreWrittenAndNothingElse() async throws {
        let colors: [HexColor?] = (0..<60).map { HexColor(red: Double($0) / 60, green: 0, blue: 0) }
        try #require(await paired())
        try preview.claim(for: window, title: "Layout")
        preview.show(colors, for: window, title: "Layout")
        let commands = await sent(53)
        #expect(commands.count == 53, "05 01, 09 and 51 others: index 52 on is dropped")
        for command in commands {
            #expect(command.isAllowed(on: .voyager))
            switch command {
            case .lighting(true), .setAllLEDs: break
            case let .setLED(index, _, _, _): #expect((0..<52).contains(index))
            default: Issue.record("\(command) isn't a preview command")
            }
        }
    }

    // MARK: Claims

    @Test func aSecondWindowsClaimIsRefused() async throws {
        _ = try await previewing()
        #expect(throws: LightingPreviewRefusal.previewingElsewhere("My MacOS Layout")) {
            try preview.claim(for: other, title: "Other")
        }
        #expect(preview.refusal(for: other)?.localizedDescription == "Previewing in My MacOS Layout")
        #expect(preview.refusal(for: window) == nil)
        preview.show(Array(repeating: Self.green, count: 52), for: other, title: "Other")
        preview.release(for: other)
        await liveClock.advance(by: .seconds(1))
        #expect(link.commands[0].count == 5, "another window's frames and releases do nothing")
        #expect(preview.isHeld(by: window))
    }

    @Test func nothingIsSentWhenLiveViewIsOff() async {
        #expect(preview.refusal(for: window) == .noKeyboard)
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { live.connection != .noKeyboard })
        #expect(throws: LightingPreviewRefusal.liveOff) { try preview.claim(for: window, title: "Layout") }
        preview.show(Self.frame, for: window, title: "Layout")
        preview.releaseAll()
        await live.releaseLightsAndWait()
        #expect(link.sessionCount == 0 && !preview.isHeld(by: window))
    }

    @Test func aClaimWhileConnectingSendsOncePaired() async throws {
        watcher.attach(.keyboard(.voyager(serial: "KlgM7/40xJ7M")))
        #expect(await eventually { live.connection != .noKeyboard })
        live.startLive()
        #expect(await eventually { link.sessionCount == 1 })
        try preview.claim(for: window, title: "Layout")
        preview.show(Self.frame, for: window, title: "Layout")
        try await Task.sleep(for: .milliseconds(10))
        #expect(link.commands[0].isEmpty, "not paired yet")
        link.send(.layer(0))
        _ = await eventually {
            await liveClock.advance(by: .milliseconds(17))
            return live.canSend
        }
        #expect(await sent(5).first == .lighting(true))
    }

    // MARK: LED colors

    /// The user's Brd+Sys is #42FF00; a painted key keeps its own color; Main has no color, so it is off.
    @Test func ledColorIsTheKeysElseTheLayersElseOff() throws {
        var layout = try KeyboardLayout(oryxJSON: Fixtures.userLayoutData)
        let orange = try #require(HexColor(hex: "#FF9500"))
        layout.layers[2].keys[16].glowColor = orange
        #expect(layout.ledColor(layer: 2, index: 16) == orange)
        #expect(layout.ledColor(layer: 2, index: 17) == HexColor(hex: "#42FF00"))
        #expect(layout.ledColor(layer: 0, index: 17) == nil)
        #expect(layout.ledColor(layer: 3, index: 0) == nil && layout.ledColor(layer: 2, index: 52) == nil)
        #expect(LEDColor(orange) == LEDColor(red: 255, green: 149, blue: 0))
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
