import Foundation
import SextantApplication
import SextantDomain

/// What the keycode picker assigns to (spec §5.6). The selected key's slot is the default; combo outputs, macro steps
/// and multi-selection bring their own, so they never edit the picker (ADR 0037).
struct AssignTarget {
    /// The scope token's text: "› Hold on Main" after the key's cap, or "Combo 3 › Output".
    var title: String
    /// The key whose cap the token shows and the board previews; nil when the target isn't a key.
    var key: KeyRef?
    /// The value being replaced: the footer's "Now …" and the ✓.
    var current: KeyAction?
    /// The keycodes it takes (a macro step takes only codes it can type); nil takes every one.
    var accepts: ((KeyAction) -> Bool)?
    /// Writes the keycode, as one undo step.
    var assign: @MainActor (KeyAction) -> Void
}

/// The floating panel's state (spec §5.6, §5.7): one component, two scopes.
public struct Palette {
    public enum Scope: Equatable, Sendable {
        /// The keycode picker: assigns to ``target``, or to the selected key's slot.
        case assign
        /// ⌘K: commands, keys, layers, keycodes and firmware settings.
        case general
        /// Find Key (⌘F): the general palette showing keys only.
        case keys
    }

    /// A new panel per open (focus and the appear animation); changing scope keeps it, so the panel morphs.
    let id = UUID()
    /// A new scope starts at the top of Suggested; the highlight and category of the old one don't apply.
    var scope: Scope {
        didSet {
            highlight = 0
            category = nil
            // Dropping the token drops its target: the general palette's keycodes assign to the selected key.
            if scope != .assign { target = nil }
        }
    }
    var query = "" { didSet { if query != oldValue { highlight = 0 } } }
    /// The picker's category rail; nil is Suggested.
    var category: KeycodeCategory? { didSet { highlight = 0 } }
    var highlight = 0
    /// The picker's own target; nil assigns to the selected key's slot.
    var target: AssignTarget?
}

/// One result row or tile.
struct PaletteItem: Identifiable {
    enum Group {
        case importOryx, suggested, recent, commands, keys, layers, keycodes, settings, documents

        var title: String {
            switch self {
            case .importOryx: String(localized: "Import")
            case .suggested: String(localized: "Suggested for the selected key")
            case .recent: String(localized: "Recent commands")
            case .commands: String(localized: "Commands")
            case .keys: String(localized: "Keys in this layout")
            case .layers: String(localized: "Layers")
            case .keycodes: String(localized: "Keycodes")
            case .settings: String(localized: "Firmware settings")
            case .documents: String(localized: "Documents")
            }
        }
    }

    enum Leading {
        case cap(KeyCapModel)
        case chip(HexColor?)
        case symbol(String)
    }

    var id: String
    var group: Group
    var title: String
    /// Trailing: a shortcut, QMK codes or a setting's value.
    var detail = ""
    /// A second line.
    var note: String?
    var leading: Leading
    /// What a keycode row assigns: the live preview and the ✓ read it.
    var keycode: KeyAction?
    var isCurrent = false
    var perform: @MainActor () -> Void
}

extension LayoutWindowModel {
    /// Opens the keycode picker on the selected key's slot (spec §5.6). The inspector's keycode tile, ⏎ on the board
    /// and Key ▸ Change Keycode… call it, some as an unapplied `() -> Void`, so it keeps this exact signature.
    public func openKeycodePicker() { openKeycodePicker(prefilled: "") }

    /// Opens the picker pre-filled, as typing on the board does. It ends Record Key and Record Steps.
    public func openKeycodePicker(prefilled query: String) {
        guard hasSelectedKey else { return }
        (recorder, macros.stepRecorder) = (nil, nil)
        palette = Palette(scope: .assign, query: query)
    }

