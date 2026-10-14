import Foundation
import SextantDomain
import Testing

@testable import SextantApplication

/// How the keyboard gets its own lighting back (ADR 0051), on FakeKeyboardLink: nothing here writes to a keyboard.
extension LightingPreviewTests {
    @Test(arguments: ["toggle off", "sleep", "quit", "Live View off"])
    func everyReleaseSendsLightingOffLast(_ path: String) async throws {
        _ = try await previewing()
        switch path {
        case "toggle off": preview.release(for: window)
        case "sleep": preview.releaseAll()
        case "quit":
            preview.releaseAll()  // as the app delegate does
            Task { await live.releaseLightsAndWait() }
        default: live.stopLive()
        }
        let commands = await sent(6)
        #expect(commands.count == 6 && commands.last == .lighting(false))
        #expect(await eventually { !preview.isHeld(by: window) }, "the switch turns off")
        if path == "Live View off" {
            #expect(!live.isLive && !live.canSend, "Live View reads as off at once")
            #expect(link.isOpen(0), "the session lasts until the keyboard has its lights back")
        }
        // The keyboard's reply ends the quit's and Live View's waits.
        link.send(.lighting(false))
        if path == "Live View off" {
            #expect(await eventually { !link.isOpen(0) })
            #expect(live.connection == .liveOff(.voyager(serial: "KlgM7/40xJ7M")))
        }
        preview.release(for: window)
        preview.releaseAll()
        await live.releaseLightsAndWait()
        try await Task.sleep(for: .milliseconds(10))
        #expect(link.commands[0].count == 6, "released once")
    }

    @Test func aReleaseBehindQueuedFramesStillComesLast() async throws {
        try #require(await paired())
        try preview.claim(for: window, title: "Layout")
        preview.show(Self.frame, for: window, title: "Layout")
        var changed = Self.frame
        changed[7] = Self.green
        preview.show(changed, for: window, title: "Layout")
        preview.release(for: window)
        await liveClock.advance(by: .seconds(1))
        try await Task.sleep(for: .milliseconds(10))
        #expect(await sent(6).last == .lighting(false))
        #expect(link.commands[0].count == 6, "the waiting frame is dropped, not sent after the release")
    }

