import Foundation
import Testing

@testable import SextantUpdates

/// What decides whether a build can update itself, and the move from ADR 0063's settings (ADR 0070).
struct SparkleUpdaterTests {
    /// A 32-byte EdDSA public key, base64; any 32 bytes do here.
    let key = Data(repeating: 7, count: 32).base64EncodedString()

    func info(
        feed: String? = "https://github.com/afrase/Sextant/releases/latest/download/appcast.xml", key: String? = nil,
        version: String? = "1.2.3"
    )
        -> [String: Any]
    {
        var info: [String: Any] = [:]
        info["SUFeedURL"] = feed
        info["SUPublicEDKey"] = key ?? self.key
        info["CFBundleShortVersionString"] = version
        return info
    }

    @Test func aBundledBuildWithAFeedAndAKeyCanUpdate() {
        #expect(SparkleConfiguration.canUpdate(info: info(), bundlePath: "/Applications/Sextant.app"))
    }

    @Test func swiftRunAndIncompleteBundlesCant() {
        #expect(!SparkleConfiguration.canUpdate(info: info(), bundlePath: "/Users/me/Sextant/.build/debug"), "swift run")
        #expect(!SparkleConfiguration.canUpdate(info: info(feed: nil), bundlePath: "/Applications/Sextant.app"))
        #expect(
            !SparkleConfiguration.canUpdate(info: info(feed: "http://example.com/appcast.xml"), bundlePath: "/Applications/Sextant.app"))
        #expect(!SparkleConfiguration.canUpdate(info: info(key: ""), bundlePath: "/Applications/Sextant.app"), "no key yet")
        #expect(!SparkleConfiguration.canUpdate(info: info(key: "bm90IGEga2V5"), bundlePath: "/Applications/Sextant.app"), "not 32 bytes")
        #expect(!SparkleConfiguration.canUpdate(info: info(version: nil), bundlePath: "/Applications/Sextant.app"))
    }

    @Test func turningChecksOffCarriesOverAndTheOldKeysGo() throws {
        let suite = "SparkleUpdaterTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "checksForUpdates")
        defaults.set(Date(), forKey: "updatesLastChecked")
        defaults.set("0.3.0", forKey: "updatesDismissedVersion")
        UpdateDefaults.migrate(defaults)
        #expect(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
        for key in UpdateDefaults.legacy { #expect(defaults.object(forKey: key) == nil, "\(key) removed") }
    }

    @Test func checksLeftOnLeaveSparklesDefault() throws {
        let suite = "SparkleUpdaterTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "checksForUpdates")
        UpdateDefaults.migrate(defaults)
        #expect(defaults.object(forKey: "SUEnableAutomaticChecks") == nil, "Info.plist's default (on) applies")
        #expect(defaults.object(forKey: "checksForUpdates") == nil)
    }
}
