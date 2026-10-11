import Foundation

/// One saved revision of a layout.
public struct LayoutRevision: Identifiable, Hashable, Sendable {
    public enum Source: String, Hashable, Sendable { case oryx, local }
    /// Revision id (Oryx hash or a local id).
    public var id: String
    public var message: String
    public var date: Date
    public var author: String
    public var source: Source
    /// The full layout at this revision.
    public var layout: KeyboardLayout
    /// Size of the firmware built from this revision, when known (bytes).
    public var firmwareSize: Int?
}

/// An ordered revision timeline (oldest first) with per-key diffs.
public struct RevisionHistory: Hashable, Sendable {
    public var revisions: [LayoutRevision]

    public init(revisions: [LayoutRevision]) { self.revisions = revisions }

    public var latest: LayoutRevision? { revisions.last }

    /// Diff between two revisions by id.
    public func diff(from oldID: String, to newID: String) -> LayoutDiff? {
        guard let a = revisions.first(where: { $0.id == oldID }), let b = revisions.first(where: { $0.id == newID }) else { return nil }
        return b.layout.diff(from: a.layout)
    }

    /// Diff of a revision against the one before it (empty diff for the first).
    public func diffToPrevious(_ index: Int) -> LayoutDiff {
        guard revisions.indices.contains(index) else { return LayoutDiff(keyChanges: [], addedLayers: [], removedLayers: [], renamedLayers: [], recoloredLayers: []) }
        let cur = revisions[index].layout
        let prev = index > 0 ? revisions[index - 1].layout : cur
        return cur.diff(from: prev)
    }

    /// Four revisions ending at `current`:
    /// 1. "Imported from Oryx" (no dual-function Z and /, no Brd+Sys shortcuts, no colour keys, plain = key)
    /// 2. Z/⌥ and //⌥ dual-function keys (2 keys)
    /// 3. Back / Prev Tab / Next Tab / Forward on Brd+Sys (4 keys)
    /// 4. The real current revision 40xJ7M: =/Esc and three colour keys (4 keys)
    public static func sample(current: KeyboardLayout) -> RevisionHistory {
        let cal = Calendar(identifier: .gregorian)
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: y, month: m, day: d, hour: h, minute: min))!
        }
        var r3 = current
        // Revision 3 lacks the =/Esc dual function and the colour keys.
        r3.updateKey(layer: 0, index: 0) { $0.hold = nil }
        for i in 21...23 { r3.updateKey(layer: 2, index: i) { $0 = .transparent } }
        r3.revisionId = "q7Lm2E"
        r3.revisionMessage = "Browser back/forward and tab switching on Brd+Sys"
        var r2 = r3
        for i in 44...47 { r2.updateKey(layer: 2, index: i) { $0 = .transparent } }
        r2.revisionId = "Pz4kWd"
        r2.revisionMessage = "Option on Z and / when held"
        var r1 = r2
        r1.updateKey(layer: 0, index: 19) { $0.hold = nil }
        r1.updateKey(layer: 0, index: 48) { $0.hold = nil }
        r1.revisionId = "k2Vn8Q"
        r1.revisionMessage = "Imported from Oryx"
        return RevisionHistory(revisions: [
            LayoutRevision(id: r1.revisionId, message: r1.revisionMessage!, date: date(2026, 8, 2, 18, 12), author: "afrase", source: .oryx, layout: r1, firmwareSize: 64_918),
            LayoutRevision(id: r2.revisionId, message: r2.revisionMessage!, date: date(2026, 8, 19, 9, 41), author: "afrase", source: .local, layout: r2, firmwareSize: 65_110),
            LayoutRevision(id: r3.revisionId, message: r3.revisionMessage!, date: date(2026, 9, 3, 21, 5), author: "afrase", source: .local, layout: r3, firmwareSize: 65_402),
            LayoutRevision(id: current.revisionId, message: current.revisionMessage ?? "Keyboard layout edited.",
                           date: current.createdAt ?? date(2026, 9, 16, 5, 5), author: "afrase", source: .oryx, layout: current, firmwareSize: 65_786),
        ])
    }
}
