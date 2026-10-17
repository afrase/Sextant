import SextantDomain
import Testing

/// Sextant's versions as release tags and the bundle name them (ADR 0063).
struct AppVersionTests {
    @Test func readsTagsAndBundleVersions() {
        #expect(AppVersion("v0.2.0") == AppVersion(major: 0, minor: 2, patch: 0))
        #expect(AppVersion("0.2.0") == AppVersion(major: 0, minor: 2, patch: 0))
        #expect(AppVersion("1.2") == AppVersion(major: 1, minor: 2, patch: 0))
        #expect(AppVersion("v1.0.0-beta.1") == AppVersion(major: 1, minor: 0, patch: 0, prerelease: ["beta", "1"]))
        #expect(AppVersion("1.0.0+build.7") == AppVersion(major: 1, minor: 0, patch: 0))
        #expect(AppVersion("v1.0.0-beta.1")?.description == "1.0.0-beta.1")
    }

    @Test(arguments: [
        "", "v", "1.", "1..2", "1.2.3.4", "a.b.c", "1.2.x", "1.2.3-", "1.2.3-beta..1", "１.２.３", "nightly", "-1.0.0", "1.0.0-01",
        "1.0.0-bêta",
    ])
    func refusesWhatIsntAVersion(_ text: String) {
        #expect(AppVersion(text) == nil)
    }

    /// semver.org's own example order, plus the cases releases meet.
    @Test func ordersBySemanticVersioningPrecedence() throws {
        let ordered = try [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1",
            "1.0.0", "1.0.1", "1.1.0", "1.10.0", "2.0.0",
        ].map { try #require(AppVersion($0)) }
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            #expect(a < b, "\(a) < \(b)")
            #expect(!(b < a))
        }
        #expect(!(try #require(AppVersion("0.2.0")) < #require(AppVersion("v0.2.0"))))
    }
}
