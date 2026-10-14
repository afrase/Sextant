import Foundation
import SextantDomain
import Testing

/// App Layers' decision (spec §8.6, ADR 0054): which layer an app switch moves the keyboard to, if any.
struct AppLayerRulesTests {
    /// Main, Sym+Num and Brd+Sys, by id; "gone" is no layer of it.
    let layout = KeyboardLayout(
        title: "Three",
        layers: [("main", "Main"), ("sym", "Sym+Num"), ("brd", "Brd+Sys")].map {
            Layer(id: $0.0, title: $0.1, keys: Array(repeating: .transparent, count: 52))
        })

    let rules = AppLayerRules(
        isOn: true,
        rules: [
            AppLayerRule(bundleID: "xcode", name: "Xcode", layerID: "sym", leaving: .returnToMain),
            AppLayerRule(bundleID: "figma", name: "Figma", layerID: "brd", leaving: .stay),
            AppLayerRule(bundleID: "mail", name: "Mail", layerID: "brd", isEnabled: false),
            AppLayerRule(bundleID: "old", name: "Old", layerID: "gone", leaving: .returnToMain),
        ])

    /// (activated, previous) → layer, or nil for nothing sent.
    @Test(
        arguments: [
            // An app with a rule moves the keyboard to its layer, whatever came before.
            ("xcode", nil, 1), ("xcode", "safari", 1), ("figma", "xcode", 2), ("xcode", "figma", 1),
            // Leaving a Return to Main app for one without a rule goes back to layer 0; leaving a Stay app doesn't.
            ("safari", "xcode", 0), ("safari", "figma", nil),
            // Neither app has a rule.
            ("safari", "notes", nil), ("safari", nil, nil),
            // A disabled rule is no rule, coming or going.
            ("mail", "safari", nil), ("safari", "mail", nil), ("mail", "xcode", 0),
            // A rule whose layer the keyboard's layout lacks is no rule, coming or going: nothing is sent for it.
            ("old", "safari", nil), ("safari", "old", nil), ("old", "xcode", 0),
            // The same app again is its own rule, never a Return to Main.
            ("xcode", "xcode", 1),
        ] as [(String, String?, Int?)])
    func decides(activated: String, previous: String?, layer: Int?) {
        #expect(rules.target(activated: activated, previous: previous, in: layout) == layer)
    }

    @Test func theSwitchOffSendsNothing() {
        var off = rules
        off.isOn = false
        #expect(off.target(activated: "xcode", previous: nil, in: layout) == nil)
        #expect(off.target(activated: "safari", previous: "xcode", in: layout) == nil)
        #expect(!off.isActive)
    }

    @Test func activeNeedsTheSwitchAndAnEnabledRule() {
        #expect(rules.isActive)
        #expect(!AppLayerRules().isActive, "off by default")
        #expect(!AppLayerRules(isOn: true).isActive)
        let disabled = AppLayerRules(isOn: true, rules: [AppLayerRule(bundleID: "a", name: "A", layerID: "sym", isEnabled: false)])
        #expect(!disabled.isActive)
    }

    /// The layer is found by id, so a rule follows its layer when layers move, and is checked against the layout given:
    /// the one on the keyboard, as it was flashed.
    @Test func followsTheLayerById() {
        var moved = layout
        moved.layers.swapAt(1, 2)
        #expect(rules.target(activated: "xcode", previous: nil, in: moved) == 2)
        var flashedBefore = layout
        flashedBefore.layers.removeLast()
        #expect(rules.target(activated: "figma", previous: nil, in: flashedBefore) == nil, "Brd+Sys isn't on the keyboard")
    }

    @Test func oneRulePerApp() {
        var rules = AppLayerRules()
        let added = rules.add(AppLayerRule(bundleID: "xcode", name: "Xcode", layerID: "sym"))
        let addedAgain = rules.add(AppLayerRule(bundleID: "xcode", name: "Xcode", layerID: "brd"))
        #expect(added && !addedAgain)
        #expect(rules.rules.count == 1)
        rules.update(AppLayerRule(bundleID: "xcode", name: "Xcode", layerID: "brd", leaving: .stay))
        #expect(rules.rule(for: "xcode")?.layerID == "brd" && rules.rule(for: "xcode")?.leaving == .stay)
        rules.update(AppLayerRule(bundleID: "none", name: "None", layerID: "brd"))
        #expect(rules.rules.count == 1, "updating an app without a rule adds nothing")
        rules.remove("xcode")
        #expect(rules.rules.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode(AppLayerRules.self, from: data) == rules)
    }
}
