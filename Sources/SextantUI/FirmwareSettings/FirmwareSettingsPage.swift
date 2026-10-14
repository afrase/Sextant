import SextantApplication
import SextantDomain
import SwiftUI

/// Which firmware settings the page shows, and how they read (spec §8.8).
enum FirmwareSettings {
    /// Every section with the settings Sextant offers (``SettingsCatalog/offers(_:)``) that apply to this layout's
    /// Navigator, in catalog order. Navigator is always there: it starts with the choice of module and side (ADR 0035).
    static func sections(for layout: KeyboardLayout, catalog: SettingsCatalog = .voyager) -> [SettingsSection] {
        catalog.sections.compactMap { section in
            var section = section
            section.settings = section.settings.filter { catalog.offers($0) && applies($0, to: layout, catalog: catalog) }
            return section.settings.isEmpty && section.id != navigator ? nil : section
        }
    }

    /// The sections the page's search and Modified only filter leave: matching settings only, and the Navigator section
    /// while it has one or the query names the module choice.
    static func sections(
        for layout: KeyboardLayout, query: String, modifiedOnly: Bool, catalog: SettingsCatalog = .voyager
    ) -> [SettingsSection] {
        let changed = Set(layout.changedSettings(in: catalog).map(\.id))
        return sections(for: layout, catalog: catalog).compactMap { section in
            var section = section
            section.settings = section.settings.filter {
                SettingsCatalog.matches($0, query) && (!modifiedOnly || changed.contains($0.id))
            }
            let keeps = section.id == navigator && showsNavigatorChoice(query: query, modifiedOnly: modifiedOnly)
            return section.settings.isEmpty && !keeps ? nil : section
        }
    }

    /// The Navigator's module and side rows show unfiltered, or when the query names them.
    static func showsNavigatorChoice(query: String, modifiedOnly: Bool) -> Bool {
        guard !modifiedOnly else { return false }
        let words = [title(nil), title(.trackpad), title(.trackball), title(.left), title(.right)]
        return SettingsCatalog.matches(([String(localized: "Navigator"), String(localized: "Side")] + words).joined(separator: " "), query)
    }

    /// The Navigator section's id.
    static let navigator = "navigator"

    /// "Trackpad", or "None" without a Navigator.
    static func title(_ kind: NavigatorConfig.Kind?) -> String {
        switch kind {
        case nil: String(localized: "None")
        case .trackpad?: String(localized: "Trackpad")
        case .trackball?: String(localized: "Trackball")
        case .knob?: String(localized: "Knob")
        }
    }

    static func title(_ side: NavigatorConfig.Side) -> String {
        side == .left ? String(localized: "Left") : String(localized: "Right")
    }

    /// The board, the Navigator kind (Navigator settings only with a Navigator) and a setting it depends on.
    private static func applies(_ setting: Setting, to layout: KeyboardLayout, catalog: SettingsCatalog) -> Bool {
        if let kinds = setting.navigatorKinds, !kinds.contains(layout.navigator?.kind.rawValue ?? "") { return false }
        guard let dependency = setting.dependsOn, let other = catalog.setting(id: dependency.id) else { return true }
        return (layout.storedValue(of: other) ?? other.unsetValue) == dependency.value
    }

    /// Where a slider starts when it is switched on: its default, else the bottom of its range.
    static func onValue(_ setting: Setting) -> SettingValue {
        setting.defaultValue ?? .number(setting.range?.lowerBound ?? 0)
    }

    // MARK: Coupling (KeyboardLayout.Coupling)

    /// Settings that do nothing while another is off, so their rows are dimmed until it is on.
    static let follows: [String: String] = [
        "autoshiftTimeout": "autoshift", "autoshiftModifiers": "autoshift", "autoshiftEnableSpecial": "autoshift",
        "autoshiftEnableNumeric": "autoshift", "autoshiftEnableAlpha": "autoshift", "autoshiftEnableTab": "autoshift",
        "chordalHoldExcludeThumbs": "chordalHold",
    ]

