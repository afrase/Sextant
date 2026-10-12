import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

extension EnvironmentValues {
    /// The window model, for the board's picker hooks: ⏎ and typing, and the preview or recording cap.
    @Entry var layoutWindow: LayoutWindowModel?
}

extension SextantMotion {
    /// The palette and picker appearing: a fade and a scale from 0.98 over 0.16 s; a 0.12 s fade under Reduce Motion.
    var panel: Animation { .easeOut(duration: reduceMotion ? 0.12 : 0.16) }
}

extension View {
    /// Floats the command palette and keycode picker over the canvas (never taking board space, spec §3.3) and runs
    /// Record Key's monitor. ⇧⌘O is the palette's second shortcut (spec §5.7).
    func paletteHost(_ model: LayoutWindowModel) -> some View {
        modifier(PaletteHost(model: model))
    }
}

/// The board and its selected key, which `PickerCapOverlay` publishes so the picker can float clear of the key and a
/// click on another key can retarget it.
private struct PickerTarget: PreferenceKey {
    struct Target {
        var board: Anchor<CGRect>
        var layout: BoardLayout
        var key: Int
    }

    static var defaultValue: Target? { nil }
    static func reduce(value: inout Target?, nextValue: () -> Target?) { value = value ?? nextValue() }
}

/// Where a click keeps the panel open, in the window's top-left coordinates: the panel and, for the picker, the
/// board's keys.
struct PanelHits: Equatable {
    var panel = CGRect.null
    var board: CGRect?
    var layout: BoardLayout?

    func keepsOpen(_ point: CGPoint, picking: Bool) -> Bool {
        if panel.contains(point) { return true }
        guard picking, let board, let layout else { return false }
        return layout.keyIndex(at: CGPoint(x: point.x - board.minX, y: point.y - board.minY)) != nil
    }
}