    /// ⏎ (an empty query) or a typed character on the focused board (spec §9.2): the picker opens on the selected key,
    /// pre-filled, but not in the Lighting lens, whose letters are its tools. During a pick, ⏎ picks the selected key and
    /// typing does nothing (ADR 0037). Returns whether the key press was used.
    func typeOnBoard(_ query: String) -> Bool {
        guard let index = session?.selection.keyIndex else { return false }
        guard boardPick == nil else {
            if query.isEmpty { click(key: index) }
            return query.isEmpty
        }
        guard lens == .keys, hasSelectedKey else { return false }
        openKeycodePicker(prefilled: query)
        return true
    }

    /// Opens the picker on a target that isn't the selected key's slot, on any page. It ends Record Key and Record Steps.
    func openKeycodePicker(_ target: AssignTarget) {
        guard session != nil else { return }
        (recorder, macros.stepRecorder) = (nil, nil)
        palette = Palette(scope: .assign, target: target)
    }

    /// Opens the command palette (⌘K, the toolbar's Search) or Find Key (⌘F). It ends Record Key and Record Steps, which
    /// would otherwise take the typing.
    public func openPalette(_ scope: Palette.Scope = .general, query: String = "") {
        guard session != nil else { return }
        (recorder, macros.stepRecorder) = (nil, nil)
        palette = Palette(scope: scope, query: query)
    }

    func closePalette() { palette = nil }

    /// ⌘K and ⇧⌘O close the command palette when it is showing, like Spotlight; from the picker or Find Key they
    /// switch to it.
    func togglePalette() {
        if palette?.scope == .general { closePalette() } else { openPalette() }
    }

    /// The picker shows keycodes only while it has a target (``assignTarget``, without building it); otherwise it falls
    /// back to the general palette.
    var isPicking: Bool { palette?.scope == .assign && (palette?.target != nil || hasSelectedKey) }

    /// What the picker assigns to: its own target, or the selected key's slot while a key is shown.
    var assignTarget: AssignTarget? { palette?.target ?? keySlotTarget }

    private var keySlotTarget: AssignTarget? {
        guard hasSelectedKey, let session, let index = session.selection.keyIndex else { return nil }
        let (layer, slot) = (session.selection.layer, session.selection.slot)
        return AssignTarget(
            title: String(localized: "› \(slot.title) on \(session.currentLayer?.title ?? "")"),
            key: KeyRef(layer: layer, index: index, slot: slot), current: session.selectedAction
        ) { session.setAction(self.assigned($0)) }
    }

    /// The results for the open panel, in display order.
    var paletteItems: [PaletteItem] {
        guard let palette else { return [] }
        let query = palette.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPicking ? keycodeItems(query, category: palette.category) : generalItems(query, keysOnly: palette.scope == .keys)
    }

    // MARK: Keys in the panel

    func moveHighlight(by step: Int) {
        guard let highlight = palette?.highlight else { return }
        // Count first: reading the items inside the write to `palette` would be an exclusivity violation.
        let last = max(paletteItems.count - 1, 0)
        palette?.highlight = min(max(highlight + step, 0), last)
    }

    /// ⏎ runs the highlighted result; ⌘⏎ on a keycode assigns it and moves to the next key.
    func runHighlighted(advance: Bool = false) {
        guard let item = paletteItems[safe: palette?.highlight ?? 0] else { return }
        run(item, advance: advance)
    }

    func run(_ item: PaletteItem, advance: Bool = false) {
        if isPicking, let action = item.keycode { assign(action, advance: advance) } else { item.perform() }
    }

    /// ⇥ / ⇧⇥: the next or previous category.
    func cycleCategory(back: Bool) {
        let all: [KeycodeCategory?] = [nil] + KeycodeCategory.allCases
        let at = all.firstIndex(of: palette?.category) ?? 0
        palette?.category = all[(at + (back ? all.count - 1 : 1)) % all.count]
    }

