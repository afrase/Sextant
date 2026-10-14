import AppKit
import SextantApplication
import SextantDomain
import SwiftUI
import UniformTypeIdentifiers

/// The App Layers page (spec §8.6): the switch, what App Layers is doing now, and one rule per app. Rules are saved
/// beside the layout as they change, outside its content (ADR 0054).
struct AppLayersPage: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let appLayers = model.appLayers
        let rules = appLayers.rules(session.id)
        VStack(spacing: 0) {
            AppLayersHeader(model: model, session: session, rules: rules)
            if let switcher = appLayers.switcher, switcher.saveError(for: session.id) != nil {
                SaveFailedBar { switcher.retrySave(for: session.id) }
            }
            Divider()
            if let error = appLayers.switcher?.loadError(for: session.id) {
                ContentUnavailableView(
                    String(localized: "Sextant couldn’t read this layout’s App Layers"), systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: error.localizedDescription))
            } else if rules.rules.isEmpty {
                ContentUnavailableView {
                    Label("No app rules yet", systemImage: "macwindow.on.rectangle")
                } description: {
                    Text("Switch the keyboard’s layer automatically when you change apps.")
                } actions: {
                    AddAppMenu(model: model, session: session)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    NowCard(model: model, session: session)
                    AppRulesTable(model: model, session: session, rules: rules)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            Divider()
            Label(AppLayersText.footnote, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .navigationTitle(session.layout.title)
        .navigationSubtitle(String(localized: "App Layers"))
        .task(id: session.id) { await appLayers.switcher?.load(session.id) }
        .confirmationDialog(
            removingTitle(rules), isPresented: Binding(get: { appLayers.removing != nil }, set: { if !$0 { appLayers.removing = nil } }),
            presenting: appLayers.removing
        ) { bundleID in
            Button("Remove Rule", role: .destructive) { appLayers.remove(bundleID, from: session.id) }
        } message: { _ in
            Text("You can’t undo this.")
        }
        .fileImporter(
            isPresented: Binding(get: { appLayers.choosesApp }, set: { appLayers.choosesApp = $0 }), allowedContentTypes: [.application]
        ) { result in
            guard case let .success(url) = result else { return }
            Task { await appLayers.addApp(at: url, to: session.id, layout: session.layout) }
        }
    }
}

extension AppLayersPage {
    private func removingTitle(_ rules: AppLayerRules) -> String {
        let name = model.appLayers.removing.flatMap { rules.rule(for: $0)?.name } ?? ""
        return String(localized: "Remove the rule for \(name)?")
    }
}

/// The title, the switch and Add App….
private struct AppLayersHeader: View {
    var model: LayoutWindowModel
    var session: EditSession
    var rules: AppLayerRules

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("App Layers").font(.title2.weight(.semibold))
                Text("The keyboard moves to a layer when an app comes forward").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "Switch layers when you change apps",
                isOn: Binding(get: { rules.isOn }, set: { on in model.appLayers.edit(session.id) { $0.isOn = on } })
            )
            .toggleStyle(.switch)
            .disabled(rules.rules.isEmpty)
            // The empty state has its own.
            if !rules.rules.isEmpty { AddAppMenu(model: model, session: session) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// A rule change that didn't save: it holds until Sextant quits, and the next launch reads the rules from before. A switch
/// turned off that comes back on at the next launch would resume writes the user stopped, so this stays until it lands.
private struct SaveFailedBar: View {
    var retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.danger.color).accessibilityHidden(true)
            Text("Sextant couldn’t save these rules. They apply until Sextant quits; the next launch uses the ones from before.")
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Try Again", action: retry)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Add App…: the apps running now, then Choose… for any other.
struct AddAppMenu: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let appLayers = model.appLayers
        let taken = Set(appLayers.rules(session.id).rules.map(\.bundleID))
        Menu {
            Section("Running Apps") {
                ForEach(appLayers.runningApps) { app in
                    Button(app.name) { appLayers.add(app, to: session.id, layout: session.layout) }
                        .disabled(taken.contains(app.bundleID))
                }
            }
            Divider()
            Button("Choose…") { appLayers.choosesApp = true }
        } label: {
            Label("Add App…", systemImage: "plus")
        }
        .fixedSize()
        .disabled(appLayers.switcher == nil)
        .task { await appLayers.followRunningApps() }
    }
}

/// What App Layers is doing now (spec §8.6): the frontmost app's rule with the keyboard's layer, or why nothing moves.
private struct NowCard: View {
    var model: LayoutWindowModel
    var session: EditSession

