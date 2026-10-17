import Clocks
import Foundation
import SextantDomain
import Synchronization
import Testing

@testable import SextantApplication

/// Telling the user about a newer Sextant (ADR 0063), against a fake feed and a test clock: nothing reaches the network.
@MainActor
struct UpdateCheckerTests {
    let feed = FakeReleaseFeed()
    let clock = TestClock()
    let now = Now()
    let saves = Recorded<UpdateChecker.Saved>()

    func checker(current: String? = "0.2.0", saved: UpdateChecker.Saved = .init()) -> UpdateChecker {
        UpdateChecker(
            current: current.flatMap(AppVersion.init), feed: feed, saved: saved, clock: clock, now: { [now] in now.date },
            persist: { [saves] in saves.append($0) })
    }

    @Test func aNewerReleaseIsOfferedAndAnOlderOrEqualOneIsnt() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0")))
        await updates.check()
        #expect(updates.status == .available(.release("0.3.0")) && updates.notice == .release("0.3.0"))
        #expect(updates.saved.lastChecked == now.date && saves.values.last?.found == .release("0.3.0"))

        feed.set(.success(.release("0.2.0")))
        await updates.check()
        #expect(updates.status == .upToDate && updates.notice == nil && updates.saved.found == nil)
        feed.set(.success(.release("0.1.1")))
        await updates.check()
        #expect(updates.status == .upToDate)
    }

    /// The release workflow attaches the zip after publishing; until then the release isn't out.
    @Test func aReleaseWithoutItsZipIsntOfferedYet() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0", zip: false)))
        await updates.check()
        #expect(updates.status == .upToDate && updates.notice == nil)
    }

    @Test func aPrereleaseBuildIsOfferedItsRelease() async {
        let updates = checker(current: "1.0.0-beta.2")
        feed.set(.success(.release("1.0.0")))
        await updates.check()
        #expect(updates.notice == .release("1.0.0"))
    }

    /// A relaunch within the day doesn't check, but still offers what the last answer found.
    @Test func whatWasFoundIsOfferedAgainAfterARelaunch() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0")))
        await updates.check()
        let relaunched = checker(saved: updates.saved)
        #expect(relaunched.notice == .release("0.3.0") && relaunched.status == .available(.release("0.3.0")))
        #expect(!relaunched.isDue)
        #expect(checker(current: "0.3.0", saved: updates.saved).notice == nil, "not once this build is that version")
    }

    @Test func aSkippedVersionIsntOfferedAgainButANewerOneIs() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0")))
        await updates.check()
        updates.dismiss()
        #expect(updates.notice == nil && updates.available == .release("0.3.0"), "a check still finds it")
        #expect(saves.values.last?.dismissed == AppVersion("0.3.0"))

        let relaunched = checker(saved: updates.saved)
        #expect(relaunched.notice == nil, "skipped across launches")
        feed.set(.success(.release("0.3.1")))
        await relaunched.check()
        #expect(relaunched.notice == .release("0.3.1"))
    }

    /// Offline, a check says why, and what an earlier answer found stays offered.
    @Test func aCheckThatFailsSaysWhyAndKeepsWhatWasFound() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0")))
        await updates.check()
        let answered = updates.saved.lastChecked
        now.date += 600
        feed.set(.failure(.offline))
        await updates.check()
        #expect(updates.status == .failed(.offline))
        #expect(updates.notice == .release("0.3.0"))
        #expect(updates.saved.lastChecked == answered, "only an answer counts as checked")
    }

    @Test func aBuildWithoutAVersionShowsTheLatestButNeverChecksByItself() async {
        let updates = checker(current: nil)
        feed.set(.success(.release("0.3.0")))
        #expect(!updates.isDue)
        await updates.check()
        #expect(updates.status == .unknownVersion(.release("0.3.0")) && updates.notice == nil)
    }

    /// Asked while one runs, the user gets that one's answer, not a second request.
    @Test func aCheckAskedForDuringOneWaitsForIt() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0")))
        feed.hold()
        let first = Task { await updates.check() }
        #expect(await eventually { feed.calls == 1 })
        let second = Task { await updates.check() }
        #expect(await eventually { updates.status == .checking })
        feed.release()
        await first.value
        await second.value
        #expect(feed.calls == 1 && updates.notice == .release("0.3.0"))
    }

    // MARK: Checking by itself

    @Test func checksALittleAfterLaunchThenOnceADay() async {
        let updates = checker()
        feed.set(.success(.release("0.2.0")))
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay - .seconds(1))
        await clock.advance(by: .seconds(1))
        #expect(await eventually { updates.looks == 1 && feed.calls == 1 && updates.status == .upToDate })

        // Hourly looks, but no check until a day has passed since the answer.
        for look in 2...24 {
            now.date += 3600
            await clock.advance(by: UpdateChecker.poll)
            #expect(await eventually { updates.looks == look })
        }
        #expect(feed.calls == 1)
        now.date += 3600
        await clock.advance(by: UpdateChecker.poll)
        #expect(await eventually { updates.looks == 25 && feed.calls == 2 })
    }

    @Test func nothingIsAskedBeforeTheLaunchDelay() async {
        let updates = checker()
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay - .seconds(1))
        await clock.advance(by: .seconds(1))
        #expect(await eventually { updates.looks == 1 })
        // The first look is the first ask: none before it.
        #expect(feed.calls == 1)
    }

    @Test func aRecentAnswerFromAnEarlierLaunchWaitsItsDay() async {
        let updates = checker(saved: .init(lastChecked: now.date - 3600))
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay)
        for look in 2...23 {
            await clock.advance(by: UpdateChecker.poll)
            #expect(await eventually { updates.looks == look })
        }
        #expect(feed.calls == 0)
        now.date += 23 * 3600
        await clock.advance(by: UpdateChecker.poll)
        #expect(await eventually { feed.calls == 1 })
    }

    /// A clock set back past the last answer counts as due, rather than waiting until it catches up.
    @Test func aClockSetBackChecks() async {
        let updates = checker(saved: .init(lastChecked: now.date + 3 * 24 * 3600))
        #expect(updates.isDue)
    }

    @Test func turnedOffItDoesntCheckByItselfButTheUserCanAsk() async {
        let updates = checker(saved: .init(checksAutomatically: false))
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay)
        for look in 2...48 {
            await clock.advance(by: UpdateChecker.poll)
            #expect(await eventually { updates.looks == look })
        }
        #expect(feed.calls == 0)
        await updates.check()
        #expect(feed.calls == 1)
    }

    @Test func turningItOnChecksWhenDue() async {
        let updates = checker(saved: .init(checksAutomatically: false))
        updates.checksAutomatically = true
        #expect(saves.values.last?.checksAutomatically == true)
        #expect(await eventually { feed.calls == 1 })
    }
}

