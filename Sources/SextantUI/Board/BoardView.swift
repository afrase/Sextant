import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// The keyboard for the session's current layer, fitted into whatever space it gets (spec §3.3, §4).
///
/// The frame is a pure function of the available size and the layout's board (ADR 0017), so nothing outside
/// the board area can move it. The board is one tab stop: arrows move the selection, ⇥ / ⇧⇥ change slot,
/// ⌫ makes the key transparent and esc deselects (§9.2).
public struct BoardView: View {
    var session: EditSession
    var mode: LegendMode
    /// Live and build issues; keys on the shown layer get a ring and a badge.
    var issues: [KeyRef: LayoutIssue.Severity]
    var pressed: PressedKeys?
    /// The kind the footer's kind key points at; every other kind dims.
    var highlightedKind: KeyKind?
    var showsGrid: Bool
    var capRange: ClosedRange<CGFloat>

    @FocusState private var isFocused: Bool
    /// The board got focus from a click, not the keyboard: the outline is a keyboard-focus cue, so it stays hidden.
    @State private var focusedByPointer = false
    @Namespace private var rotors
    @Environment(\.motion) private var motion
    @Environment(\.colorSchemeContrast) private var contrast
    /// The Lighting lens brush: a click or drag paints instead of selecting (spec §2.2, §6.2).
    @Environment(\.brush) private var lensBrush
    @Environment(\.swapsKeys) private var swapsKeys
    /// Keys the current paint stroke has crossed; they preview the brush until the stroke lands as one undo step.
    @State private var stroke: [Int] = []
    /// True while a stroke is live. SwiftUI resets it however the stroke ends, so a cancelled one (no `onEnded`) stops
    /// previewing, and the next stroke starts from nothing.
    @GestureState private var isPainting = false
    @Environment(\.layoutWindow) private var window
    /// A pick takes clicks first (ADR 0037), so it stops painting and swapping until it ends.
    private var hasBoardPick: Bool { window?.boardPick != nil }
    private var brush: Brush? { hasBoardPick ? nil : lensBrush }

    public init(
        session: EditSession, mode: LegendMode = .symbols, issues: [KeyRef: LayoutIssue.Severity] = [:], pressed: PressedKeys? = nil,
        highlightedKind: KeyKind? = nil, showsGrid: Bool = true, capRange: ClosedRange<CGFloat> = 36...76
    ) {
        self.session = session
        self.mode = mode
        self.issues = issues
        self.pressed = pressed
        self.highlightedKind = highlightedKind
        self.showsGrid = showsGrid
        self.capRange = capRange
    }

    /// Cap side for a board area (spec §3.3). The spec's `pitch = min((W − 48) / 15, (H − 48) / 6.7)` uses the
    /// Voyager's size in pitch units; any board passes its own (ADR 0017). `cap = pitch / 1.11`, clamped.
    static func capSize(for area: CGSize, boardUnits: CGSize, range: ClosedRange<CGFloat>) -> CGFloat {
        let pitch = min((area.width - 48) / boardUnits.width, (area.height - 48) / boardUnits.height)
        return min(max(pitch / 1.11, range.lowerBound), range.upperBound)
    }