    /// ⌥⇥: the next slot of the same key; other targets have no slots.
    func cycleSlot() {
        guard palette?.target == nil, let session, let key = session.selection.keyIndex else { return }
        let slots = KeySlot.allCases
        let at = slots.firstIndex(of: session.selection.slot) ?? 0
        session.select(key: key, slot: slots[(at + 1) % slots.count])
        palette?.highlight = 0  // Suggested differs per slot
    }

    /// ⌫ on an empty field removes the target token: the picker becomes the general palette.
    func dropScopeToken() {
        if palette?.scope == .assign { palette?.scope = .general }
    }

    // MARK: Assigning

    /// Assigns a keycode to the target as one undo step. On the selected slot, a plain HID keycode replacing a plain
    /// keycode keeps its chord modifiers, as `EditSession.setCode` does, and with `advance` (⌘⏎) the selection moves to
    /// the next key in reading order and the picker stays open; otherwise it closes.
    func assign(_ action: KeyAction, advance: Bool = false) {
        guard let target = assignTarget else { return }
        target.assign(action)
        recentKeycodes = [action] + recentKeycodes.filter { $0 != action }.prefix(7)
        // Another target has no next key: it closes, and the selection stays.
        guard advance, palette?.target == nil, let session, let index = session.selection.keyIndex else {
            palette = nil
            return
        }
        let order = BoardView.readingOrder(session.geometry)
        let sorted = order.indices.sorted { order[$0] > order[$1] }
        if let at = sorted.firstIndex(of: index) { session.select(key: sorted[(at + 1) % sorted.count]) }
        palette?.query = ""
    }

    private func assigned(_ action: KeyAction) -> KeyAction {
        // Only a HID keycode takes a chord (LSFT(QK_BOOT) is another keycode, QK_KB_0). OSM and LM keep their modifiers
        // in the same field, but they aren't a chord for the keycode replacing them. The picker never offers a colour key.
        guard action.code.hasPrefix("KC_"), !action.isTransparent, !action.isNone, let existing = session?.selectedAction,
            !existing.isLayerAction, KeycodeCatalog.entry(for: existing.code)?.needsModifiers != true
        else { return action }
        return KeyAction(code: action.code, modifiers: existing.modifiers)
    }

    /// The target's cap as the highlighted keycode would make it, for the picker preview state (spec §4.7, §5.6). The
    /// board shows only its own layer's keys.
    var pickerPreview: KeyCapModel? {
        guard isPicking, let session, let key = assignTarget?.key, key.layer == session.selection.layer,
            let action = paletteItems[safe: palette?.highlight ?? 0]?.keycode
        else { return nil }
        var layout = session.layout
        // As `assign` writes it: only the selected slot keeps its chord.
        layout.updateKey(layer: key.layer, index: key.index) { $0[key.slot ?? .tap] = palette?.target == nil ? assigned(action) : action }
        return KeyCapModel(layout: layout, layer: key.layer, index: key.index, mode: legendMode)
    }

    /// The scope token's text: "› Hold on Main" after the cap.
    var pickerTarget: String { assignTarget?.title ?? "" }

    /// The footer's current value: "Now KC_TRANSPARENT".
    var pickerCurrent: String {
        guard let action = assignTarget?.current else { return String(localized: "Now empty") }
        return String(localized: "Now \(Legends.legend(for: action).qmk)")
    }

    /// Results in a rail category (nil is Suggested).
    func pickerCount(_ category: KeycodeCategory?) -> Int {
        if category == .macros { return macroPickerCount }
        return category.map { KeycodeCatalog.entries(in: $0).reduce(0) { $0 + pickable($1).count } } ?? suggestedKeycodes.count
    }

    // MARK: Keycode results

