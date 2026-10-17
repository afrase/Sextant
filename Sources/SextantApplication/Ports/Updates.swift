import Foundation
import SextantDomain

/// A published Sextant release (ADR 0063).
public struct AppRelease: Codable, Equatable, Sendable {
    public var version: AppVersion
    /// Its release page, with the notes.
    public var page: URL
    /// The zip to download; nil until the release workflow has attached it, and then the release isn't offered yet.
    public var download: URL?
    public var published: Date?

    public init(version: AppVersion, page: URL, download: URL?, published: Date? = nil) {
        self.version = version
        self.page = page
        self.download = download
        self.published = published
    }
}

/// Why checking for an update failed.
public enum UpdateCheckError: Error, Equatable, Sendable, LocalizedError {
    /// No network, DNS failure or timeout.
    case offline
    /// The release feed answered with something Sextant can't read.
    case unreadable(String)
    /// The release feed reported an error (an HTTP status, or a rate limit).
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .offline: String(localized: "Sextant couldn’t reach GitHub to check for updates. Check your connection and try again.")
        case let .unreadable(detail): String(localized: "GitHub sent something Sextant couldn’t read. \(detail)")
        case let .server(detail): String(localized: "GitHub reported a problem: \(detail)")
        }
    }
}

/// Where Sextant's releases are published (ADR 0063). Reads only; nothing is downloaded or installed.
public protocol ReleaseFeed: Sendable {
    /// The newest release, never a draft or a pre-release.
    func latest() async throws(UpdateCheckError) -> AppRelease
}
