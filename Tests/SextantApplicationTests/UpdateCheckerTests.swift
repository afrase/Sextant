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
        #expect(updates.saved.lastChecked == now.date && saves.values.last?.lastChecked == now.date)

        feed.set(.success(.release("0.2.0")))
        await updates.check()
        #expect(updates.status == .upToDate && updates.notice == nil)
        feed.set(.success(.release("0.1.1")))
        await updates.check()
        #expect(updates.status == .upToDate)
    }

    @Test func aPrereleaseBuildIsOfferedItsRelease() async {
        let updates = checker(current: "1.0.0-beta.2")
        feed.set(.success(.release("1.0.0")))
        await updates.check()
        #expect(updates.notice == .release("1.0.0"))
    }

    @Test func aDismissedVersionIsntOfferedAgainButANewerOneIs() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0")))
        await updates.check()
        updates.dismiss()
        #expect(updates.notice == nil && updates.status == .available(.release("0.3.0")), "a check still finds it")
        #expect(saves.values.last?.dismissed == AppVersion("0.3.0"))

        let relaunched = checker(saved: updates.saved)
        await relaunched.check()
        #expect(relaunched.notice == nil, "dismissed across launches")
        feed.set(.success(.release("0.3.1")))
        await relaunched.check()
        #expect(relaunched.notice == .release("0.3.1"))
    }

    @Test func aCheckThatFailsSaysWhyAndKeepsTheLastAnswerDate() async {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let updates = checker(saved: .init(lastChecked: earlier))
        feed.set(.failure(.offline))
        await updates.check()
        #expect(updates.status == .failed(.offline))
        #expect(updates.saved.lastChecked == earlier, "only an answer counts as checked")
    }

    @Test func aBuildWithoutAVersionShowsTheLatestButNeverChecksByItself() async {
        let updates = checker(current: nil)
        feed.set(.success(.release("0.3.0")))
        #expect(!updates.isDue)
        await updates.check()
        #expect(updates.status == .unknownVersion(.release("0.3.0")) && updates.notice == nil)
    }

    // MARK: Checking by itself

    @Test func checksALittleAfterLaunchThenOnceADay() async {
        let updates = checker()
        feed.set(.success(.release("0.2.0")))
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay - .seconds(1))
        #expect(feed.calls == 0, "launching never waits on the network")
        await clock.advance(by: .seconds(1))
        #expect(await eventually { feed.calls == 1 && updates.status == .upToDate })

        // Hourly looks, but no check until a day has passed since the answer.
        for _ in 0..<23 {
            now.date += 3600
            await clock.advance(by: UpdateChecker.poll)
        }
        #expect(feed.calls == 1)
        now.date += 3600
        await clock.advance(by: UpdateChecker.poll)
        #expect(await eventually { feed.calls == 2 })
    }

    @Test func aRecentAnswerFromAnEarlierLaunchWaitsItsDay() async {
        let updates = checker(saved: .init(lastChecked: now.date - 3600))
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay)
        await clock.advance(by: UpdateChecker.poll * 22)
        #expect(feed.calls == 0)
        now.date += 23 * 3600
        await clock.advance(by: UpdateChecker.poll)
        #expect(await eventually { feed.calls == 1 })
    }

    @Test func turnedOffItDoesntCheckByItselfButTheUserCanAsk() async {
        let updates = checker(saved: .init(checksAutomatically: false))
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay + UpdateChecker.poll * 48)
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

    /// A failure on its own keeps what an earlier check found, so the notice doesn't vanish while offline.
    @Test func aFailedCheckByItselfKeepsWhatWasFound() async {
        let updates = checker()
        feed.set(.success(.release("0.3.0")))
        await updates.check()
        feed.set(.failure(.offline))
        now.date += 25 * 3600
        updates.start()
        defer { updates.stop() }
        await clock.advance(by: UpdateChecker.launchDelay)
        #expect(await eventually { feed.calls == 2 })
        #expect(updates.notice == .release("0.3.0"))
    }
}

extension AppRelease {
    static func release(_ version: String) -> AppRelease {
        let page = URL(string: "https://github.com/afrase/Sextant/releases/tag/v\(version)")!
        return AppRelease(version: AppVersion(version)!, page: page, download: page)
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

/// Answers with the result it is given and counts the asks.
final class FakeReleaseFeed: ReleaseFeed {
    private let state = Mutex<(result: Result<AppRelease, UpdateCheckError>, calls: Int)>((.failure(.offline), 0))
    var calls: Int { state.withLock { $0.calls } }
    func set(_ result: Result<AppRelease, UpdateCheckError>) { state.withLock { $0.result = result } }

    func latest() async throws(UpdateCheckError) -> AppRelease {
        try state.withLock {
            $0.calls += 1
            return $0.result
        }.get()
    }
}