    @Test func theQuitWaitEndsOnTheReplyOrOnceTheQueueHadTime() async throws {
        _ = try await previewing()
        var done = false
        Task {
            await live.releaseLightsAndWait()
            done = true
        }
        _ = await sent(6)
        try await Task.sleep(for: .milliseconds(10))
        #expect(!done)
        link.send(.lighting(false))
        #expect(await eventually { done }, "the keyboard's 08 00")

        // A whole frame queued (53 writes, about 640 ms), then quit at once with no reply.
        try preview.claim(for: window, title: "Layout")
        preview.show((0..<52).map { HexColor(red: Double($0) / 52, green: 0, blue: 0) }, for: window, title: "Layout")
        _ = await sent(59)
        done = false
        Task {
            await live.releaseLightsAndWait()
            done = true
        }
        #expect(await sent(60).last == .lighting(false))
        await liveClock.advance(by: .milliseconds(900))
        try await Task.sleep(for: .milliseconds(10))
        #expect(!done, "the queue ahead of the release gets its time, then half a second for the reply")
        #expect(
            await eventually {
                await liveClock.advance(by: .milliseconds(100))
                return done
            }, "no reply: the wait is bounded")
    }

    /// The `08 00` answering one release must not cancel the next: the lights were taken again in between.
    @Test(arguments: ["switch off", "quit"])
    func aLateReplyToAnEarlierReleaseLeavesTheNextOneDue(_ path: String) async throws {
        _ = try await previewing()
        preview.release(for: window)
        try preview.claim(for: window, title: "Layout")
        preview.show(Self.frame, for: window, title: "Layout")
        #expect(await sent(11).dropFirst(6).first == .lighting(true))
        link.send(.lighting(false))  // the reply to the first release
        try await Task.sleep(for: .milliseconds(10))
        if path == "quit" { Task { await live.releaseLightsAndWait() } } else { preview.release(for: window) }
        #expect(await sent(12).last == .lighting(false))
    }

    /// The preview's release went out and is still queued when Live View is turned off or Sextant quits: both wait for it,
    /// since ending the session drops it.
    @Test(arguments: ["Live View off", "quit"])
    func aReleaseStillQueuedIsWaitedFor(_ path: String) async throws {
        _ = try await previewing()
        preview.release(for: window)
        var done = false
        if path == "quit" {
            Task {
                await live.releaseLightsAndWait()
                done = true
            }
        } else {
            live.stopLive()
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(!done && link.isOpen(0))
        #expect(link.commands[0].count == 6, "the release isn't sent twice")
        link.send(.lighting(false))
        #expect(await eventually { path == "quit" ? done : !link.isOpen(0) })
    }

    @Test func liveViewOffThenOnAgainEndsOn() async throws {
        _ = try await previewing()
        live.stopLive()
        live.startLive()
        #expect(live.isLive)
        try await Task.sleep(for: .milliseconds(10))
        #expect(link.sessionCount == 1, "the session giving the lights back isn't cut off")
        link.send(.lighting(false))
        #expect(await eventually { link.sessionCount == 2 && !link.isOpen(0) }, "then it pairs again")
        #expect(live.isLive)
    }

    @Test func aClaimWhileLiveViewGivesTheLightsBackIsRefused() async throws {
        _ = try await previewing()
        live.stopLive()
        #expect(await eventually { !preview.isHeld(by: window) })
        #expect(throws: LightingPreviewRefusal.liveOff) { try preview.claim(for: window, title: "Layout") }
        link.send(.lighting(false))
        #expect(await eventually { !link.isOpen(0) })
        #expect(link.commands[0].count == 6)
    }

    @Test func aDisconnectSendsNothingAndAReconnectResendsTheWholeFrame() async throws {
        let first = try await previewing()
        link.send(.ended(.io("unplugged")))
        #expect(await eventually { !live.canSend })
        #expect(preview.isHeld(by: window), "the switch stays on")
        #expect(
            await eventually {
                await liveClock.advance(by: .milliseconds(100))
                return link.sessionCount == 2
            }, "reconnected after the backoff")
        link.send(.layer(0))
        _ = await eventually {
            await liveClock.advance(by: .milliseconds(17))
            return live.canSend
        }
        #expect(await sent(5, session: 1) == first)
        #expect(link.commands[0].count == 5, "no 05 00 to a session that ended")
        live.stopLive()
        #expect(await sent(6, session: 1).last == .lighting(false), "the new session took the lights")
    }

    @Test func anotherHostsReleaseMakesTheNextFrameTakeTheLightsAgain() async throws {
        _ = try await previewing()
        link.send(.lighting(false))
        try await Task.sleep(for: .milliseconds(20))
        var frame = Self.frame
        frame[20] = Self.green
        preview.show(frame, for: window, title: "Layout")
        let commands = await sent(11)
        #expect(commands.count == 11, "05 01, 09 and four others")
        #expect(commands.dropFirst(5).prefix(2) == [.lighting(true), .setAllLEDs(red: 0, green: 0, blue: 255)])
    }

    /// Secure input hides presses, not the keyboard's replies.
    @Test func repliesArriveDuringSecureInput() async throws {
        _ = try await previewing()
        secureInput.isOn = true
        link.send(.lighting(false))  // another host's release
        try await Task.sleep(for: .milliseconds(20))
        var frame = Self.frame
        frame[20] = Self.green
        preview.show(frame, for: window, title: "Layout")
        #expect(await sent(6).dropFirst(5).first == .lighting(true), "the lights are taken again in full")
        await liveClock.advance(by: .seconds(1))
        live.stopLive()
        link.send(.lighting(false))
        #expect(await eventually { !link.isOpen(0) }, "the reply ends the wait")
    }
}

extension LightingPreviewTests {
    /// While the switch is on, the inspector says why nothing shows: Keymapp holding the keyboard, not "connecting".
    @Test func theKeyboardsStateSaysWhyAPreviewShowsNothing() async throws {
        _ = try await previewing()
        #expect(preview.keyboardRefusal == nil)
        link.send(.ended(.heldByAnotherApp))
        #expect(await eventually { preview.keyboardRefusal == .heldByAnotherApp })
        #expect(preview.isHeld(by: window), "the switch stays on")
    }
}