    /// The catalog's ranked search (glyph, code or alias, name prefix, word, fuzzy), or a category to browse.
    private func keycodeItems(_ query: String, category: KeycodeCategory?) -> [PaletteItem] {
        guard let session else { return [] }
        if category == .macros { return macroPickerItems(query) }
        let actions =
            query.isEmpty
            ? category.map { KeycodeCatalog.entries(in: $0).flatMap(pickable) } ?? suggestedKeycodes
            : KeycodeCatalog.search(query, category: category).flatMap(pickable)
        let current = assignTarget?.current
        return actions.map { action in
            let legend = Legends.legend(for: action, layerNames: session.layout.layerNames)
            let entry = KeycodeCatalog.entry(for: action.code)
            let codes = action.layer == nil ? ([action.code] + (entry?.aliases.prefix(1) ?? [])).joined(separator: " · ") : legend.qmk
            return PaletteItem(
                id: "keycode-\(legend.qmk)", group: .keycodes, title: legend.name, detail: codes,
                note: [entry?.shiftedLabel.map { "⇧ \($0)" }, entry?.category.title].compactMap { $0 }.joined(separator: " · "),
                leading: .cap(capModel(action, session.layout)), keycode: action,
                isCurrent: current.map { $0.canonicalCode == action.canonicalCode && $0.layer == action.layer } ?? false
            ) { [weak self] in
                self?.assign(action)
            }
        }
    }

    /// What the picker offers for an entry: layer functions once per layer.
    /// shortcut: OSM, LM and RGB need a modifier or a colour the picker can't ask for; they stay out until the slot
    /// editors offer them.
    private func pickable(_ entry: KeycodeEntry) -> [KeyAction] {
        if entry.needsModifiers || entry.needsColor { return [] }
        guard entry.needsLayer, let layers = session?.layout.layers.indices else { return [KeyAction(code: entry.code)].filter(accepts) }
        return layers.map { KeyAction(code: entry.code, layer: $0) }.filter(accepts)
    }

    private func accepts(_ action: KeyAction) -> Bool { assignTarget?.accepts?(action) ?? true }

    /// Recents, then slot-aware suggestions: modifiers and layers for a hold, common keys otherwise.
    private var suggestedKeycodes: [KeyAction] {
        guard let session else { return [] }
        let slot = assignTarget?.key?.slot
        let isHold = slot == .hold || slot == .tapHold
        let codes =
            isHold
            ? [
                "KC_LEFT_SHIFT", "KC_LEFT_CTRL", "KC_LEFT_ALT", "KC_LEFT_GUI", "KC_RIGHT_SHIFT", "KC_RIGHT_CTRL", "KC_RIGHT_ALT",
                "KC_RIGHT_GUI",
            ]
            : ["KC_ESCAPE", "KC_TAB", "KC_ENTER", "KC_SPACE", "KC_BSPC", "KC_DELETE", "KC_TRANSPARENT", "KC_NO"]
        let layers = isHold ? session.layout.layers.indices.filter { $0 != session.selection.layer }.map(KeyAction.momentary) : []
        // Recents outlive deleted layers and layout switches.
        let recents = recentKeycodes.filter { $0.layer.map(session.layout.layers.indices.contains) ?? true }
        var seen = Set<KeyAction>()
        return (recents + codes.map { KeyAction(code: $0) } + layers).filter { accepts($0) && seen.insert($0).inserted }
    }

    /// A cap showing `action` alone; a layer key takes its target layer's colour.
    private func capModel(_ action: KeyAction, _ layout: KeyboardLayout) -> KeyCapModel {
        var layout = layout
        layout.updateKey(layer: 0, index: 0) { $0 = Key(tap: action) }
        return KeyCapModel(layout: layout, layer: 0, index: 0)
    }

    // MARK: General results

