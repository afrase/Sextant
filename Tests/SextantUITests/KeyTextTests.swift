import Foundation
import SextantDomain
import Testing

@testable import SextantUI

/// Readout, context-strip and VoiceOver text on the user's layout (spec §3.7, §4.11, §11).
struct KeyTextTests {
    let layout: KeyboardLayout
    var geometry: BoardGeometry { BoardDefinition.voyager.geometry(navigator: .right) }

    init() throws { layout = try KeyboardLayout(oryxJSON: #require(userLayoutData)) }

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
            KeyText.value(enter, layout: layout, layer: 0, index: 24, geometry: geometry)
                == "Dual-function. Tap sends Return. Hold activates layer 1, Sym+Num. Left thumb, outer key, key 24.")
        let z = Legends.legend(layout: layout, layer: 1, index: 19)
        #expect(KeyText.label(z, index: 19).hasSuffix(", inherited"))
        let value = KeyText.value(z, layout: layout, layer: 1, index: 19, geometry: geometry)
        #expect(value.hasPrefix("Transparent on Sym+Num. Acts as Z, hold Left Option, from Main."), "\(value)")
        #expect(value.hasSuffix("Left hand, bottom row, column 2, key 19."), "\(value)")
    }

    @Test func positions() {
        #expect(KeyText.position(geometry.key(51), in: geometry) == "Right thumb, outer key")
        #expect(KeyText.position(geometry.key(50), in: geometry) == "Right thumb, inner key")
        #expect(KeyText.position(geometry.key(24), in: geometry) == "Left thumb, outer key")
        #expect(KeyText.position(geometry.key(25), in: geometry) == "Left thumb, inner key")
        #expect(KeyText.position(geometry.key(12), in: geometry) == "Left hand, home row, far left")
        #expect(KeyText.position(geometry.key(43), in: geometry) == "Right hand, home row, far right")
        #expect(KeyText.position(geometry.key(0), in: geometry) == "Left hand, top row, far left")
        #expect(KeyText.position(geometry.key(14), in: geometry) == "Left hand, home row, column 3")
        #expect(KeyText.position(geometry.key(26), in: geometry) == "Right hand, top row, column 1")
        #expect(KeyText.position(geometry.key(31), in: geometry) == "Right hand, top row, far right")
    }

    /// Spec §7.3: the flash-mode cards name keys by what they show on Main and where they are, never by index.
    @Test func flashModeCards() throws {
        #expect(KeyText.resetButtonPlace(layout: layout, geometry: geometry) == "on the top edge of the left half, above the 3 key")
        let path = try #require(FlashPath.find(in: layout))
        let hold = KeyText.flashStep(path.holds[0], isHold: true, layout: layout, geometry: geometry)
        #expect(hold == ("Hold Space", "Right thumb, outer key"))
        let reset = KeyText.flashStep(path.reset, isHold: false, layout: layout, geometry: geometry)
        #expect(reset == ("Press the key that shows “-” on Main", "Right hand, top row, far right"))

        // Nothing under the button on the base layer, a plain layer key, and a Reset key over an empty base key.
        var bare = KeyboardLayout(title: "T", layers: [.transparent(title: "Base"), .transparent(title: "Nav")])
        #expect(
            KeyText.resetButtonPlace(layout: bare, geometry: geometry)
                == "on the top edge of the left half, above the top-row key in column 4")
        bare.updateKey(layer: 0, index: 24) { $0 = Key(tap: .momentary(1)) }
        bare.updateKey(layer: 1, index: 5) { $0 = Key(tap: .code("QK_BOOT")) }
        #expect(
            KeyText.flashStep(KeyRef(layer: 0, index: 24, slot: .tap), isHold: true, layout: bare, geometry: geometry).text == "Hold Nav")
        #expect(
            KeyText.flashStep(KeyRef(layer: 1, index: 5, slot: .tap), isHold: false, layout: bare, geometry: geometry)
                == ("Press the key", "Left hand, top row, column 6"))

        // A layer key is named by the layer it shows, in the text and under the button alike.
        bare.updateKey(layer: 0, index: 5) { $0 = Key(tap: .momentary(1)) }
        bare.updateKey(layer: 0, index: 3) { $0 = Key(tap: .momentary(1)) }
        #expect(
            KeyText.flashStep(KeyRef(layer: 1, index: 5, slot: .tap), isHold: false, layout: bare, geometry: geometry).text
                == "Press the key that shows “Nav” on Base")
        #expect(KeyText.resetButtonPlace(layout: bare, geometry: geometry) == "on the top edge of the left half, above the Nav key")
    }

    /// Spec §4.11: the left half row by row, its thumbs, then the right half and its thumbs.
    @Test func voiceOverReadingOrder() {
        let order = BoardView.readingOrder(geometry)
        func priorities(_ hand: BoardGeometry.Hand, _ cluster: BoardGeometry.Cluster) -> [Double] {
            geometry.keys.filter { $0.hand == hand && $0.cluster == cluster }.map { order[$0.index] }
        }
        #expect(order[0] == order.max(), "the top-left key reads first")
        let groups = [priorities(.left, .main), priorities(.left, .thumb), priorities(.right, .main), priorities(.right, .thumb)]
        #expect(groups.allSatisfy { !$0.isEmpty })
        for (earlier, later) in zip(groups, groups.dropFirst()) {
            #expect((earlier.min() ?? 0) > (later.max() ?? 0), "left rows, left thumbs, right rows, right thumbs")
        }
    }

    @Test func issueCapsuleText() {
        let issue = LayoutIssue(kind: .unknownKeycode("KC_FOO"), severity: .error, key: KeyRef(layer: 2, index: 45, slot: .tap))
        #expect(KeyText.issueText(issue, layout: layout) == "Unknown keycode KC_FOO on Brd+Sys · key 45 · Tap")
        #expect(KeyText.issueText(LayoutIssue(kind: .emptyCombo, severity: .warning, key: nil), layout: layout) == "Empty combo")
        let dance = LayoutIssue(kind: .notInTapDance, severity: .error, key: KeyRef(layer: 0, index: 3, slot: .doubleTap))
        #expect(KeyText.issueText(dance, layout: layout) == "Action can't run in a tap dance on Main · key 3 · Double tap")
    }

    /// A combo issue names its combo: its name, else its number.
    @Test func comboIssueText() {
        var combos = layout
        combos.combos = [
            Combo(id: "a", keyIndices: [1, 2], output: .code("KC_ESCAPE")),
            Combo(id: "b", name: "Save", keyIndices: [3, 4], output: .code("KC_S")),
        ]
        func text(_ kind: LayoutIssue.Kind, _ combo: String) -> String {
            KeyText.issueText(LayoutIssue(kind: kind, severity: .warning, key: nil, combo: combo), layout: combos)
        }
        #expect(text(.rollingNeighbors(1, 2), "a") == "Combo keys 1 and 2 are rolling neighbors · Combo 1")
        #expect(text(.duplicateComboTrigger, "b") == "Another combo uses the same keys · Save")
        #expect(text(.emptyCombo, "gone") == "Empty combo", "a combo that no longer exists isn't named")
    }
}

