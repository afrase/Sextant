import Foundation
import SextantApplication
import SextantDomain

/// Read-only Oryx client: public GraphQL `layout` query and firmware downloads (decision 2). Skeleton; the
/// Oryx slice implements it.
public struct OryxClient: OryxReader {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func layout(_ reference: OryxReference) async throws(OryxError) -> KeyboardLayout {
        throw .server("Not implemented yet.")
    }

    public func firmware(revisionID: String, expectedMD5: String) async throws(OryxError) -> Data {
        throw .server("Not implemented yet.")
    }
}
