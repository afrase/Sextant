import Foundation
import SextantApplication
import SextantDomain
import os

/// Sextant's releases on GitHub (ADR 0063): one unauthenticated GET of the repository's latest release, which GitHub
/// never answers with a draft or a pre-release. It sends no credentials and no identifiers beyond the User-Agent GitHub
/// requires, which names Sextant's version.
public struct GitHubReleaseFeed: ReleaseFeed {
    static let endpoint = "https://api.github.com/repos/afrase/Sextant/releases/latest"
    private static let offline: [URLError.Code] = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
        .dataNotAllowed, .internationalRoamingOff,
    ]

    private let session: URLSession
    private let userAgent: String
    private let log = Logger(subsystem: "com.sextant.app", category: "updates")

    /// - Parameter version: the running build's version, for the User-Agent; nil says "unknown".
    public init(session: URLSession = .shared, version: String?) {
        self.session = session
        userAgent = "Sextant/\(version ?? "unknown") (macOS; update check)"
    }

    public func latest() async throws(UpdateCheckError) -> AppRelease {
        guard let url = URL(string: Self.endpoint) else { throw .unreadable("Bad URL.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offline.contains(error.code) {
            throw .offline
        } catch {
            log.error("Update check failed: \(String(describing: error), privacy: .public)")
            throw .server(error.localizedDescription)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .unreadable("The reply isn't HTTP.") }
        guard status == 200 else {
            log.error("Update check got HTTP \(status, privacy: .public)")
            // 403 and 429 are GitHub's rate limit for unauthenticated requests: 60 an hour per address.
            throw .server(status == 403 || status == 429 ? String(localized: "Too many requests; try again later.") : "HTTP \(status)")
        }
        return try Self.release(from: data)
    }

    static func release(from data: Data) throws(UpdateCheckError) -> AppRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release: GitHubRelease
        do {
            release = try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw .unreadable(String(localized: "The release information didn’t decode."))
        }
        guard release.draft != true, release.prerelease != true else {
            throw .unreadable(String(localized: "The latest release is a draft or a pre-release."))
        }
        guard let version = AppVersion(release.tagName) else {
            throw .unreadable(String(localized: "The latest release’s tag, \(release.tagName), isn’t a version."))
        }
        // Only github.com links leave the app: the release page, and the zip the release workflow attaches.
        guard isGitHub(release.htmlURL) else { throw .unreadable(String(localized: "The release page isn’t on GitHub.")) }
        let zip = release.assets?.first { $0.name == "Sextant-\(version).zip" && isGitHub($0.browserDownloadURL) }
        return AppRelease(
            version: version, page: release.htmlURL, download: zip?.browserDownloadURL ?? release.htmlURL,
            published: release.publishedAt)
    }

    private static func isGitHub(_ url: URL) -> Bool { url.scheme == "https" && url.host() == "github.com" }
}

/// The fields Sextant reads from GitHub's release JSON.
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    var tagName: String
    var htmlURL: URL
    var draft: Bool?
    var prerelease: Bool?
    var publishedAt: Date?
    var assets: [Asset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
        case publishedAt = "published_at"
        case assets
    }
}