extension AppRelease {
    /// A published release, its zip attached unless `zip` is false.
    static func release(_ version: String, zip: Bool = true) -> AppRelease {
        let page = URL(string: "https://github.com/afrase/Sextant/releases/tag/v\(version)")!
        let download = URL(string: "https://github.com/afrase/Sextant/releases/download/v\(version)/Sextant-\(version).zip")!
        return AppRelease(version: AppVersion(version)!, page: page, download: zip ? download : nil)
    }
}

/// A clock face the tests move by hand.
final class Now: Sendable {
    private let value = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    var date: Date {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

/// Answers with the result it is given and counts the asks; `hold()` keeps answers back until `release()`.
final class FakeReleaseFeed: ReleaseFeed {
    private let state = Mutex<(result: Result<AppRelease, UpdateCheckError>, calls: Int, held: Bool)>((.failure(.offline), 0, false))
    var calls: Int { state.withLock { $0.calls } }
    func set(_ result: Result<AppRelease, UpdateCheckError>) { state.withLock { $0.result = result } }
    func hold() { state.withLock { $0.held = true } }
    func release() { state.withLock { $0.held = false } }

    func latest() async throws(UpdateCheckError) -> AppRelease {
        state.withLock { $0.calls += 1 }
        while state.withLock({ $0.held }) { try? await Task.sleep(for: .milliseconds(2)) }
        return try state.withLock { $0.result }.get()
    }
}
