import SextantApplication
import SextantDomain
import SwiftUI

/// Which firmware settings the page shows, and how they read (spec §8.8).
enum FirmwareSettings {
    /// The MVP core sections (spec §13.5 step 11), with the settings that apply to this layout's board and Navigator.
    /// Navigator is always there: it starts with the choice of module and side (ADR 0035).
    /// shortcut: RGB shows only its timeout and the other nine sections are left out; v1 shows all 101 settings.
    static func sections(for layout: KeyboardLayout, catalog: SettingsCatalog = .voyager) -> [SettingsSection] {
        catalog.sections.compactMap { section in
            var section = section
            section.settings = section.settings.filter { isCore($0, in: section.id) && applies($0, to: layout, catalog: catalog) }
            return section.settings.isEmpty && section.id != navigator ? nil : section
        }
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

    private static func isCore(_ setting: Setting, in section: String) -> Bool {
        switch section {
        case "tapping", "oneshot", "debounce", "navigator": true
        case "rgb": setting.id == "rgbTimeout"
        default: false
        }
    }

    /// The board, the Navigator kind (Navigator settings only with a Navigator) and a setting it depends on.
    private static func applies(_ setting: Setting, to layout: KeyboardLayout, catalog: SettingsCatalog) -> Bool {
        guard setting.appliesToVoyager else { return false }
        if let kinds = setting.navigatorKinds, !kinds.contains(layout.navigator?.kind.rawValue ?? "") { return false }
        guard let dependency = setting.dependsOn, let other = catalog.setting(id: dependency.id) else { return true }
        return (layout.storedValue(of: other) ?? other.unsetValue) == dependency.value
    }

    /// Where a slider starts when it is switched on: its default, else the bottom of its range.
    static func onValue(_ setting: Setting) -> SettingValue {
        setting.defaultValue ?? .number(setting.range?.lowerBound ?? 0)
    }
}

/// The Firmware Settings page (spec §8.8): a grouped Form over the settings catalog. Every change is one undo step.
struct FirmwareSettingsPage: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let changed = session.layout.changedSettings().count
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Firmware Settings").font(.title2.weight(.semibold))
                    Text(
                        changed == 1
                            ? "Built into the firmware · 1 changed from defaults"
                            : "Built into the firmware · \(changed) changed from defaults"
                    )
                    .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            ScrollViewReader { proxy in
                Form {
                    ForEach(FirmwareSettings.sections(for: session.layout)) { self.section($0).id($0.id) }
                }
                .formStyle(.grouped)
                // Initial too: the palette sets a target before the page appears.
                .onChange(of: model.settingsScrollTarget, initial: true) {
                    guard let target = model.settingsScrollTarget else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                    model.settingsScrollTarget = nil
                }
            }
        }
    }

    /// A section's rows; Navigator starts with the module and side and ends with a footnote.
    private func section(_ section: SettingsSection) -> some View {
        Section {
            if section.id == FirmwareSettings.navigator { NavigatorChoice(session: session) }
            ForEach(section.settings) { SettingRow(setting: $0, session: session) }
        } header: {
            Text(section.title)
        } footer: {
            if section.id == FirmwareSettings.navigator {
                Text("Choose the module attached to your keyboard. The change takes effect after you build and flash.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
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

/// One setting: title (accent dot and semibold when changed), its control, Sextant's description, and a footer with
/// the default, Reset to Default and the setting id.
private struct SettingRow: View {
    var setting: Setting
    var session: EditSession

    var body: some View {
        let stored = session.layout.storedValue(of: setting)
        let value = stored ?? setting.unsetValue
        let isChanged = stored.map { $0 != setting.unsetValue } ?? false
        VStack(alignment: .leading, spacing: 6) {
            control(value, title: title(isChanged))
            Text(setting.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            // shortcut: no MVP core setting uses it (RGB animations come with all 101 settings in v1).
            LabeledContent {
                Text(setting.format(value)).foregroundStyle(.secondary)
            } label: {
                title
            }
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
