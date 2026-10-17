import Foundation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

@testable import SextantUpdates

/// Contract tests for the release feed against a `URLProtocol` stub (never the real network). Serialized because the
/// stub's reply and log are shared by every session that uses it.
@Suite(.serialized)
struct GitHubReleaseFeedTests {
    let feed: GitHubReleaseFeed

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStub.self]
        feed = GitHubReleaseFeed(session: URLSession(configuration: configuration), version: "0.2.0")
        ReleaseStub.state.withLock { $0 = ReleaseStub.State() }
    }

    /// GitHub's reply, trimmed to what matters, for `tag`.
    static func reply(tag: String = "v0.3.0", draft: Bool = false, prerelease: Bool = false, assets: String? = nil) -> Data {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assetList =
            assets ?? """
                [{"name": "Sextant-\(version).zip.sha256", "browser_download_url": "https://github.com/afrase/Sextant/releases/download/\(tag)/Sextant-\(version).zip.sha256"},
                 {"name": "Sextant-\(version).zip", "browser_download_url": "https://github.com/afrase/Sextant/releases/download/\(tag)/Sextant-\(version).zip"}]
                """
        return Data(
            """
            {"tag_name": "\(tag)", "html_url": "https://github.com/afrase/Sextant/releases/tag/\(tag)", "draft": \(draft),
             "prerelease": \(prerelease), "published_at": "2026-10-20T12:00:00Z", "name": "\(tag)", "body": "Notes",
             "assets": \(assetList)}
            """.utf8)
    }

    @Test func asksGitHubForTheLatestReleaseWithoutCredentials() async throws {
        ReleaseStub.reply(.http(200, Self.reply()))
        let release = try await feed.latest()
        #expect(release.version == AppVersion(major: 0, minor: 3, patch: 0))
        #expect(release.page.absoluteString == "https://github.com/afrase/Sextant/releases/tag/v0.3.0")
        #expect(release.download.absoluteString == "https://github.com/afrase/Sextant/releases/download/v0.3.0/Sextant-0.3.0.zip")
        #expect(release.published == Date(timeIntervalSince1970: 1_792_497_600))

        let sent = try #require(ReleaseStub.sent.first)
        #expect(ReleaseStub.sent.count == 1)
        #expect(sent.httpMethod == "GET")
        #expect(sent.url?.absoluteString == "https://api.github.com/repos/afrase/Sextant/releases/latest")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == "Sextant/0.2.0 (macOS; update check)")
    }

    @Test func withoutTheZipTheDownloadIsTheReleasePage() async throws {
        ReleaseStub.reply(.http(200, Self.reply(assets: "[]")))
        let release = try await feed.latest()
        #expect(release.download == release.page)
    }

    @Test func linksOffGitHubAreRefused() async throws {
        let elsewhere = """
            [{"name": "Sextant-0.3.0.zip", "browser_download_url": "https://example.com/Sextant-0.3.0.zip"}]
            """
        ReleaseStub.reply(.http(200, Self.reply(assets: elsewhere)))
        #expect(try await feed.latest().download.host() == "github.com", "the release page instead")

        var page = String(bytes: Self.reply(), encoding: .utf8) ?? ""
        page = page.replacingOccurrences(of: "\"html_url\": \"https://github.com", with: "\"html_url\": \"http://github.com")
        ReleaseStub.reply(.http(200, Data(page.utf8)))
        await #expect(throws: UpdateCheckError.self) { try await feed.latest() }
    }

    @Test(arguments: [
        (Self.reply(draft: true), "a draft"), (Self.reply(prerelease: true), "a pre-release"),
        (Self.reply(tag: "nightly"), "not a version"), (Data("<html>".utf8), "not JSON"),
    ])
    func repliesThatArentAReleaseAreUnreadable(_ data: Data, _ why: String) async {
        ReleaseStub.reply(.http(200, data))
        await #expect(throws: UpdateCheckError.self, "\(why)") { try await feed.latest() }
        do throws(UpdateCheckError) {
            _ = try await feed.latest()
        } catch {
            if case .unreadable = error {} else { Issue.record("\(why): \(error)") }
        }
    }

    @Test func offlineAndRateLimitsSaySo() async {
        ReleaseStub.reply(.failure(.notConnectedToInternet))
        await #expect(throws: UpdateCheckError.offline) { try await feed.latest() }
        ReleaseStub.reply(.http(403, Data()))
        await #expect(throws: UpdateCheckError.server("Too many requests; try again later.")) { try await feed.latest() }
        ReleaseStub.reply(.http(404, Data()))
        await #expect(throws: UpdateCheckError.server("HTTP 404")) { try await feed.latest() }
    }
}

/// Answers every request with the configured reply and records what was sent.
final class ReleaseStub: URLProtocol {
    enum Reply: Sendable {
        case http(Int, Data)
        case failure(URLError.Code)
    }

    struct State: Sendable {
        var reply = Reply.http(200, Data())
        var sent: [URLRequest] = []
    }

    static let state = Mutex(State())
    static var sent: [URLRequest] { state.withLock { $0.sent } }
    static func reply(_ reply: Reply) { state.withLock { $0.reply = reply } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let reply = Self.state.withLock { state in
            state.sent.append(request)
            return state.reply
        }
        switch reply {
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .http(status, data):
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}
