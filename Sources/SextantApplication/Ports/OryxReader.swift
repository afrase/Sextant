import Foundation
import SextantDomain

/// Errors from reading Oryx (spec §8.1 copy).
public enum OryxError: Error, Equatable, Sendable, LocalizedError {
    /// No network, DNS failure or timeout.
    case offline
    /// Private, deleted or never existed.
    case notFound
    /// The layout is for another board (geometry name, e.g. "moonlander").
    case otherBoard(String)
    /// Oryx answered with something Sextant can't read.
    case unreadable(String)
    /// A downloaded firmware didn't match the md5 Oryx published.
    case checksumMismatch
    /// Oryx reported an error (HTTP status or GraphQL error message).
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .offline: String(localized: "Sextant couldn't reach Oryx. Check your connection and try again.")
        case .notFound: String(localized: "This layout is private or doesn't exist. Sextant can only import public layouts.")
        case let .otherBoard(board):
            String(localized: "This is a \(board.capitalized) layout. Sextant supports the ZSA Voyager for now.")
        case let .unreadable(detail): String(localized: "Oryx sent something Sextant couldn't read. \(detail)")
        case .checksumMismatch:
            String(localized: "Oryx's firmware didn't match its checksum, so Sextant didn't keep it. The layout imported fine.")
        case let .server(detail): String(localized: "Oryx reported a problem: \(detail)")
        }
    }
}

/// Read-only access to Oryx's public GraphQL API and firmware downloads (decision 2). Never logs in, never writes.
public protocol OryxReader: Sendable {
    /// The layout at `reference` (its revision, or the latest when it names none).
    func layout(_ reference: OryxReference) async throws(OryxError) -> KeyboardLayout
    /// Oryx's compiled firmware for a revision, verified against `expectedMD5` before it is returned.
    func firmware(revisionID: String, expectedMD5: String) async throws(OryxError) -> Data
}