/// What each cap draws (spec §4.4, §4.5).
struct KeyCapModelTests {
    let layout: KeyboardLayout

    init() throws { layout = try KeyboardLayout(oryxJSON: #require(userLayoutData)) }

    @Test func bandsAndBars() {
        #expect(KeyCapModel(layout: layout, layer: 0, index: 24).band?.slot == .hold, "dual-function: hold band")
        #expect(KeyCapModel(layout: layout, layer: 0, index: 24).bar == nil, "a band replaces the bar")
        #expect(KeyCapModel(layout: layout, layer: 0, index: 24, mode: .qmk).band == nil, "QMK mode hides the band")
        let holdOnly = KeyCapModel(layout: layout, layer: 0, index: 18)
        #expect(holdOnly.isHoldOnly && holdOnly.bar != nil, "hold-only modifier: marker and bar")
        var layerHold = layout
        layerHold.layers[0].keys[18] = Key(hold: .momentary(1))
        let mo = KeyCapModel(layout: layerHold, layer: 0, index: 18)
        #expect(mo.legend.legend.primarySlot == .hold && !mo.isHoldOnly, "a hold-only layer key's caption already says hold")
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
        #expect(holder.isGhost && holder.isOwned && holder.isActivator, "the key holding the layer is ringed, hatched and haloed")
        #expect(!own.isActivator && !inherited.isActivator)
    }

    /// Spec §4.8: the LED dot shows when the key has its own LED colour, transparent or not.
    @Test func ledDotFollowsTheKeysOwnColour() {
        let glow = HexColor(red: 0.16, green: 1, blue: 1)
        var lit = layout
        lit.layers[1].keys[19] = Key(glowColor: glow)  // all-null: transparent (ADR 0015), with its own colour
        let ghost = KeyCapModel(layout: lit, layer: 1, index: 19)
        #expect(ghost.isGhost && ghost.ownGlow == glow)
        var below = layout
        below.layers[0].keys[19].glowColor = glow
        let inherited = KeyCapModel(layout: below, layer: 1, index: 19)
        #expect(inherited.isGhost && inherited.ownGlow == nil, "an inherited color is not the key's own")
    }

    /// Spec §4.8: the top-right corner shows one thing, issue > diff badge > LED dot; a combo number has the top left.
    @Test func cornerPriority() {
        let glow = HexColor(red: 0.16, green: 1, blue: 1)
        let added = CapDecoration.Mark(symbol: "plus.circle.fill", color: Tokens.success, accessibilityText: "Added")
        var lit = layout
        lit.layers[0].keys[0].glowColor = glow
        var model = KeyCapModel(layout: lit, layer: 0, index: 0)
        #expect(model.decoration == CapDecoration() && model.topRight == .led(glow), "undecorated: today's LED dot")
        model.decoration.badge = added
        #expect(model.topRight == .mark(added), "a diff badge beats the LED dot")
        model.decoration.number = CapDecoration.Mark(symbol: "3.circle.fill", color: Tokens.warning, accessibilityText: "Combo 3")
        #expect(model.topRight == .mark(added), "the combo number has its own corner")
        model.issue = .error
        #expect(model.topRight == .issue(.error), "an issue beats everything")

        lit.layers[0].keys[0] = Key(tap: .code("KC_NOPE"), glowColor: glow)
        var unknown = KeyCapModel(layout: lit, layer: 0, index: 0)
        unknown.decoration.badge = added
        #expect(unknown.topRight == .issue(.warning), "an unknown code is a warning")
    }
}
