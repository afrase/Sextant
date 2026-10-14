import SextantApplication
import SextantDomain
import SwiftUI

/// The rule inspector (spec §8.6, §3.8): the selected rule's details, then the recent switches, app names only.
struct AppLayersInspector: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let appLayers = model.appLayers
        let rules = appLayers.rules(session.id)
        if let bundleID = appLayers.selection, let rule = rules.rule(for: bundleID) {
            editor(rule)
        } else {
            Text(rules.rules.isEmpty ? "Add an app to make its first rule." : "Select a rule to see its details.")
                .foregroundStyle(.secondary)
        }
        Divider()
        recentSwitches(appLayers.switcher?.history ?? [])
    }

    private func editor(_ rule: AppLayerRule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIcon(bundleID: rule.bundleID, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: rule.name).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(verbatim: rule.bundleID).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Group {
                LabeledContent("Layer") { AppRuleLayerPicker(model: model, session: session, rule: rule).fixedSize() }
                LabeledContent("When leaving") {
                    AppRuleLeavingPicker(model: model, session: session, rule: rule, layout: session.layout).fixedSize()
                }
                LabeledContent("Enabled") {
                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { rule.isEnabled },
                            set: { on in model.appLayers.edit(session.id) { $0.update(rule.with(enabled: on)) } })
                    )
                    .labelsHidden()
                }
            }
            .labeledContentStyle(InspectorRowStyle())
            if let note = note(rule) {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(summary(rule)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Remove Rule") { model.appLayers.remove(rule.bundleID, from: session.id) }
        }
    }

    /// Why the rule can't move the keyboard although it is on: its layer is gone, or the keyboard's build lacks it.
    private func note(_ rule: AppLayerRule) -> String? {
        guard let index = AppLayerRules.layerIndex(of: rule, in: session.layout) else {
            return String(localized: "Its layer was deleted. Choose another layer for it to do anything.")
        }
        guard let running = model.onKeyboard?.running, running.entry.id == session.id,
            AppLayerRules.layerIndex(of: rule, in: running.layout) == nil
        else { return nil }
        let name = session.layout.layers[index].title
        return String(localized: "\(name) isn’t on the keyboard yet. Build & Flash to use this rule.")
    }

    /// "When Xcode comes forward, the keyboard moves to Sym+Num. When you leave it for an app without a rule, it returns to
    /// Main."
    private func summary(_ rule: AppLayerRule) -> String {
        let layers = session.layout.layers
        let layer = layers.first { $0.id == rule.layerID }?.title ?? String(localized: "its layer")
        let comes = String(localized: "When \(rule.name) comes forward, the keyboard moves to \(layer).")
        let leaves =
            switch rule.leaving {
            case .returnToMain:
                String(
                    localized:
                        "When you leave it for an app without a rule, it returns to \(layers.first?.title ?? String(localized: "layer 0"))."
                )
            case .stay: String(localized: "When you leave it for an app without a rule, it stays there.")
            }
        return "\(comes) \(leaves)"
    }

    private func recentSwitches(_ history: [AppLayerSwitcher.Switch]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Switches").font(.headline)
            if history.isEmpty {
                Text("None since Sextant opened.").foregroundStyle(.secondary)
            } else {
                ForEach(history) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: AppLayersText.entry(entry)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(entry.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text("App names only, kept in memory until Sextant quits.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