    private func generalItems(_ query: String, keysOnly: Bool) -> [PaletteItem] {
        guard let session else { return [] }
        if keysOnly { return keyItems(query, limit: 60) }
        let commands = paletteCommands
        guard !query.isEmpty else {
            let recent = recentCommands.compactMap { id in commands.first { $0.id == id } }.map { item in
                var item = item
                item.group = .recent
                return item
            }
            return slotSuggestions + recent + commands.filter { !recentCommands.contains($0.id) }
        }
        var items: [PaletteItem] = []
        // A pasted configure.zsa.io link or layout/revision serial; a bare word could be a layout id, so it needs a "/".
        if query.contains("/"), let ref = OryxReference(query) {
            items.append(
                PaletteItem(
                    id: "import", group: .importOryx, title: String(localized: "Import from Oryx…"),
                    detail: [ref.layoutID, ref.revisionID].compactMap { $0 }.joined(separator: "/"),
                    leading: .symbol("square.and.arrow.down")
                ) { [weak self] in
                    self?.palette = nil
                    self?.openImport(query)
                })
        }
        items += Self.ranked(slotSuggestions, query) { [$0.title] }
        items += Self.ranked(commands, query).prefix(8)
        items += keyItems(query, limit: 6)
        items += Self.ranked(layerItems, query).prefix(5)
        // Only where the key is shown: entering the assign scope on a page would find no target.
        if hasSelectedKey, let index = session.selection.keyIndex {
            let key = session.legend(at: index).legend.primary.map(CapLegendView.capText) ?? String(localized: "Key \(index)")
            items += keycodeItems(query, category: nil).prefix(5).enumerated().map { n, item in
                var item = item
                item.note = String(localized: "Assign to \(key) \(pickerTarget)…")
                item.perform = { [weak self] in
                    self?.palette?.scope = .assign
                    self?.palette?.highlight = n
                }
                return item
            }
        }
        items += settingItems(query)
        items += macroDocumentItems(query)
        return items
    }

    /// Matches first, best first; ties keep their order.
    private static func ranked(
        _ items: [PaletteItem], _ query: String, fields: (PaletteItem) -> [String] = { [$0.title, $0.note ?? ""] }
    ) -> [PaletteItem] {
        items.enumerated().map { (PaletteSearch.score(query, fields($1)), $0, $1) }.filter { $0.0 > 0 }
            .sorted { ($0.0, $1.1) > ($1.0, $0.1) }.map(\.2)
    }

    /// Keys in the layout by name ("Esc · Sym+Num · key 0"); with no query, the shown layer's keys in order.
    private func keyItems(_ query: String, limit: Int) -> [PaletteItem] {
        guard let session else { return [] }
        let layout = session.layout
        var found: [(score: Int, layer: Int, index: Int, name: String)] = []
        for l in query.isEmpty ? [session.selection.layer] : Array(layout.layers.indices) {
            for (i, key) in layout.layers[l].keys.enumerated() where !key.isTransparent && key.kind != .disabled {
                guard let primary = Legends.legend(for: key, layerNames: layout.layerNames).primary else { continue }
                let score = query.isEmpty ? 1 : PaletteSearch.score(query, [primary.name, primary.text, primary.qmk])
                if score > 0 { found.append((score, l, i, primary.name)) }
            }
        }
        let best = found.enumerated().sorted { ($0.element.score, $1.offset) > ($1.element.score, $0.offset) }.prefix(limit).map(\.element)
        return best.map { hit in
            PaletteItem(
                id: "key-\(hit.layer)-\(hit.index)", group: .keys, title: hit.name,
                note: String(localized: "\(layout.layers[hit.layer].title) · key \(hit.index)"),
                leading: .cap(KeyCapModel(layout: layout, layer: hit.layer, index: hit.index))
            ) { [weak self] in
                self?.palette = nil
                // The destination, not the layer: on a page the key's layer may already be the shown one.
                self?.destination = .layer(hit.layer)
                session.select(key: hit.index)
            }
        }
    }

    private var layerItems: [PaletteItem] {
        guard let session else { return [] }
        return session.layout.layers.enumerated().map { index, layer in
            PaletteItem(
                id: "layer-\(layer.id)", group: .layers, title: layer.title, detail: index < 9 ? "⌘\(index + 1)" : "",
                note: String(localized: "Layer \(index)"), leading: .chip(layer.color)
            ) { [weak self] in
                self?.palette = nil
                self?.destination = .layer(index)
            }
        }
    }