struct PaletteHost: ViewModifier {
    var model: LayoutWindowModel
    @Environment(\.motion) private var motion
    @State private var hits = PanelHits()

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(PickerTarget.self) { target in
                GeometryReader { proxy in
                    if let palette = model.palette, let session = model.session {
                        let items = model.paletteItems
                        let key = target.flatMap { t in
                            t.layout.frames[safe: t.key]?.boundingBox.offsetBy(dx: proxy[t.board].minX, dy: proxy[t.board].minY)
                        }
                        let frame =
                            model.isPicking
                            ? Self.pickerFrame(beside: key ?? .zero, in: proxy.size)
                            : Self.paletteFrame(items: items, in: proxy.size)
                        PalettePanel(model: model, palette: palette, session: session, items: items, width: frame.width)
                            .frame(width: frame.width, height: frame.height)
                            .onGeometryChange(for: PanelHits.self) { panel in
                                let global = panel.frame(in: .global)
                                let board = target.map { panel[$0.board].offsetBy(dx: global.minX, dy: global.minY) }
                                return PanelHits(panel: global, board: board, layout: target?.layout)
                            } action: {
                                hits = $0
                            }
                            .position(x: frame.midX, y: frame.midY)
                            .id(palette.id)
                            .transition(motion.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .animation(motion.panel, value: model.palette?.id)
                .animation(motion.standard, value: model.isPicking)
            }
            .environment(\.layoutWindow, model)
            .background {
                Button("Command Palette") { model.togglePalette() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .modifier(RecordKeyMonitor(model: model))
            .task(id: model.palette != nil) { await closeOnClickOutsideOrEscape() }
    }

    /// While a panel is open, a local monitor on its window closes it on esc wherever focus is, and on a click outside
    /// it, which still goes through. A click on a key retargets the picker instead (spec §5.6, §5.7). Like Record Key's
    /// monitor it needs no TCC, and the panel closes when the window resigns key.
    private func closeOnClickOutsideOrEscape() async {
        guard model.palette != nil, let window = NSApp.keyWindow else { return }
        let number = window.windowNumber
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { event in
            guard event.windowNumber == number else { return event }
            // `keyCode` raises on a mouse event.
            let (isKey, location) = (event.type == .keyDown, event.locationInWindow)
            let isEscape = isKey && event.keyCode == 0x35
            let consumed = MainActor.assumeIsolated {
                if isKey {
                    // An input method's composition takes esc first.
                    guard isEscape, (window.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
                    model.closePalette()
                    return true
                }
                guard let point = window.contentView?.convert(location, from: nil) else { return false }
                if !hits.keepsOpen(point, picking: model.isPicking) { model.closePalette() }
                return false
            }
            return consumed ? nil : event
        }
        for await _ in NotificationCenter.default.notifications(named: NSWindow.didResignKeyNotification, object: window) {
            model.closePalette()
            break
        }
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// The picker floats over the half of the column opposite its key and keeps 8 pt clear of the key's rotated
    /// bounds, narrowing rather than covering an inner key: the target cap always stays visible (spec §5.6).
    static func pickerFrame(beside key: CGRect, in area: CGSize) -> CGRect {
        // Laid out as if the key were on the left, then mirrored for a right-hand key.
        let mirrored = key.midX > area.width / 2
        let near = mirrored ? area.width - key.minX + 8 : key.maxX + 8
        let width = max(0, min(560, area.width / 2 + 40, area.width - 12 - near))
        let x = min(max(area.width * 0.75 - width / 2, near), area.width - 12 - width)
        let height = min(440, area.height - 16)
        // Centred on the board, which sits about 45% down the column (§3.3).
        let y = min(max(area.height * 0.45 - height / 2, 8), area.height - 8 - height)
        return CGRect(x: mirrored ? area.width - x - width : x, y: y, width: width, height: height)
    }

    /// The palette sits at the top centre, 24 pt below the toolbar (§5.7), as tall as its results.
    static func paletteFrame(items: [PaletteItem], in area: CGSize) -> CGRect {
        let headers = zip(items, items.dropFirst()).filter { $0.group != $1.group }.count + (items.isEmpty ? 0 : 1)
        let list = items.isEmpty ? 80 : min(400, CGFloat(items.count) * 40 + CGFloat(headers) * 26 + 12)
        let size = CGSize(width: min(640, area.width - 32), height: 52 + list + 30)
        return CGRect(origin: CGPoint(x: (area.width - size.width) / 2, y: max(8, min(24, area.height - 8 - size.height))), size: size)
    }
}

/// The glass panel shared by the picker and the palette (spec §5.6, §5.7, §10.4).
struct PalettePanel: View {
    var model: LayoutWindowModel
    var palette: Palette
    var session: EditSession
    var items: [PaletteItem]
    var width: CGFloat
    @FocusState private var isFieldFocused: Bool
    @State private var selection: TextSelection?

    private var isPicking: Bool { model.isPicking }
    /// In centre columns narrower than 800 pt the rail shows icons only (spec §5.6).
    private var compact: Bool { width < 440 }
    private var railWidth: CGFloat { compact ? 48 : 160 }
    private var isGrid: Bool { isPicking && palette.query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var columns: Int { max(1, Int((width - railWidth - 17) / 72)) }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 52)
            Divider()
            if isPicking {
                HStack(spacing: 0) {
                    CategoryRail(model: model, selected: palette.category, compact: compact).frame(width: railWidth)
                    Divider()
                    results
                }
            } else {
                results
            }
            Divider()
            footer.frame(height: 29)
        }
        .surface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isPicking ? Text("Keycode picker") : Text("Command palette"))
        .onAppear { isFieldFocused = true }
        // Once the panel has gone (its field keeps focus while it fades), focus goes back to the board, unless a click
        // outside it focused a text field or a list.
        .onDisappear {
            Task {
                let responder = NSApp.keyWindow?.firstResponder
                if model.palette == nil && !(responder is NSText || responder is NSTableView) { model.boardFocusRequests += 1 }
            }
        }
        // Focus stays in the field, so VoiceOver hears the highlighted result as it changes (arrows or typing).
        .onChange(of: items[safe: palette.highlight]?.id) {
            guard let item = items[safe: palette.highlight] else { return }
            AccessibilityNotification.Announcement(ResultAccessibility.label(item)).post()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if isPicking, let index = session.selection.keyIndex {
                // The scope token: "[Z] › Hold on Main". ⌫ on an empty field removes it.
                HStack(spacing: 6) {
                    KeyCap(model: KeyCapModel(layout: session.layout, layer: session.selection.layer, index: index), u: 24)
                        .frame(width: 24, height: 24)
                    Text(model.pickerTarget).font(.callout.weight(.medium)).lineLimit(1)
                }
                .padding(.leading, 3)
                .padding(.trailing, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Assigning to key \(index) \(model.pickerTarget)"))
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            TextField(placeholder, text: Binding(get: { palette.query }, set: { model.palette?.query = $0 }), selection: $selection)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFieldFocused)
                // A focused field selects its text; typing on the board must add to the pre-filled character, not replace it.
                .onChange(of: isFieldFocused) { _, focused in
                    if focused { Task { selection = TextSelection(insertionPoint: palette.query.endIndex) } }
                }
                .onKeyPress(phases: [.down, .repeat], action: handle)
        }
        .padding(.horizontal, 14)
    }

    private var placeholder: String {
        switch palette.scope {
        case .assign where isPicking && compact: String(localized: "Search keycodes")
        case .assign where isPicking: String(localized: "Search \(KeycodeCatalog.entries.count) keycodes, or type a character")
        case .keys: String(localized: "Find a key by name")
        default: String(localized: "Search commands, keys, layers and settings")
        }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: model.moveHighlight(by: isGrid ? -columns : -1)
        case .downArrow: model.moveHighlight(by: isGrid ? columns : 1)
        case .leftArrow where isGrid: model.moveHighlight(by: -1)
        case .rightArrow where isGrid: model.moveHighlight(by: 1)
        // ⏎, ⌘⏎ and ⌫ act once per press: a held key must not assign again or drop the token.
        case .return where press.phase == .down: model.runHighlighted(advance: press.modifiers.contains(.command))
        case .tab where isPicking && press.modifiers.contains(.option): model.cycleSlot()
        case .tab where isPicking: model.cycleCategory(back: press.modifiers.contains(.shift))
        case KeyEquivalent("\u{19}") where isPicking: model.cycleCategory(back: true)  // ⇧⇥ arrives as back-tab
        // The field gets ⌫ as U+007F, not `KeyEquivalent.delete`.
        case KeyEquivalent("\u{7F}") where isPicking && palette.query.isEmpty && press.phase == .down: model.dropScopeToken()
        default: return .ignored
        }
        return .handled
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if items.isEmpty {
                    Text("No results").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 28)
                } else if isGrid {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: columns), spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            KeycodeTile(item: item, isHighlighted: index == palette.highlight)
                                .onTapGesture { model.run(item) }
                                .onHover { if $0 { model.palette?.highlight = index } }
                                .modifier(
                                    ResultAccessibility(item: item, isHighlighted: index == palette.highlight, run: { model.run(item) }))
                        }
                    }
                    .padding(8)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if !isPicking && (index == 0 || items[index - 1].group != item.group) {
                                Text(item.group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(EdgeInsets(top: 8, leading: 10, bottom: 4, trailing: 10))
                                    .accessibilityAddTraits(.isHeader)
                            }
                            PaletteRow(item: item, isHighlighted: index == palette.highlight)
                                .onTapGesture { model.run(item) }
                                .onHover { if $0 { model.palette?.highlight = index } }
                                .modifier(
                                    ResultAccessibility(item: item, isHighlighted: index == palette.highlight, run: { model.run(item) }))
                        }
                    }
                    .padding(6)
                }
            }
            .accessibilityLabel(Text("Results"))
            .onChange(of: palette.highlight) { _, index in
                if let id = items[safe: index]?.id { proxy.scrollTo(id) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if isPicking { Text(model.pickerCurrent).font(.caption.monospaced()).layoutPriority(1) }
            Spacer(minLength: 0)
            Text(hints).font(.caption)
        }
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .padding(.horizontal, 16)
    }

    private var hints: String {
        if !isPicking { return String(localized: "↑↓ move · ⏎ run · esc close") }
        return compact
            ? String(localized: "⏎ assign · ⌘⏎ & next · esc close")
            : String(localized: "↑↓ move · ⏎ assign · ⌘⏎ assign & next · ⇥ category · ⇧⌘R record · esc close")
    }
}

