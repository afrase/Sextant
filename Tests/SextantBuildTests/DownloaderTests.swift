import Foundation
import Synchronization
import Testing

@testable import SextantBuild

/// URLSessionDownloader against a stub server: large files come in parallel ranges joined in order, and a server that
/// ignores Range still gets the file downloaded whole.
@Suite(.serialized)
struct DownloaderTests {
    @Test(arguments: ["ranges.test", "whole.test"])
    func largeFilesArriveIntact(host: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sextant-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeServer.self]
        let downloader = URLSessionDownloader(parts: 8, rangedFrom: 1000, configuration: configuration)
        let artifact = Artifact(
            name: "blob", url: try #require(URL(string: "https://\(host)/blob")), size: Int64(RangeServer.blob.count), sha256: "")
        let file = folder.appending(path: "blob")
        let last = Mutex<Int64>(0)
        try await downloader.download(artifact, to: file) { bytes in last.withLock { $0 = max($0, bytes) } }
        #expect(try Data(contentsOf: file) == RangeServer.blob)
        #expect(last.withLock { $0 } == Int64(RangeServer.blob.count))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["blob"], "no pieces left behind")
    }
}

/// Serves `blob`: honoring Range at ranges.test, ignoring it (a whole 200) at whole.test.
final class RangeServer: URLProtocol, @unchecked Sendable {
    static let blob = Data((0..<1_000_003).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) })

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let blob = Self.blob
        var body = blob
        var status = 200
        var headers = ["Content-Length": "\(blob.count)"]
        if url.host == "ranges.test", let range = request.value(forHTTPHeaderField: "Range"),
            let match = range.wholeMatch(of: /bytes=(\d+)-(\d+)/), let start = Int(match.1), let end = Int(match.2)
        {
            body = blob.subdata(in: start..<(end + 1))
            status = 206
            headers = ["Content-Length": "\(body.count)", "Content-Range": "bytes \(start)-\(end)/\(blob.count)"]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
