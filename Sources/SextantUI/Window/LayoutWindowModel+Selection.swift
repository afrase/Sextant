import SextantApplication

/// How a click on a key changes a multi-selection (spec §5.4).
enum KeyClick {
    /// A plain click: that key alone.
    case select
    /// ⌘-click: adds the key or takes it out.
    case toggle
    /// ⇧-click: the keys from the anchor to it, in reading order.
    case range
}

extension LayoutWindowModel {
    /// Selected keys on the shown board: the inspector says "3 keys" and the context strip "3 keys selected".
    var selectedKeyCount: Int { page == nil ? session?.selectedKeys.count ?? 0 : 0 }

    /// ⌘- and ⇧-click select several keys only on the plain board in the Keys lens, with no pick on (ADR 0047). The
    /// session asks this before any edit, so elsewhere a multi-selection (one undo brought back, say) acts as its anchor.
    var selectsSeveralKeys: Bool { page == nil && lens == .keys && boardPick == nil }

    /// A click on a board key with ⌘ or ⇧ held; a plain click, or one where several keys can't be selected, is
    /// ``click(key:)``.
    func click(key index: Int, _ kind: KeyClick) {
        guard kind != .select, selectsSeveralKeys, let session, session.selection.keyIndex != nil else { return click(key: index) }
        if kind == .toggle { session.toggle(key: index) } else { session.selectRange(to: index) }
    }
}
