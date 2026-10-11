import Foundation

/// A parsed Oryx layout reference: a configure.zsa.io URL, a USB serial (`KlgM7/40xJ7M`) or a bare id.
public struct OryxLayoutReference: Hashable, Sendable {
    public var geometry: String
    public var layoutID: String
    /// Revision id, or nil for "latest".
    public var revisionID: String?
    /// Layer index from the URL path, if present.
    public var layer: Int?

    /// Accepts:
    /// - `https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0` (optionally with `/<key>/<slot>` after the layer)
    /// - `configure.zsa.io/voyager/layouts/KlgM7/latest`
    /// - `KlgM7/40xJ7M` (the keyboard's USB serial), `KlgM7`
    public init?(_ string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let isID: (Substring) -> Bool = { $0.count >= 4 && $0.count <= 8 && $0.allSatisfy { $0.isLetter || $0.isNumber } }
        if s.contains("zsa.io") || s.contains("/layouts/") {
            let path = s.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            let parts = path.split(separator: "/")
            guard let li = parts.firstIndex(of: "layouts"), parts.indices.contains(li + 1), isID(parts[li + 1]) else { return nil }
            geometry = li > 0 && parts[li - 1] != "configure.zsa.io" ? String(parts[li - 1]) : "voyager"
            layoutID = String(parts[li + 1])
            let rev = parts.indices.contains(li + 2) ? String(parts[li + 2]) : nil
            revisionID = rev == "latest" ? nil : rev
            layer = parts.indices.contains(li + 3) ? Int(parts[li + 3]) : nil
            return
        }
        let parts = s.split(separator: "/")
        guard let first = parts.first, isID(first), parts.count <= 2 else { return nil }
        geometry = "voyager"
        layoutID = String(first)
        revisionID = parts.count == 2 && isID(parts[1]) ? String(parts[1]) : nil
        layer = nil
    }

    /// Canonical viewer URL.
    public var url: URL {
        URL(string: "https://configure.zsa.io/\(geometry)/layouts/\(layoutID)/\(revisionID ?? "latest")/\(layer ?? 0)")!
    }
}

/// What an import shows before the user commits.
public struct OryxImportPreview: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        case pastedURL
        /// Detected from the connected keyboard's USB serial.
        case connectedKeyboard
    }

    public enum StepState: String, Hashable, Sendable { case pending, running, done, warning, failed }

    public struct Step: Identifiable, Hashable, Sendable {
        public var id: String { title }
        public var title: String
        public var detail: String?
        public var state: StepState
    }

    public struct Summary: Hashable, Sendable {
        public var layerCount: Int
        /// Non-transparent keys across all layers.
        public var assignedKeys: Int
        public var dualFunctionKeys: Int
        public var customLabels: Int
        public var colorKeys: Int
        public var macros: Int
        public var combos: Int
        public var firmwareVersion: String?
        public var author: String
        public var lastEdited: Date?
    }

    public var input: String
    public var reference: OryxLayoutReference
    public var source: Source
    public var layout: KeyboardLayout
    public var summary: Summary
    public var steps: [Step]
    public var notes: [String]

    /// The import of the user's layout from its Oryx URL, fully resolved.
    public static func sample(layout: KeyboardLayout, source: Source = .pastedURL) -> OryxImportPreview {
        let input = source == .pastedURL ? "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0" : "KlgM7/40xJ7M"
        let keys = layout.layers.flatMap(\.keys)
        let summary = Summary(
            layerCount: layout.layers.count,
            assignedKeys: keys.filter { !$0.isTransparent }.count,
            dualFunctionKeys: keys.filter { $0.tap != nil && $0.hold != nil }.count,
            customLabels: keys.filter { ($0.customLabel ?? "").isEmpty == false }.count,
            colorKeys: keys.filter { $0.tap?.canonicalCode == "RGB" }.count,
            macros: keys.filter { $0.actions.contains { $0.action.macro != nil } }.count,
            combos: layout.combos.count,
            firmwareVersion: layout.firmwareVersion,
            author: "afrase",
            lastEdited: layout.createdAt)
        return OryxImportPreview(
            input: input,
            reference: OryxLayoutReference(input)!,
            source: source,
            layout: layout,
            summary: summary,
            steps: [
                Step(title: source == .pastedURL ? "Read link" : "Read keyboard serial", detail: "Layout KlgM7, revision 40xJ7M", state: .done),
                Step(title: "Fetch layout from Oryx", detail: "“\(layout.title)” by afrase", state: .done),
                Step(title: "Check firmware", detail: "Firmware \(layout.firmwareVersion ?? "?") · binary md5 matches", state: .done),
                Step(title: "Convert", detail: "\(summary.layerCount) layers · \(summary.assignedKeys) assigned keys", state: .done),
            ],
            notes: [
                "\(summary.customLabels) custom labels are shown in Sextant only; they aren't sent to the keyboard.",
                "Navigator trackpad found on the right half; its settings come along.",
                "Oryx stays read-only. Sextant saves its own copy.",
            ])
    }
}
