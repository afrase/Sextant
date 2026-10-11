import Foundation

/// A pointer to an Oryx layout: a `configure.zsa.io` URL, a `layout/revision` serial, or a bare layout id.
public struct OryxReference: Hashable, Sendable {
    /// Board name from the URL (`voyager`), when it has one.
    public var geometry: String?
    public var layoutID: String
    /// Nil means the latest revision.
    public var revisionID: String?
    /// Layer index from the URL, when it has one.
    public var layer: Int?

    public init(geometry: String? = nil, layoutID: String, revisionID: String? = nil, layer: Int? = nil) {
        self.geometry = geometry
        self.layoutID = layoutID
        self.revisionID = revisionID
        self.layer = layer
    }

    /// Parses `https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0`, `KlgM7/40xJ7M` or `KlgM7`.
    /// `latest` as a revision means the latest. Returns nil for anything else.
    public init?(_ string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        func isID(_ p: Substring) -> Bool { (3...16).contains(p.count) && p.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }
        if let url = URL(string: s), let host = url.host(), host.hasSuffix("zsa.io") {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard let i = parts.firstIndex(of: "layouts"), parts.indices.contains(i + 1), isID(Substring(parts[i + 1])) else { return nil }
            let revision = parts.indices.contains(i + 2) ? parts[i + 2] : nil
            if let revision, revision != "latest", !isID(Substring(revision)) { return nil }
            self.init(
                geometry: i > 0 ? parts[i - 1] : nil, layoutID: parts[i + 1], revisionID: revision == "latest" ? nil : revision,
                layer: parts.indices.contains(i + 3) ? Int(parts[i + 3]) : nil)
            return
        }
        let pieces = s.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), pieces.allSatisfy(isID) else { return nil }
        self.init(layoutID: String(pieces[0]), revisionID: pieces.count == 2 ? String(pieces[1]) : nil)
    }
}