    var body: some View {
        let switcher = model.appLayers.switcher
        let state = switcher?.state(for: session.id) ?? .off
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                line(state, switcher: switcher)
            }
            Spacer(minLength: 0)
            if state == .on, let layout = model.onKeyboard?.running?.layout, let layer = model.live?.activeLayer {
                LayerMap(layout: layout, layer: layer).frame(width: 200, height: 76)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func line(_ state: AppLayersState, switcher: AppLayerSwitcher?) -> some View {
        switch state {
        case .off:
            let rules = model.appLayers.rules(session.id)
            Label(
                rules.isOn
                    ? String(localized: "Every rule is turned off, so the keyboard stays where it is.")
                    : String(localized: "Turn on “Switch layers when you change apps” to use these rules."),
                systemImage: "pause.circle"
            )
            .foregroundStyle(.secondary)
        case let .paused(pause):
            HStack(spacing: 10) {
                Label(pause.text, systemImage: "pause.circle")
                // Starting Live View pairs with the keyboard: only ever on the user's click (ADR 0057).
                if pause == .refused(.liveOff), model.canGoLive {
                    Button("Turn On Live View") { model.isLive = true }.controlSize(.small)
                }
            }
        case .on:
            if let applied = switcher?.applied(for: session.id) {
                Text(verbatim: AppLayersText.applied(applied)).font(.headline)
            } else if let last = switcher?.history.first {
                Text("Last switch: \(AppLayersText.entry(last))")
            } else {
                Text("On. The keyboard moves when an app with a rule comes forward.")
            }
        }
    }
}

/// One row per app (spec §8.6): the app, its bundle id, the layer, When Leaving and Enabled.
private struct AppRulesTable: View {
    var model: LayoutWindowModel
    var session: EditSession
    var rules: AppLayerRules

    var body: some View {
        let appLayers = model.appLayers
        let layout = session.layout
        Table(rules.rules, selection: Binding(get: { appLayers.selection }, set: { appLayers.selection = $0 })) {
            TableColumn("App") { rule in
                HStack(spacing: 6) {
                    AppIcon(appLayers: appLayers, bundleID: rule.bundleID, size: 16)
                    Text(verbatim: rule.name).lineLimit(1)
                }
            }
            .width(min: 80, ideal: 90)
            // Cut at the head: a bundle id's end ("dt.Xcode") tells apps apart, its "com." doesn't.
            TableColumn("Bundle ID") { rule in
                Text(verbatim: rule.bundleID).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head).help(rule.bundleID)
            }
            .width(min: 100, ideal: 115)
            TableColumn("Layer") { rule in AppRuleLayerPicker(model: model, session: session, rule: rule) }
                .width(min: 110, ideal: 120)
            TableColumn("When Leaving") { rule in
                AppRuleLeavingPicker(model: model, session: session, rule: rule, layout: layout)
            }
            .width(min: 130, ideal: 130)
            TableColumn("Enabled") { rule in
                Toggle(
                    "Enabled",
                    isOn: Binding(get: { rule.isEnabled }, set: { on in appLayers.edit(session.id) { $0.update(rule.with(enabled: on)) } })
                )
                .labelsHidden()
                .accessibilityLabel(Text("\(rule.name) enabled"))
            }
            .width(56)
        }
        .contextMenu(forSelectionType: String.self) { selected in
            if let bundleID = selected.first {
                Button("Remove Rule") { appLayers.removing = bundleID }
            }
        }
        .onDeleteCommand { appLayers.removing = appLayers.selection }
        .frame(minHeight: 120)
        .accessibilityLabel(Text("App rules"))
    }
}

/// A rule's layer, by chip and name. A layer deleted since the rule was made shows as missing until another is chosen.
struct AppRuleLayerPicker: View {
    var model: LayoutWindowModel
    var session: EditSession
    var rule: AppLayerRule

    var body: some View {
        let layers = session.layout.layers
        let isDeleted = !layers.contains { $0.id == rule.layerID }
        HStack(spacing: 4) {
            if isDeleted {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.warning.color)
                    .help(String(localized: "This rule’s layer was deleted."))
                    .accessibilityHidden(true)
            }
            Picker(
                "Layer",
                selection: Binding(
                    get: { rule.layerID },
                    set: { id in model.appLayers.edit(session.id) { $0.update(rule.with(layerID: id)) } })
            ) {
                ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                    Text(verbatim: "\(index) · \(layer.title)").tag(layer.id)
                }
                if isDeleted {
                    Text("Deleted layer").tag(rule.layerID)
                }
            }
            .labelsHidden()
            .accessibilityLabel(Text("\(rule.name) layer"))
        }
    }
}

/// A rule's When Leaving: back to the base layer, or stay.
struct AppRuleLeavingPicker: View {
    var model: LayoutWindowModel
    var session: EditSession
    var rule: AppLayerRule
    var layout: KeyboardLayout

    var body: some View {
        Picker(
            "When leaving",
            selection: Binding(
                get: { rule.leaving },
                set: { leaving in model.appLayers.edit(session.id) { $0.update(rule.with(leaving: leaving)) } })
        ) {
            ForEach(AppLayerRule.Leaving.allCases, id: \.self) { Text(verbatim: AppLayersText.leaving($0, in: layout)).tag($0) }
        }
        .labelsHidden()
        .accessibilityLabel(Text("\(rule.name) when leaving"))
    }
}

/// An app's icon (``AppLayersModel/icon(for:)``).
struct AppIcon: View {
    var appLayers: AppLayersModel
    var bundleID: String
    var size: CGFloat

    var body: some View {
        Image(nsImage: appLayers.icon(for: bundleID))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension AppLayerRule {
    func with(layerID: String? = nil, leaving: Leaving? = nil, enabled: Bool? = nil) -> Self {
        var rule = self
        rule.layerID = layerID ?? rule.layerID
        rule.leaving = leaving ?? rule.leaving
        rule.isEnabled = enabled ?? rule.isEnabled
        return rule
    }
}