    public var body: some View {
        let layout = session.layout
        let layer = session.selection.layer
        let models = capModels()
        GeometryReader { proxy in
            let geometry = session.geometry
            let cap = Self.capSize(for: proxy.size, boardUnits: geometry.bounds.size, range: capRange)
            let board = geometry.layout(keySize: cap, spacing: cap * 0.11)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.46)
            let origin = CGPoint(x: center.x - board.size.width / 2, y: center.y - board.size.height / 2)
            ZStack(alignment: .topLeading) {
                BenchBackdrop(
                    boardRect: CGRect(origin: origin, size: board.size), pitch: board.pitch,
                    gridAnchor: gridAnchor(board, geometry, origin), wash: models.first?.layerTones, layer: layer, showsGrid: showsGrid)
                keys(board, models: models, cap: cap)
                    .frame(width: board.size.width, height: board.size.height)
                    .keySwapGesture(session, board: board)
                    .environment(\.swapsKeys, swapsKeys && !hasBoardPick)
                    // The board draws its own focus ring (spec §11): the selection glow, or this outline before a key is chosen.
                    .overlay {
                        if isFocused && session.selection.keyIndex == nil && !focusedByPointer {
                            RoundedRectangle(cornerRadius: 0.3 * cap, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                                .padding(-0.3 * cap)
                                .allowsHitTesting(false)
                        }
                    }
                    // A child's simultaneous gesture still beats this one, so the swap is off outside the Keys lens (ADR 0029).
                    .highPriorityGesture(paintStroke(board), isEnabled: brush != nil)
                    .position(center)
            }
        }
        .simultaneousGesture(SpatialTapGesture().onEnded { _ in focusedByPointer = true })
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onChange(of: isFocused) { if !isFocused { focusedByPointer = false } }
        .onMoveCommand(perform: move)
        .onKeyPress(keys: [.tab, Self.backTab], phases: .down) { press in
            // ⌃⇥ / ⌃⇧⇥ leave the board, as they leave a text view.
            press.modifiers.contains(.control) ? .ignored : cycleSlot(back: press.key == Self.backTab || press.modifiers.contains(.shift))
        }
        .onKeyPress(.delete) {
            // Not under a pick's prompt, which says what the keys do now.
            guard session.selection.keyIndex != nil, !hasBoardPick else { return .ignored }
            session.makeTransparent()
            return .handled
        }
        .modifier(BoardPickerKeys(isFocused: $isFocused))
        .onExitCommand { if let window { window.escapeBoard() } else { session.select(key: nil) } }
        // A pick starting, or the board appearing for one (Assign to Key leaves the Macros page), focuses the board, so
        // ⏎ picks the selected key and esc cancels (spec §9.2, §9.3).
        .onChange(of: hasBoardPick, initial: true) { if hasBoardPick { isFocused = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(localized: "Keyboard, \(layout.layers[safe: layer]?.title ?? "") layer, \(layout.keyCount) keys")
        )
        .accessibilityRotor(Text("Layers")) {
            // Each entry needs its own target, so entry n lands on key n of the layer it switches to.
            ForEach(Array(layout.layers.prefix(layout.keyCount).enumerated()), id: \.offset) { index, item in
                AccessibilityRotorEntry(Text(verbatim: item.title), id: index, in: rotors) { session.select(layer: index) }
            }
        }
        .accessibilityRotor(Text("Key kinds")) {
            ForEach(KeyKind.allCases.compactMap { kind in models.first { $0.legend.ownKind == kind } }, id: \.index) { model in
                AccessibilityRotorEntry(Text(verbatim: model.legend.ownKind.title), id: model.index, in: rotors)
            }
        }
        .accessibilityRotor(Text("Issues")) {
            ForEach(models.filter { $0.issue != nil }, id: \.index) { model in
                AccessibilityRotorEntry(Text(verbatim: KeyText.label(model.legend, index: model.index)), id: model.index, in: rotors)
            }
        }
        .accessibilityRotor(Text("Painted keys")) {
            // Lighting lens only; an optional rotor needs macOS 27, so other lenses get an empty one.
            ForEach(brush == nil ? [] : models.filter { layout.key(layer: layer, index: $0.index)?.glowColor != nil }, id: \.index) {
                model in
                AccessibilityRotorEntry(Text(verbatim: KeyText.label(model.legend, index: model.index)), id: model.index, in: rotors)
            }
        }
    }

    // MARK: Keys

    private func keys(_ board: BoardLayout, models: [KeyCapModel], cap: CGFloat) -> some View {
        let layout = session.layout
        let layer = session.selection.layer
        let order = Self.readingOrder(session.geometry)
        return ZStack(alignment: .topLeading) {
            if layout.navigator != nil, let nav = board.navigator {
                NavigatorDisc(diameter: nav.diameter, kind: layout.navigator?.kind)
                    .position(nav.center)
            }
            BoardCanvas(layout: board) { frame in
                if let model = models[safe: frame.index], let brush {
                    let own =
                        isPainting && stroke.contains(frame.index) ? brush.color : layout.key(layer: layer, index: frame.index)?.glowColor
                    LitKeyCap(
                        model: model, light: KeyLight(own: own, layer: layout.layers[safe: layer]?.color), u: cap,
                        press: pressed?.state(frame.index)
                    )
                    .accessibilityHint(brush.color == nil ? Text("Erases the key's own color.") : Text("Paints with the brush."))
                    .accessibilityAction { session.paint(brush.color, keys: [frame.index]) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilitySortPriority(order[safe: frame.index] ?? 0)
                    .accessibilityRotorEntry(id: frame.index, in: rotors)
                } else if let model = models[safe: frame.index] {
                    let value = KeyText.value(
                        model.legend, layout: layout, layer: layer, index: frame.index, geometry: session.geometry,
                        decoration: model.decoration)
                    BoardKey(model: model, u: cap, height: frame.size.height, press: pressed?.state(frame.index))
                        .onTapGesture { select(frame.index) }
                        .help(value)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(KeyText.label(model.legend, index: frame.index))
                        .accessibilityValue(value)
                        .accessibilityHint(window?.boardPick.map { Text($0.prompt) } ?? Text("Press Return to change. Actions available."))
                        .accessibilityAction { select(frame.index) }
                        .accessibilityAddTraits(frame.index == session.selection.keyIndex ? [.isButton, .isSelected] : .isButton)
                        .accessibilitySortPriority(order[safe: frame.index] ?? 0)
                        .accessibilityRotorEntry(id: frame.index, in: rotors)
                        .accessibilityActions { keyActions(model) }
                }
            }
            selectionRing(board, cap: cap)
            PickerCapOverlay(board: board, cap: cap)
        }
        .animation(SextantMotion.layerChange, value: layer)
    }

    /// Click or drag across keys to paint them, hit-testing the key polygons; one stroke is one undo step (spec §6.2).
    private func paintStroke(_ board: BoardLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPainting) { drag, painting, _ in
                if !painting { stroke = [] }
                painting = true
                if let index = board.keyIndex(at: drag.location), !stroke.contains(index) { stroke.append(index) }
            }
            .onEnded { _ in
                if let brush { session.paint(brush.color, keys: stroke) }
                stroke = []
            }
    }

    /// VoiceOver custom actions (spec §4.11).
    @ViewBuilder private func keyActions(_ model: KeyCapModel) -> some View {
        let index = model.index
        if let window {
            Button("Change Tap") {
                session.select(key: index, slot: .tap)
                window.openKeycodePicker()
            }
            Button("Change Hold") {
                session.select(key: index, slot: .hold)
                window.openKeycodePicker()
            }
            Button("Record Key") {
                session.select(key: index)
                window.startRecording()
            }
        }
        if !model.isGhost { Button("Make Transparent") { session.makeTransparent(index: index) } }
        if model.legend.ownKind != .disabled { Button("Disable") { session.disable(index: index) } }
        if model.legend.isInherited { Button("Override on This Layer") { session.overrideInherited(index: index) } }
        Button("Show on Other Layers") { session.select(key: index) }
        Button("Copy QMK Expression") { session.copyQMKExpression(index: index) }
    }

    /// One ring that moves between keys, following their rotation (spec §4.7, §10.6).
    @ViewBuilder private func selectionRing(_ board: BoardLayout, cap: CGFloat) -> some View {
        // The picker preview and Record Key draw their own rings instead (§4.7).
        if let index = session.selection.keyIndex, board.frames.indices.contains(index), window?.pickerPreview == nil,
            window?.recorder == nil
        {
            let frame = board.frames[index]
            let quiet = contrast == .increased || motion.reduceMotion
            let width: CGFloat = contrast == .increased || (isFocused && quiet) ? 3 : 2
            let outset = 2.5 + width
            RoundedRectangle(cornerRadius: 0.16 * cap + outset, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: width)
                .frame(width: frame.size.width + outset * 2, height: frame.size.height + outset * 2)
                .shadow(color: isFocused && !quiet ? Color.accentColor.opacity(0.35) : .clear, radius: 4)
                .rotationEffect(.degrees(frame.rotation))
                .position(frame.center)
                .animation(motion.selection, value: index)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func capModels() -> [KeyCapModel] {
        let layer = session.selection.layer
        var severity: [Int: LayoutIssue.Severity] = [:]
        for (ref, s) in issues where ref.layer == layer && severity[ref.index] != .error { severity[ref.index] = s }
        return (0..<session.layout.keyCount).map { index in
            var model = KeyCapModel(layout: session.layout, layer: layer, index: index, mode: mode, issue: severity[index])
            model.isDimmed = highlightedKind.map { $0 != model.legend.ownKind } ?? false
            if let window { model.decoration = window.capDecoration(layer: layer, index: index) }
            return model
        }
    }

    /// VoiceOver reads the left half row by row, its thumbs, then the right half and its thumbs (spec §4.11).
    nonisolated static func readingOrder(_ geometry: BoardGeometry) -> [Double] {
        let keys = geometry.keys
        let sorted = keys.sorted {
            ($0.hand == .right ? 1 : 0, $0.cluster == .thumb ? 1 : 0, $0.row, $0.center.x)
                < ($1.hand == .right ? 1 : 0, $1.cluster == .thumb ? 1 : 0, $1.row, $1.center.x)
        }
        var priority = Array(repeating: 0.0, count: keys.count)
        for (rank, key) in sorted.enumerated() where priority.indices.contains(key.index) {
            priority[key.index] = Double(keys.count - rank)
        }
        return priority
    }

    /// A point on the key-pitch grid, in board-area coordinates, so the bench grid lines up with the keys.
    private func gridAnchor(_ board: BoardLayout, _ geometry: BoardGeometry, _ origin: CGPoint) -> CGPoint {
        guard let frame = board.frames.first, let shape = geometry.keys.first else { return origin }
        return CGPoint(
            x: origin.x + frame.center.x - shape.center.x * board.pitch, y: origin.y + frame.center.y - shape.center.y * board.pitch)
    }

    // MARK: Keyboard

    private static let backTab = KeyEquivalent("\u{19}")

    private func select(_ index: Int) {
        if let window { window.click(key: index) } else { session.select(key: index) }
        isFocused = true
    }

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: session.moveSelection(.left)
        case .right: session.moveSelection(.right)
        case .up: session.moveSelection(.up)
        case .down: session.moveSelection(.down)
        @unknown default: break
        }
    }

    private func cycleSlot(back: Bool) -> KeyPress.Result {
        guard let key = session.selection.keyIndex else { return .ignored }
        let slots = KeySlot.allCases
        let current = slots.firstIndex(of: session.selection.slot) ?? 0
        session.select(key: key, slot: slots[(current + (back ? slots.count - 1 : 1)) % slots.count])
        return .handled
    }
}

/// One cap on the board. Hover is local and the live press is read from this key's own state, so neither
/// redraws the rest of the board (spec §13.3 item 6).
private struct BoardKey: View {
    var model: KeyCapModel
    var u: CGFloat
    var height: CGFloat
    var press: PressedKeys.KeyState?
    @State private var isHovered = false

    var body: some View {
        KeyCap(model: model, u: u, height: height, isPressed: press?.isDown ?? false, isHovered: isHovered, glows: true)
            .equatable()
            .onHover { isHovered = $0 }
    }
}

/// A gesture in progress that takes the board's key clicks instead of selection (spec §9.3 step 4): choosing a combo's
/// members, or Assign to Key. Its feature makes it; the lens lane shows its prompt and esc cancels it (ADR 0037).
struct BoardPick {
    /// The lens lane's text: "Click 2–6 keys, then Choose Output · esc cancels".
    var prompt: String
    /// Takes a clicked key's index; returns true when the pick is done.
    var onPick: @MainActor (Int) -> Bool
    /// Runs when the pick ends unfinished.
    var onCancel: @MainActor () -> Void = {}
}

extension EditSession {
    /// Copies the key's own QMK expression (`LT(1, KC_ENTER)`, `KC_TRNS`) to the pasteboard (⌥⇧⌘C).
    func copyQMKExpression(index: Int? = nil) {
        guard let i = index ?? selection.keyIndex, let key = layout.key(layer: selection.layer, index: i) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Legends.qmkExpression(for: key), forType: .string)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