    /// "Tapping term · 180 ms · changed": the settings the Firmware Settings page shows, and the Navigator ("Trackpad ·
    /// Right"); choosing one goes to its section.
    private func settingItems(_ query: String) -> [PaletteItem] {
        guard let layout = session?.layout else { return [] }
        let sections = FirmwareSettings.sections(for: layout)
        let section = { (id: String) in sections.first { $0.settings.contains { $0.id == id } }?.id }
        func item(_ id: String, _ title: String, _ detail: String, section: String?) -> PaletteItem {
            PaletteItem(id: "setting-\(id)", group: .settings, title: title, detail: detail, leading: .symbol("slider.horizontal.3")) {
                [weak self] in
                self?.palette = nil
                self?.destination = .firmwareSettings
                self?.settingsScrollTarget = section
            }
        }
        let attached = layout.navigator.map { "\(FirmwareSettings.title($0.kind)) · \(FirmwareSettings.title($0.side))" }
        let navigator = item(
            "navigator", String(localized: "Navigator"), attached ?? FirmwareSettings.title(nil), section: FirmwareSettings.navigator)
        let kinds = "\(FirmwareSettings.title(.trackpad)) \(FirmwareSettings.title(.trackball))"
        let sides = "\(String(localized: "Side")) \(FirmwareSettings.title(.left)) \(FirmwareSettings.title(.right))"
        return Self.ranked([navigator], query) { [$0.title, kinds, sides] }
            + SettingsCatalog.voyager.search(query).filter { section($0.id) != nil }.prefix(5).map { setting in
                // Navigator settings live in the Navigator's options (ADR 0030).
                let stored = layout.storedValue(of: setting)
                let value = setting.format(stored ?? setting.unsetValue)
                let changed = stored.map { $0 != setting.unsetValue } ?? false
                return item(
                    setting.id, setting.title, changed ? String(localized: "\(value) · changed") : value, section: section(setting.id))
            }
    }

    /// "Change Hold · Left Option · ⌥⌘2": one per slot of the selected key; choosing one opens the picker on it.
    private var slotSuggestions: [PaletteItem] {
        guard let session, let index = session.selection.keyIndex, let key = session.selectedKey else { return [] }
        return KeySlot.allCases.enumerated().map { n, slot in
            PaletteItem(
                id: "slot-\(slot.rawValue)", group: .suggested, title: String(localized: "Change \(slot.title)"), detail: "⌥⌘\(n + 1)",
                note: key[slot].map { Legends.legend(for: $0, layerNames: session.layout.layerNames).name } ?? String(localized: "Empty"),
                leading: .symbol("pencil")
            ) { [weak self] in
                session.select(key: index, slot: slot)
                self?.palette?.scope = .assign
                self?.palette?.query = ""
            }
        }
    }

