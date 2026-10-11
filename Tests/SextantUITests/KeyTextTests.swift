import Foundation
import SextantDomain
import Testing

@testable import SextantUI

/// Readout, context-strip and VoiceOver text on the user's layout (spec §3.7, §4.11, §11).
struct KeyTextTests {
    let layout = (try? KeyboardLayout(oryxJSON: userLayoutData ?? Data())) ?? KeyboardLayout(title: "", layers: [])
    var geometry: BoardGeometry { BoardDefinition.voyager.geometry(navigator: .right) }

    @Test func readout() {
        #expect(KeyText.readout(layout: layout, layer: 0, isFollowing: false) == "Layer 0 · base · 52 keys")
        #expect(KeyText.readout(layout: layout, layer: 1, isFollowing: false) == "Layer 1 · held by ⏎ (key 24) · 47 own · 5 inherited")
        #expect(KeyText.readout(layout: layout, layer: 2, isFollowing: false).hasPrefix("Layer 2 · held by Space (key 51)"))
        #expect(KeyText.readout(layout: layout, layer: 2, isFollowing: true) == "LIVE · following the keyboard")
    }

    @Test func contextStripLines() {
        func line(_ layer: Int, _ index: Int) -> (text: String, spoken: String) {
            KeyText.stripLine(Legends.legend(layout: layout, layer: layer, index: index))
        }
        #expect(line(0, 24).text == "⏎ · hold Sym+Num")
        #expect(line(1, 24).text == "Inherits ⏎")
        #expect(line(1, 24).spoken == "inherits Return")
        #expect(line(0, 19).text == "Z · hold ⌥")
        #expect(line(1, 0).text == "Esc")
    }

    @Test func voiceOverLabelAndValue() {
        let enter = Legends.legend(layout: layout, layer: 0, index: 24)
        #expect(KeyText.label(enter, index: 24) == "Return, hold for Sym+Num")
        #expect(
            KeyText.value(layout: layout, layer: 0, index: 24, geometry: geometry)
                == "Dual-function. Tap sends Return. Hold activates layer 1, Sym+Num. Left thumb, key 24.")
        let z = Legends.legend(layout: layout, layer: 1, index: 19)
        #expect(KeyText.label(z, index: 19).hasSuffix(", inherited"))
        let value = KeyText.value(layout: layout, layer: 1, index: 19, geometry: geometry)
        #expect(value.hasPrefix("Transparent on Sym+Num. Acts as Z, hold Left Option, from Main."), "\(value)")
        #expect(value.hasSuffix("Left hand, bottom row, column 2, key 19."), "\(value)")
    }

    @Test func positions() {
        #expect(KeyText.position(geometry.key(51), in: geometry) == "Right thumb")
        #expect(KeyText.position(geometry.key(0), in: geometry) == "Left hand, top row, column 1")
        #expect(KeyText.position(geometry.key(14), in: geometry) == "Left hand, home row, column 3")
    }

    @Test func issueCapsuleText() {
        let issue = LayoutIssue(kind: .unknownKeycode("KC_FOO"), severity: .error, key: KeyRef(layer: 2, index: 45, slot: .tap))
        #expect(KeyText.issueText(issue, layout: layout) == "Unknown keycode KC_FOO on Brd+Sys · key 45 · Tap")
        #expect(KeyText.issueText(LayoutIssue(kind: .emptyCombo, severity: .warning, key: nil), layout: layout) == "Empty combo")
    }
}

/// What each cap draws (spec §4.4, §4.5).
struct KeyCapModelTests {
    let layout = (try? KeyboardLayout(oryxJSON: userLayoutData ?? Data())) ?? KeyboardLayout(title: "", layers: [])

    @Test func bandsAndBars() {
        #expect(KeyCapModel(layout: layout, layer: 0, index: 24).band?.slot == .hold, "dual-function: hold band")
        #expect(KeyCapModel(layout: layout, layer: 0, index: 24).bar == nil, "a band replaces the bar")
        #expect(KeyCapModel(layout: layout, layer: 0, index: 24, mode: .qmk).band == nil, "QMK mode hides the band")
        let holdOnly = KeyCapModel(layout: layout, layer: 0, index: 18)
        #expect(holdOnly.isHoldOnly && holdOnly.bar != nil, "hold-only modifier: marker and bar")
        let reset = KeyCapModel(layout: layout, layer: 2, index: 31)
        #expect(reset.bar?.light == Tokens.danger.light, "Reset gets a red bar")

        var dance = layout
        dance.layers[0].keys[0] = Key(tap: .code("KC_A"), doubleTap: .code("KC_B"))
        let model = KeyCapModel(layout: dance, layer: 0, index: 0)
        #expect(model.kind == .tapDance && model.band?.slot == .doubleTap && model.bar != nil, "tap dance: 2× band and its bar")
    }

    @Test func layerRingsAndGhosts() {
        #expect(KeyCapModel(layout: layout, layer: 0, index: 0).layerTones == nil, "the base layer has no rings")
        let own = KeyCapModel(layout: layout, layer: 1, index: 0)
        #expect(own.isOwned && !own.isGhost)
        let inherited = KeyCapModel(layout: layout, layer: 1, index: 19)
        #expect(inherited.isGhost && !inherited.isOwned && inherited.kind == .dualFunction, "shows the inherited kind")
        let holder = KeyCapModel(layout: layout, layer: 1, index: 24)
        #expect(holder.isGhost && holder.isOwned, "the key holding the layer is ringed and hatched")
    }
}
