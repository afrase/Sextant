import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// The keycode picker and command palette (spec §5.6, §5.7), driven through the window model.
@MainActor
struct PaletteTests {
    @Test func pickerRanksGlyphsCodesAndWords() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19)
        model.openKeycodePicker("[")
        #expect(model.paletteItems.first?.keycode?.code == "KC_LBRC", "exact glyph")
        model.palette?.query = "KC_LEFT_BRACKET"
        #expect(model.paletteItems.first?.keycode?.code == "KC_LBRC", "alias")
        model.palette?.query = "vol"
        #expect(Set(model.paletteItems.prefix(2).compactMap(\.keycode?.code)) == ["KC_AUDIO_VOL_UP", "KC_AUDIO_VOL_DOWN"], "word")
    }

    @Test func layerFunctionsComeOncePerLayerAndArgumentKeysStayOut() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19)
        model.openKeycodePicker()
        model.palette?.category = .layers
        let actions = model.paletteItems.compactMap(\.keycode)
        #expect(actions.filter { $0.code == "MO" }.map(\.layer) == [0, 1, 2])
        #expect(!actions.contains { $0.code == "LM" }, "needs modifiers")
        #expect(model.pickerCount(.layers) == actions.count)
        model.palette?.category = .modifiers
        #expect(!model.paletteItems.contains { $0.keycode?.code == "OSM" })
    }

    @Test func holdSuggestsModifiersAndOtherLayers() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19, slot: .hold)
        model.openKeycodePicker()
        let actions = model.paletteItems.compactMap(\.keycode)
        #expect(actions.contains(KeyAction(code: "KC_LEFT_SHIFT")))
        #expect(actions.filter(\.isLayerAction).map(\.layer) == [1, 2], "not the key's own layer")
    }

    @Test func returnAssignsKeepingTheChordAndCommandReturnAdvances() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)  // Z, hold Left Option
        session.setModifiers([.leftCommand])
        model.openKeycodePicker("[")
        #expect(model.pickerPreview?.legend.legend.primary?.qmk == "LGUI(KC_LBRC)", "the cap previews the result")
        #expect(session.selectedAction?.code == "KC_Z", "previewing doesn't edit")
        model.runHighlighted()
        #expect(session.selectedAction == KeyAction(code: "KC_LBRC", modifiers: [.leftCommand]))
        #expect(model.palette == nil, "⏎ closes the picker")
        #expect(model.recentKeycodes.first == KeyAction(code: "KC_LBRC"))

        model.openKeycodePicker("esc")
        model.runHighlighted(advance: true)
        #expect(session.layout.key(layer: 0, index: 19)?.tap?.code == "KC_ESCAPE")
        #expect(session.selection.keyIndex == 20, "the next key in reading order")
        #expect(model.palette?.query.isEmpty == true, "⌘⏎ keeps the picker open for the next key")

        // A one-shot modifier's modifiers aren't a chord for the keycode that replaces it.
        session.setAction(KeyAction(code: "OSM", modifiers: [.leftShift]))
        model.openKeycodePicker("a")
        model.runHighlighted()
        #expect(session.selectedAction == KeyAction(code: "KC_A"))
    }

    @Test func arrowsTabAndOptionTabNavigate() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19, slot: .hold)
        model.openKeycodePicker()
        model.moveHighlight(by: 100)
        #expect(model.palette?.highlight == model.paletteItems.count - 1, "↓ stops at the last result")
        model.cycleSlot()
        #expect(model.session?.selection.slot == .doubleTap)
        #expect(model.palette?.highlight == 0, "Suggested differs per slot")
        #expect(model.pickerPreview != nil)
        model.cycleCategory(back: true)
        #expect(model.palette?.category == KeycodeCategory.allCases.last, "⇧⇥ from Suggested wraps")
        model.cycleCategory(back: false)
        #expect(model.palette?.category == nil)
    }

    @Test func paletteRunsCommandsAndRemembersThem() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.openPalette(query: "new layer")
        let first = try #require(model.paletteItems.first)
        #expect(first.title == "New Layer")
        model.run(first)
        #expect(session.layout.layers.count == 4)
        #expect(model.palette == nil)
        model.openPalette()
        #expect(model.paletteItems.first?.group == .recent)
        #expect(model.paletteItems.first?.title == "New Layer")
    }

    @Test func aPastedOryxLinkOffersImportFirst() async throws {
        let model = try await openUserLayout()
        model.openPalette(query: "https://configure.zsa.io/voyager/layouts/KlgM7/40xJ7M/0")
        #expect(model.paletteItems.first?.group == .importOryx)
        model.palette?.query = "KlgM7/40xJ7M"
        #expect(model.paletteItems.first?.group == .importOryx)
        model.palette?.query = "esc"
        #expect(!model.paletteItems.contains { $0.group == .importOryx }, "a bare word is not a link")
    }

    @Test func findKeyJumpsToTheLayerAndKey() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.openPalette(.keys, query: "reset")
        model.run(try #require(model.paletteItems.first))
        #expect(session.selection.layer == 2 && session.selection.keyIndex == 31, "Reset on Brd+Sys")
        #expect(model.palette == nil)
    }

    @Test func aKeycodeInThePaletteEntersTheAssignScope() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19)
        model.openPalette(query: "[")
        model.run(try #require(model.paletteItems.first { $0.group == .keycodes }))
        #expect(model.isPicking)
        #expect(model.paletteItems[safe: model.palette?.highlight ?? -1]?.keycode?.code == "KC_LBRC")
    }

    @Test func pickerAndRecordKeyEndEachOther() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19)
        model.startRecording()
        #expect(model.recorder != nil)
        model.openKeycodePicker()
        #expect(model.recorder == nil && model.isPicking)
        model.dropScopeToken()
        #expect(model.palette?.scope == .general, "⌫ on an empty field drops the token")
        model.startRecording()
        #expect(model.palette == nil && model.recorder != nil)
    }

    @Test func paletteSearchRanksExactPrefixWordSubstring() {
        #expect(PaletteSearch.score("main", ["Main"]) > PaletteSearch.score("main", ["Mainly"]))
        #expect(PaletteSearch.score("lay", ["Layer 1"]) > PaletteSearch.score("lay", ["New Layer"]))
        #expect(PaletteSearch.score("layer", ["New Layer"]) > PaletteSearch.score("ayer", ["New Layer"]))
        #expect(PaletteSearch.score("new duplicate", ["New Layer"]) == 0, "every word must match")
    }
}
