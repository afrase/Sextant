import CryptoKit
import Foundation
import SextantApplication
import SextantDomain
import Synchronization
import Testing

@testable import SextantOryx

/// Contract tests for the Oryx client against a `URLProtocol` stub (never the real network).
/// Serialized because the stub's reply and log are shared by every session that uses it.
@Suite(.serialized)
struct OryxClientTests {
    let client: OryxClient

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        client = OryxClient(session: URLSession(configuration: configuration))
        StubProtocol.state.withLock { $0 = StubProtocol.State() }
    }

    // MARK: Layout

    @Test func asksForTheLayoutReadOnly() async throws {
        StubProtocol.reply(.http(200, try fixture("my-layout-KlgM7-full.json")))
        _ = try await client.layout(#require(OryxReference("https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0")))

        let sent = try #require(StubProtocol.sent.first)
        #expect(StubProtocol.sent.count == 1)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.request.url?.absoluteString == "https://oryx.zsa.io/graphql")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(sent.request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Sextant") == true)
        #expect(sent.request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(body["operationName"] as? String == "getLayout")
        let variables = try #require(body["variables"] as? [String: String])
        #expect(variables == ["hashId": "KlgM7", "revisionId": "40xJ7M", "geometry": "voyager"])
        let query = try #require(body["query"] as? String)
        #expect(query.hasPrefix("query getLayout("))
        #expect(!query.contains("mutation"))
        for field in ["md5", "qmkVersion", "navigators", "swatch", "combos", "layers", "keys", "position"] {
            #expect(query.contains(field), "\(field)")
        }
    }

    @Test func asksForTheLatestRevisionWhenTheReferenceNamesNone() async throws {
        StubProtocol.reply(.http(200, try fixture("my-layout-KlgM7-40xJ7M.json")))
        _ = try await client.layout(OryxReference(layoutID: "KlgM7"))
        let body = try #require(StubProtocol.sent.first?.body)
        let variables = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["variables"] as? [String: String])
        #expect(variables == ["hashId": "KlgM7", "revisionId": "latest"])
    }

    @Test(arguments: ["my-layout-KlgM7-full.json", "voyager-default.json", "voyager-JRGQm.json"])
    func decodesOryxReplies(_ file: String) async throws {
        StubProtocol.reply(.http(200, try fixture(file)))
        let layout = try await client.layout(OryxReference(layoutID: "KlgM7"))
        #expect(layout == (try KeyboardLayout(oryxJSON: fixture(file))))
        #expect(layout.oryx?.md5 != nil)
    }

    @Test(arguments: [
        #"{"data":{"layout":null}}"#,
        #"{"data":{"layout":null},"errors":[{"message":"NotFound"}]}"#,
        #"{"data":null,"errors":[{"message":"PrivateLayout"}]}"#,
    ])
    func aMissingOrPrivateLayoutIsNotFound(_ reply: String) async {
        StubProtocol.reply(.http(200, Data(reply.utf8)))
        await #expect(throws: OryxError.notFound) { try await client.layout(OryxReference(layoutID: "nope1")) }
    }

    @Test func otherGraphQLErrorsAreServerErrors() async {
        StubProtocol.reply(.http(200, Data(#"{"errors":[{"message":"Field 'x' doesn't exist on type 'Layout'"}]}"#.utf8)))
        await #expect(throws: OryxError.server("Field 'x' doesn't exist on type 'Layout'")) {
            try await client.layout(OryxReference(layoutID: "KlgM7"))
        }
    }

    @Test func anotherBoardIsNamed() async throws {
        let moonlander = try #require(String(bytes: fixture("my-layout-KlgM7-40xJ7M.json"), encoding: .utf8))
            .replacingOccurrences(of: #""geometry":"voyager""#, with: #""geometry":"moonlander""#)
        #expect(moonlander.contains("moonlander"))
        StubProtocol.reply(.http(200, Data(moonlander.utf8)))
        await #expect(throws: OryxError.otherBoard("moonlander")) { try await client.layout(OryxReference(layoutID: "KlgM7")) }
    }

    @Test func junkIsUnreadable() async {
        StubProtocol.reply(.http(200, Data("<html>maintenance</html>".utf8)))
        await #expect(throws: OryxError.unreadable("The reply isn't GraphQL JSON.")) {
            try await client.layout(OryxReference(layoutID: "KlgM7"))
        }
        StubProtocol.reply(.http(200, Data(#"{"data":{"layout":{"title":"No revision"}}}"#.utf8)))
        await #expect(throws: OryxError.unreadable(OryxDecodingError.missingRevision.description)) {
            try await client.layout(OryxReference(layoutID: "KlgM7"))
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost])
    func noNetworkIsOffline(_ code: URLError.Code) async {
        StubProtocol.reply(.failure(code))
        await #expect(throws: OryxError.offline) { try await client.layout(OryxReference(layoutID: "KlgM7")) }
    }

    @Test func httpErrorsAreServerErrors() async {
        StubProtocol.reply(.http(500, Data("oops".utf8)))
        await #expect(throws: OryxError.server("HTTP 500")) { try await client.layout(OryxReference(layoutID: "KlgM7")) }
    }

    // MARK: Firmware

    @Test func downloadsFirmwareAndChecksItsMD5() async throws {
        let image = Data((0..<1000).map { UInt8($0 % 251) })
        let md5 = Insecure.MD5.hash(data: image).map { String(format: "%02x", $0) }.joined()
        StubProtocol.reply(.http(200, image))
        #expect(try await client.firmware(revisionID: "40xJ7M", expectedMD5: md5.uppercased()) == image)

        let sent = try #require(StubProtocol.sent.first)
        #expect(sent.request.httpMethod == "GET")
        #expect(sent.request.url?.absoluteString == "https://oryx.zsa.io/firmware/40xJ7M")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Sextant") == true)
    }

    @Test func refusesFirmwareThatDoesNotMatchItsMD5() async {
        StubProtocol.reply(.http(200, Data("tampered".utf8)))
        await #expect(throws: OryxError.checksumMismatch) {
            try await client.firmware(revisionID: "40xJ7M", expectedMD5: "4f0376c0cf280fdc21e3df5b189685e9")
        }
    }

    @Test func missingFirmwareIsNotFound() async {
        StubProtocol.reply(.http(404, Data()))
        await #expect(throws: OryxError.notFound) { try await client.firmware(revisionID: "40xJ7M", expectedMD5: "") }
    }

    @Test func neverPutsAStrangeRevisionIDInTheURL() async {
        for id in ["", "../graphql", "40xJ7M?alt=true", "a/b"] {
            await #expect(throws: OryxError.self) { try await client.firmware(revisionID: id, expectedMD5: "") }
        }
        #expect(StubProtocol.sent.isEmpty)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appending(path: "docs/research/oryx-examples/\(name)"))
    }
}

/// Answers every request with the configured reply and records what was sent.
final class StubProtocol: URLProtocol {
    enum Reply: Sendable {
        case http(Int, Data)
        case failure(URLError.Code)
    }

    struct Sent: Sendable {
        var request: URLRequest
        var body: Data
    }

    struct State: Sendable {
        var reply = Reply.http(200, Data())
        var sent: [Sent] = []
    }

    static let state = Mutex(State())
    static var sent: [Sent] { state.withLock { $0.sent } }
    static func reply(_ reply: Reply) { state.withLock { $0.reply = reply } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let sent = Sent(request: request, body: request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data())
        let reply = Self.state.withLock { state in
            state.sent.append(sent)
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

    /// URLSession hands protocols the body as a stream.
    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