/// VoiceOver: each result is a button labelled "Left Bracket, KC_LBRC · KC_LEFT_BRACKET, Punctuation" (spec §11).
private struct ResultAccessibility: ViewModifier {
    var item: PaletteItem
    var isHighlighted: Bool
    var run: () -> Void

    static func label(_ item: PaletteItem) -> String {
        [item.title, item.detail, item.note ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.label(item))
            .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(item.isCurrent ? Text("Current value") : Text(verbatim: ""))
            .accessibilityAction { run() }
    }
}

private struct PaletteRow: View {
    var item: PaletteItem
    var isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            PaletteLeading(leading: item.leading, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if let note = item.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(item.detail)
                .font(item.group == .keycodes ? .caption.monospaced() : .callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if item.isCurrent {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(Highlight(isOn: isHighlighted))
        .contentShape(Rectangle())
    }
}

/// A 64 pt tile in a browsed category: the cap and its short code (spec §5.6).
private struct KeycodeTile: View {
    var item: PaletteItem
    var isHighlighted: Bool

    var body: some View {
        VStack(spacing: 3) {
            PaletteLeading(leading: item.leading, size: 38)
            Text(item.keycode.map { Legends.legend(for: $0).qmk.replacingOccurrences(of: "KC_", with: "") } ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 64, height: 64)
        .background(Highlight(isOn: isHighlighted))
        .overlay(alignment: .topTrailing) {
            if item.isCurrent {
                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.accentColor).padding(3)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct PaletteLeading: View {
    var leading: PaletteItem.Leading
    var size: CGFloat

    var body: some View {
        Group {
            switch leading {
            case let .cap(model): KeyCap(model: model, u: size)
            case let .chip(color): LayerChip(color: color, size: 12)
            case let .symbol(name): Image(systemName: name).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct Highlight: View {
    var isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isOn ? Color.accentColor.opacity(0.18) : .clear)
    }
}

/// Suggested plus the catalog's categories, with counts (spec §5.6).
private struct CategoryRail: View {
    var model: LayoutWindowModel
    var selected: KeycodeCategory?
    var compact: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach([nil] + KeycodeCategory.allCases.map(Optional.some), id: \.self) { category in
                        let title = category?.title ?? String(localized: "Suggested")
                        Button {
                            model.palette?.category = category
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: category?.symbolName ?? "star").frame(width: 18)
                                if !compact {
                                    Text(title).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(verbatim: "\(model.pickerCount(category))").monospacedDigit().foregroundStyle(.tertiary)
                                }
                            }
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 26, alignment: compact ? .center : .leading)
                            .background(Highlight(isOn: category == selected))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(title)
                        .accessibilityLabel(title)
                        .accessibilityAddTraits(category == selected ? .isSelected : [])
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            // ⇥ can select a category below the fold.
            .onChange(of: selected) { _, category in proxy.scrollTo(category) }
        }
    }
}

/// ⏎ and typing on the focused board open the picker on the selected key (spec §9.2, §5.5). A closed panel gives the
/// board focus, so arrows and ⏎ go on working.
struct BoardPickerKeys: ViewModifier {
    var session: EditSession
    var isFocused: FocusState<Bool>.Binding
    @Environment(\.layoutWindow) private var window

    func body(content: Content) -> some View {
        content
            .onKeyPress(.return, phases: .down) { press in
                press.modifiers.isEmpty ? open("") : .ignored
            }
            .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.symbols), phases: .down) { press in
                press.modifiers.isDisjoint(with: [.command, .control]) ? open(press.characters) : .ignored
            }
            .onChange(of: window?.boardFocusRequests) { isFocused.wrappedValue = true }
    }

    /// Not in the Lighting lens, whose letters are its tools.
    private func open(_ query: String) -> KeyPress.Result {
        guard let window, window.lens == .keys, session.selection.keyIndex != nil else { return .ignored }
        window.openKeycodePicker(prefilled: query)
        return .handled
    }
}

/// The selected cap in the picker preview state (dashed accent ring, the previewed legend at 75%) or the Record Key
/// state (pulsing red ring and a REC badge), spec §4.7. Drawn by the board above the key, following its rotation.
struct PickerCapOverlay: View {
    var board: BoardLayout
    var cap: CGFloat
    @Environment(\.layoutWindow) private var window
    @Environment(\.motion) private var motion
    @State private var dim = false

    var body: some View {
        if let window, let session = window.session, let index = session.selection.keyIndex, let frame = board.frames[safe: index] {
            let shape = RoundedRectangle(cornerRadius: 0.16 * cap, style: .continuous)
            ZStack {
                if let preview = window.pickerPreview {
                    shape.fill(LinearGradient(colors: [Tokens.capTop.color, Tokens.capBottom.color], startPoint: .top, endPoint: .bottom))
                    KeyCap(model: preview, u: cap, height: frame.size.height).opacity(0.75)
                    shape.inset(by: -1.5).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                } else if window.recorder != nil {
                    shape.inset(by: -2).stroke(Tokens.danger.color, lineWidth: 2)
                        .opacity(dim ? 0.35 : 1)
                        .onAppear {
                            guard !motion.reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
                        }
                        .onDisappear { dim = false }
                    Text(verbatim: "REC")
                        .font(.system(size: max(7, 0.11 * cap), weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 0.06 * cap)
                        .background(Capsule().fill(Tokens.danger.color))
                        .offset(y: -frame.size.height / 2)
                }
            }
            .frame(width: frame.size.width, height: frame.size.height)
            .rotationEffect(.degrees(frame.rotation))
            .position(frame.center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Fills the board, whose space the key frames are in.
            Color.clear
                .anchorPreference(key: PickerTarget.self, value: .bounds) { PickerTarget.Target(board: $0, layout: board, key: index) }
                .allowsHitTesting(false)
        }
    }
}