    /// What changing this setting also changes, said inline under its row.
    static func couplingNote(_ id: String) -> String? {
        switch id {
        case "tappingTerm":
            String(localized: "Over \(Int(KeyboardLayout.Coupling.permissiveHoldTerm)) ms, this also turns on Permissive hold.")
        case "chordalHold": String(localized: "Turning it on or off does the same to Exclude thumbs.")
        case "autoshift":
            String(localized: "Turning it on with punctuation, numbers and letters off turns them on; turning all three off turns it off.")
        default: nil
        }
    }

    /// A section's footnote.
    static func footer(_ section: String) -> String? {
        switch section {
        case navigator: String(localized: "Choose the module attached to your keyboard. The change takes effect after you build and flash.")
        // ADR 0040: at the catalog defaults nothing is written, so the board's own mouse-key values apply.
        case "mouse":
            String(localized: "At their defaults, the keyboard's own mouse key speeds apply. Changing one replaces them with yours.")
        case "international": String(localized: "Only the input sources Sextant has keycodes for are listed.")
        default: nil
        }
    }
}

/// The Firmware Settings page (spec §8.8): a grouped Form over the settings catalog, with search (⌘F) and a Modified
/// only filter. Every change is one undo step, together with the settings it turns on or off.
struct FirmwareSettingsPage: View {
    var model: LayoutWindowModel
    var session: EditSession
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let filter = model.firmwareSettings
        let query = filter.trimmedQuery
        let sections = FirmwareSettings.sections(for: session.layout, query: query, modifiedOnly: filter.modifiedOnly)
        VStack(spacing: 0) {
            header(sections)
            Divider()
            ScrollViewReader { proxy in
                Group {
                    if sections.isEmpty {
                        empty(query: query)
                    } else {
                        Form {
                            ForEach(sections) { self.section($0, query: query).id($0.id) }
                        }
                        .formStyle(.grouped)
                    }
                }
                // Initial too: the palette sets a target before the page appears.
                .onChange(of: model.settingsScrollTarget, initial: true) {
                    guard let target = model.settingsScrollTarget else { return }
                    model.settingsScrollTarget = nil
                    guard sections.contains(where: { $0.id == target }) else {
                        // A section the filter hides: show everything, then scroll once the Form has it.
                        filter.clearFilters()
                        Task { withAnimation { proxy.scrollTo(target, anchor: .top) } }
                        return
                    }
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
        .onChange(of: filter.searchFocusRequests) { isSearchFocused = true }
    }

    private func header(_ sections: [SettingsSection]) -> some View {
        let filter = model.firmwareSettings
        return HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Firmware Settings").font(.title2.weight(.semibold))
                // One line, shorter when narrow: a wrapping line here makes the window's height depend on its width,
                // which AppKit's constraint passes never settle.
                let lines = subtitles(sections)
                ViewThatFits(in: .horizontal) {
                    ForEach(lines, id: \.self) { Text($0).lineLimit(1) }
                }
                .font(.callout).foregroundStyle(.secondary)
                .accessibilityLabel(lines[0])
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            SearchField(query: Bindable(filter).query, isFocused: $isSearchFocused)
                .frame(minWidth: 140, idealWidth: 220, maxWidth: 240)
            Toggle("Modified only", isOn: Bindable(filter).modifiedOnly)
                .toggleStyle(.checkbox)
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// "Built into the firmware · 3 changed from defaults", or what the filter shows: "11 settings match ‘hold’". Then
    /// shorter forms for a narrow window; the last one is truncated if even it doesn't fit.
    private func subtitles(_ sections: [SettingsSection]) -> [String] {
        let filter = model.firmwareSettings
        let query = filter.trimmedQuery
        let count = sections.reduce(0) { $0 + $1.settings.count }
        switch (query.isEmpty, filter.modifiedOnly) {
        case (true, false):
            let changed = session.layout.changedSettings().count
            return changed == 1
                ? [String(localized: "Built into the firmware · 1 changed from defaults"), String(localized: "1 changed from defaults")]
                : [
                    String(localized: "Built into the firmware · \(changed) changed from defaults"),
                    String(localized: "\(changed) changed from defaults"),
                ]
        case (true, true):
            return [count == 1 ? String(localized: "1 changed setting") : String(localized: "\(count) changed settings")]
        case (false, false):
            return [
                count == 1 ? String(localized: "1 setting matches ‘\(query)’") : String(localized: "\(count) settings match ‘\(query)’"),
                count == 1 ? String(localized: "1 match") : String(localized: "\(count) matches"),
            ]
        case (false, true):
            return [
                count == 1
                    ? String(localized: "1 changed setting matches ‘\(query)’")
                    : String(localized: "\(count) changed settings match ‘\(query)’"),
                count == 1 ? String(localized: "1 match") : String(localized: "\(count) matches"),
            ]
        }
    }

    @ViewBuilder
    private func empty(query: String) -> some View {
        if query.isEmpty {
            ContentUnavailableView {
                Label("No Changed Settings", systemImage: "slider.horizontal.3")
            } description: {
                Text("Every setting has its default value.")
            } actions: {
                Button("Show All Settings") { model.firmwareSettings.modifiedOnly = false }
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    /// A section's rows; Navigator starts with the module and side.
    private func section(_ section: SettingsSection, query: String) -> some View {
        Section {
            if section.id == FirmwareSettings.navigator,
                FirmwareSettings.showsNavigatorChoice(query: query, modifiedOnly: model.firmwareSettings.modifiedOnly)
            {
                NavigatorChoice(session: session)
            }
            ForEach(section.settings) { SettingRow(setting: $0, session: session, filter: model.firmwareSettings) }
        } header: {
            Text(section.title)
        } footer: {
            if let footer = FirmwareSettings.footer(section.id) {
                Text(footer).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// The page's search field: a magnifying glass, the field, and a clear button while it has text. Esc clears it.
private struct SearchField: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Search"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// The Navigator's module (None, Trackpad, Trackball) and the half it is on, laid out like setting rows. Changing the
/// module resets its options; moving it keeps them. Each change is one undo step.
private struct NavigatorChoice: View {
    var session: EditSession

    var body: some View {
        let navigator = session.layout.navigator
        // An imported knob shows as it is; Sextant can't build one, so it isn't offered otherwise.
        let kinds: [NavigatorConfig.Kind?] = [nil, .trackpad, .trackball] + (navigator?.kind == .knob ? [.knob] : [])
        VStack(alignment: .leading, spacing: 6) {
            Picker("Navigator", selection: Binding(get: { navigator?.kind }, set: { session.setNavigator($0) })) {
                ForEach(kinds, id: \.self) { Text(FirmwareSettings.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("The trackpad or trackball module on your keyboard, if any.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        VStack(alignment: .leading, spacing: 6) {
            // No Navigator, no side selected.
            let side = Binding(get: { navigator?.side }, set: { if let side = $0 { session.moveNavigator(to: side) } })
            Picker("Side", selection: side) {
                ForEach([NavigatorConfig.Side.left, .right], id: \.self) { Text(FirmwareSettings.title($0)).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .disabled(navigator == nil)
            Text("The half of the keyboard it's attached to.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// One setting: title (accent dot and semibold when changed), its control, Sextant's description, what it changes
/// with it, and a footer with the default, Reset to Default and the setting id. Dimmed while the setting it follows
/// is off.
private struct SettingRow: View {
    var setting: Setting
    var session: EditSession
    var filter: FirmwareSettingsModel

    var body: some View {
        let stored = session.layout.storedValue(of: setting)
        let value = stored ?? setting.unsetValue
        let isChanged = stored.map { $0 != setting.unsetValue } ?? false
        VStack(alignment: .leading, spacing: 6) {
            control(value, title: title(isChanged))
            Text(setting.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let note = FirmwareSettings.couplingNote(setting.id) {
                Label(note, systemImage: "link")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if isChanged {
                    Text("Default \(setting.format(setting.unsetValue))").foregroundStyle(.secondary)
                    Button("Reset to Default") { session.setSetting(setting.id, to: nil) }.buttonStyle(.link)
                }
                Spacer()
                Text(verbatim: setting.id).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .disabled(isWaiting)
    }

    /// The setting this one follows is off (``FirmwareSettings/follows``).
    private var isWaiting: Bool {
        guard let id = FirmwareSettings.follows[setting.id], let leader = SettingsCatalog.voyager.setting(id: id) else { return false }
        return (session.layout.storedValue(of: leader) ?? leader.unsetValue) != .bool(true)
    }

    private func title(_ isChanged: Bool) -> some View {
        HStack(spacing: 6) {
            if isChanged {
                Circle().fill(.tint).frame(width: 6, height: 6).accessibilityHidden(true)
            }
            Text(setting.title).fontWeight(isChanged ? .semibold : .regular)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isChanged ? String(localized: "Changed") : "")
    }

    @ViewBuilder
    private func control(_ value: SettingValue?, title: some View) -> some View {
        switch setting.control {
        case .toggle:
            Toggle(isOn: Binding(get: { value?.boolValue ?? false }, set: { session.setSetting(setting.id, to: .bool($0)) })) { title }
        case .slider where setting.isToggleable:
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    isOn: Binding(
                        get: { value != nil }, set: { session.setSetting(setting.id, to: $0 ? FirmwareSettings.onValue(setting) : nil) })
                ) {
                    title
                }
                if let number = value?.doubleValue { NumberControl(setting: setting, value: number, session: session) }
            }
        case .slider:
            LabeledContent {
                NumberControl(setting: setting, value: value?.doubleValue ?? 0, session: session).frame(maxWidth: 320)
            } label: {
                title
            }
        case .layerSelect:
            LabeledContent {
                LayerSelect(
                    setting: setting, selected: value.flatMap { if case let .integers(l) = $0 { l } else { nil } } ?? [], session: session)
            } label: {
                title
            }
        case .animationSelect:
            AnimationSelect(setting: setting, value: value, session: session, isExpanded: Bindable(filter).showsAnimations) { title }
        }
    }
}

/// A slider with a value field and unit. A drag commits once, when it ends; arrow keys and VoiceOver commit each step.
/// The field commits on ⏎. Values are clamped to the setting's range in whole steps (the firmware takes integers and
/// refuses values out of range).
private struct NumberControl: View {
    var setting: Setting
    var value: Double
    var session: EditSession
    /// The value under the pointer while dragging; nil otherwise.
    @State private var draft: Double?
    @State private var isDragging = false

    var body: some View {
        let range = setting.range ?? 0...100
        HStack(spacing: 8) {
            // Whole steps without `step:`, which draws a tick per step (a solid bar over 1000 of them).
            Slider(
                value: Binding(get: { draft ?? value }, set: { isDragging ? (draft = $0.rounded()) : commit($0) }), in: range
            ) {
                Text(setting.title)
            } onEditingChanged: { editing in
                isDragging = editing
                guard !editing, let draft else { return }
                commit(draft)
                self.draft = nil
            }
            .labelsHidden()
            if setting.marks.isEmpty {
                TextField(value: Binding(get: { draft ?? value }, set: { commit($0) }), format: .number.grouping(.never)) {
                    Text(setting.title)
                }
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                Text(verbatim: setting.unitSymbol).foregroundStyle(.secondary).frame(minWidth: 24, alignment: .leading)
            } else {
                Text(setting.format(.number(draft ?? value))).monospacedDigit().frame(minWidth: 56, alignment: .leading)
            }
        }
    }

    private func commit(_ number: Double) {
        let range = setting.range ?? 0...100
        session.setSetting(setting.id, to: .number(min(max(number.rounded(), range.lowerBound), range.upperBound)))
    }
}

/// Picks layers (Navigator aim, turbo and drag-scroll layers).
private struct LayerSelect: View {
    var setting: Setting
    var selected: [Int]
    var session: EditSession

    var body: some View {
        let layers = session.layout.layers
        Menu(selected.isEmpty ? String(localized: "None") : selected.compactMap { layers[safe: $0]?.title }.joined(separator: ", ")) {
            ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                Toggle(
                    String(localized: "\(index) · \(layer.title)"),
                    isOn: Binding(
                        get: { selected.contains(index) },
                        set: { on in
                            let next = on ? (selected + [index]).sorted() : selected.filter { $0 != index }
                            session.setSetting(setting.id, to: .integers(next))
                        }))
            }
        }
        .fixedSize()
    }
}
