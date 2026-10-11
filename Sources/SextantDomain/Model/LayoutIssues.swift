import Foundation

/// A problem found in a layout before any build (spec §7.5 "Live issues").
public struct LayoutIssue: Hashable, Sendable, Identifiable {
    public enum Severity: String, Hashable, Sendable { case error, warning }
    public enum Kind: Hashable, Sendable {
        case unknownKeycode(String)
        case missingLayer(Int)
        case unreachableLayer(Int)
        case macroTooLong(steps: Int)
        case emptyCombo
        case tapDanceUnsupported
        case nearSizeLimit
    }

    public var kind: Kind
    public var severity: Severity
    /// The key the issue is on; nil for layout-wide issues (an unreachable layer, a combo).
    public var key: KeyRef?

    public init(kind: Kind, severity: Severity, key: KeyRef?) {
        self.kind = kind
        self.severity = severity
        self.key = key
    }

    public var id: String { "\(kind)-\(key.map { "\($0.layer)-\($0.index)-\($0.slot?.rawValue ?? "")" } ?? "")" }
}

public enum LayoutIssues {
    /// Every live issue in `layout`, errors first, then in layer and key order.
    public static func check(_ layout: KeyboardLayout) -> [LayoutIssue] {
        []  // Implemented in the build slice (spec §7.5).
    }
}
