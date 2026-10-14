import SextantApplication
import SextantDomain
import SwiftUI

/// The lighting animations built into the firmware (`disabledAnimations` stores the ones left out): how many are in,
/// and under a disclosure a checkbox per animation with Include All and Include None. Each change is one undo step.
struct AnimationSelect<Title: View>: View {
    var setting: Setting
    var value: SettingValue?
    var session: EditSession
    @Binding var isExpanded: Bool
    @ViewBuilder var title: Title

    var body: some View {
        let excluded = excludedIDs
        let included = setting.options.count { !excluded.contains($0.id) }
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(setting.options) { option in
                        Toggle(
                            option.title,
                            isOn: Binding(
                                get: { !excluded.contains(option.id) },
                                set: { on in store(on ? excluded.subtracting([option.id]) : excluded.union([option.id])) })
                        )
                        .toggleStyle(.checkbox)
                    }
                }
                HStack {
                    Button("Include All") { store([]) }.disabled(included == setting.options.count)
                    Button("Include None") { store(Set(setting.options.map(\.id))) }.disabled(included == 0)
                }
            }
            .padding(.top, 6)
        } label: {
            LabeledContent {
                Text("\(included) of \(setting.options.count) included").monospacedDigit().foregroundStyle(.secondary)
            } label: {
                title
            }
        }
    }

    private var excludedIDs: Set<String> {
        if case let .strings(ids)? = value { Set(ids) } else { [] }
    }

    /// Stores the animations left out in the catalog's order, keeping ids Sextant doesn't know after them.
    private func store(_ excluded: Set<String>) {
        let known = Set(setting.options.map(\.id))
        let unknown: [String] = if case let .strings(ids)? = value { ids.filter { !known.contains($0) } } else { [] }
        let ordered = setting.options.map(\.id).filter(excluded.contains) + unknown
        session.setSetting(setting.id, to: .strings(ordered))
    }
}