    /// Menu commands the window can run now, with their shortcuts. Running one closes the palette first.
    private var paletteCommands: [PaletteItem] {
        guard let session else { return [] }
        var items: [PaletteItem] = []
        /// A toggle passes a `key`, so it stays one command in Recent when its title flips.
        func add(
            _ title: String, _ shortcut: String = "", key: String? = nil, if enabled: Bool = true, _ run: @escaping @MainActor () -> Void
        ) {
            guard enabled else { return }
            let id = "command-\(key ?? title)"
            items.append(
                PaletteItem(id: id, group: .commands, title: title, detail: shortcut, leading: .symbol("command")) {
                    [weak self] in
                    guard let self else { return }
                    palette = nil
                    recentCommands = Array(([id] + recentCommands.filter { $0 != id }).prefix(5))
                    run()
                })
        }
        let hasKey = hasSelectedKey
        add(String(localized: "Build & Flash"), "⌘R", if: canBuild) { self.build(.buildAndFlash) }
        add(String(localized: "Build"), "⌘B", if: canBuild) { self.build(.build) }
        add(String(localized: "Stop"), "⌘.", if: canStop) { self.build(.stop) }
        add(String(localized: "Show Build Log"), "⇧⌘B", if: buildFlash != nil) { self.build(.showLog) }
        add(isFollowing ? String(localized: "Stop Following") : String(localized: "Follow Keyboard"), "⌘L", key: "follow", if: canFollow) {
            self.isFollowing.toggle()
        }
        add(String(localized: "Import from Oryx…"), "⇧⌘I") { self.openImport() }
        add(String(localized: "Show in Finder")) { Task { await self.showInFinder() } }
        add(String(localized: "Change Keycode…"), "⏎", if: hasKey) { self.openKeycodePicker() }
        add(String(localized: "Record Key"), "⇧⌘R", if: hasKey) { self.startRecording() }
        add(String(localized: "Make Transparent"), "⌘⌫", if: hasKey) { session.makeTransparent() }
        add(String(localized: "Disable Key"), "⇧⌘⌫", if: hasKey) { session.disable() }
        add(String(localized: "Override on This Layer"), if: canOverrideKey) { session.overrideInherited() }
        add(String(localized: "Copy QMK Expression"), "⌥⇧⌘C", if: hasKey) { session.copyQMKExpression() }
        add(String(localized: "New Layer"), "⇧⌘N") { session.addLayer() }
        add(String(localized: "Duplicate Layer"), "⇧⌘D") { session.duplicateLayer(session.selection.layer) }
        add(String(localized: "Delete Layer…"), if: canDeleteLayer) { self.requestDeleteLayer() }
        add(String(localized: "Move Layer Up"), "⌥⌘↑", if: canShowPreviousLayer) { self.moveLayer(by: -1) }
        add(String(localized: "Move Layer Down"), "⌥⌘↓", if: canShowNextLayer) { self.moveLayer(by: 1) }
        add(String(localized: "Show Previous Layer"), "⇧⌘[", if: canShowPreviousLayer) { self.showAdjacentLayer(-1) }
        add(String(localized: "Show Next Layer"), "⇧⌘]", if: canShowNextLayer) { self.showAdjacentLayer(1) }
        for (n, lens) in Lens.allCases.enumerated() {
            add(String(localized: "Lens: \(lens.title)"), "⌃⌘\(n + 1)") { self.lens = lens }
        }
        for (mode, shortcut) in [(LegendMode.symbols, ""), (.qmk, "⌥⌘C"), (.index, "⌥⌘N")] {
            add(String(localized: "Legends: \(mode.title)"), shortcut) { self.legendMode = mode }
        }
        add(showsInspector ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"), key: "inspector") {
            self.showsInspector.toggle()
        }
        add(columnVisibility == .detailOnly ? String(localized: "Show Sidebar") : String(localized: "Hide Sidebar"), "⌃⌘S", key: "sidebar")
        {
            self.columnVisibility = self.columnVisibility == .detailOnly ? .all : .detailOnly
        }
        return items
    }
}

/// Text matching for palette rows: every word of the query must match a field. Per field: exact (100) > prefix (80) >
/// word prefix (70) > substring (50). Keycodes use the catalog's own ranking instead.
enum PaletteSearch {
    static func score(_ query: String, _ fields: [String]) -> Int {
        let folded = fields.map(fold)
        var total = 0
        for term in fold(query).split(whereSeparator: \.isWhitespace).map(String.init) {
            let best =
                folded.map { field in
                    if field == term { return 100 }
                    if field.hasPrefix(term) { return 80 }
                    if field.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(term) }) { return 70 }
                    return field.contains(term) ? 50 : 0
                }.max() ?? 0
            guard best > 0 else { return 0 }
            total += best
        }
        return total
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
