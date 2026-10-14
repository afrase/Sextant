import CryptoKit
import Foundation
import SextantApplication
import SextantDomain
import os

/// Read-only Oryx client (decision 2): the public GraphQL `layout` query and firmware downloads. It never sends
/// credentials and never calls a mutation.
public struct OryxClient: OryxReader {
    /// Oryx's `getLayout`, trimmed to the fields `KeyboardLayout`'s codec reads (research data/oryx-graphql-operations.json, in
    /// the reference folder).
    private static let query = """
        query getLayout($hashId: String!, $revisionId: String!, $geometry: String) {
          layout(hashId: $hashId, geometry: $geometry, revisionId: $revisionId) {
            hashId title geometry
            revision {
              hashId qmkVersion title createdAt md5 config navigators swatch
              combos { keyIndices layerIdx name trigger }
              layers { automouse hashId prevHashId title position color keys }
            }
          }
        }
        """
    private static let userAgent = "Sextant (macOS keyboard configurator; read-only Oryx import)"
    private static let offline: [URLError.Code] = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
        .dataNotAllowed, .internationalRoamingOff,
    ]

    private let session: URLSession
    private let log = Logger(subsystem: "com.sextant.app", category: "oryx")

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func layout(_ reference: OryxReference) async throws(OryxError) -> KeyboardLayout {
        var request = try URLRequest(url: Self.url("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let variables = Body.Variables(
            hashId: reference.layoutID, revisionId: reference.revisionID ?? "latest", geometry: reference.geometry)
        do {
            request.httpBody = try JSONEncoder().encode(Body(variables: variables))
        } catch {
            throw .unreadable(String(describing: error))
        }
        let data = try await send(request)

        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw .unreadable("The reply isn't GraphQL JSON.")
        }
        guard reply.data?.layout != nil else {
            let messages = reply.errors?.map(\.message) ?? []
            log.error("Oryx has no layout \(reference.layoutID, privacy: .public): \(messages.joined(separator: " "), privacy: .public)")
            // A private or missing layout or revision comes back as a null layout (a missing revision says only
            // "Cannot return null…"), or as null data with a NotFound or PrivateLayout error.
            let notFound = ["notfound", "not found", "private"]
            if reply.data != nil || messages.isEmpty
                || messages.contains(where: { m in notFound.contains { m.lowercased().contains($0) } })
            {
                throw .notFound
            }
            throw .server(messages.joined(separator: " "))
        }
        do {
            return try KeyboardLayout(oryxJSON: data)
        } catch OryxDecodingError.unsupportedBoard(let board) {
            throw .otherBoard(board)
        } catch let error as OryxDecodingError {
            throw .unreadable(error.description)
        } catch {
            log.error("Oryx layout didn't decode: \(String(describing: error), privacy: .public)")
            throw .unreadable("The layout data didn't decode.")
        }
    }

    public func firmware(revisionID: String, expectedMD5: String) async throws(OryxError) -> Data {
        // The id goes into a URL path.
        guard !revisionID.isEmpty, revisionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw .unreadable("Unexpected revision id \(revisionID).")
        }
        var request = try URLRequest(url: Self.url("firmware/\(revisionID)"))
        // Oryx rebuilds revisions, so a cached image may no longer match the published md5.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data = try await send(request)
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard md5 == expectedMD5.lowercased() else {
            log.error("Firmware \(revisionID, privacy: .public) has md5 \(md5, privacy: .public), not \(expectedMD5, privacy: .public)")
            throw .checksumMismatch
        }
        return data
    }

    // MARK: HTTP

    private static func url(_ path: String) throws(OryxError) -> URL {
        guard let url = URL(string: "https://oryx.zsa.io/\(path)") else { throw .unreadable("Bad URL path \(path).") }
        return url
    }

    private func send(_ request: URLRequest) async throws(OryxError) -> Data {
        var request = request
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offline.contains(error.code) {
            throw .offline
        } catch {
            throw .server(error.localizedDescription)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw .unreadable("The reply isn't HTTP.") }
        switch status {
        case 200..<300: return data
        case 404: throw .notFound
        default: throw .server("HTTP \(status)")
        }
    }

    private struct Body: Encodable {
        struct Variables: Encodable {
            var hashId: String
            var revisionId: String
            var geometry: String?
        }

        var operationName = "getLayout"
        var query = OryxClient.query
        var variables: Variables
    }

    /// Just enough of a GraphQL reply to tell a layout from a null one and to read the errors.
    private struct Reply: Decodable {
        struct Payload: Decodable { var layout: Present? }
        /// Decodes from any non-null value without reading it.
        struct Present: Decodable { init(from decoder: any Decoder) {} }
        struct Message: Decodable { var message: String }

        var data: Payload?
        var errors: [Message]?
    }
}
