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
        model.openKeycodePicker(prefilled: "[")
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

    /// A firmware setting row opens the Firmware Settings page at its section; the palette floats over the page too.
    @Test func aSettingRowGoesToItsSection() async throws {
        let model = try await openUserLayout()
        model.openPalette(query: "tapping term")
        let row = try #require(model.paletteItems.first { $0.id == "setting-tappingTerm" })
        model.run(row)
        #expect(model.palette == nil && model.destination == .firmwareSettings && model.firmwareSettings.scrollTarget == "tapping")
    }

    /// The Navigator has a row too (ADR 0035), and Navigator settings read the Navigator's options.
    @Test func theNavigatorRowFollowsTheLayout() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.openPalette(query: "trackball")
        #expect(model.paletteItems.first { $0.id == "setting-navigator" }?.detail == "None")
        session.setNavigator(.trackpad)
        session.moveNavigator(to: .left)
        session.setSetting("automouseTime", to: .number(800))
        model.openPalette(query: "auto-mouse release")
        #expect(model.paletteItems.first { $0.id == "setting-automouseTime" }?.detail == "800 ms · changed")
        model.openPalette(query: "side")
        #expect(model.paletteItems.contains { $0.id == "setting-navigator" }, "the user's words: change sides")
        model.openPalette(query: "navigator")
        let row = try #require(model.paletteItems.first { $0.id == "setting-navigator" })
        #expect(row.detail == "Trackpad · Left")
        model.run(row)
        #expect(model.palette == nil && model.destination == .firmwareSettings && model.firmwareSettings.scrollTarget == "navigator")
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
        model.openKeycodePicker(prefilled: "[")
        #expect(model.pickerPreview?.legend.legend.primary?.qmk == "LGUI(KC_LBRC)", "the cap previews the result")
        #expect(session.selectedAction?.code == "KC_Z", "previewing doesn't edit")
        model.runHighlighted()
        #expect(session.selectedAction == KeyAction(code: "KC_LBRC", modifiers: [.leftCommand]))
        #expect(model.palette == nil, "⏎ closes the picker")
        #expect(model.picker.recentKeycodes.first == KeyAction(code: "KC_LBRC"))

        model.openKeycodePicker(prefilled: "esc")
        model.runHighlighted(advance: true)
        #expect(session.layout.key(layer: 0, index: 19)?.tap?.code == "KC_ESCAPE")
        #expect(session.selection.keyIndex == 20, "the next key in reading order")
        #expect(model.palette?.query.isEmpty == true, "⌘⏎ keeps the picker open for the next key")

        // A one-shot modifier's modifiers aren't a chord for the keycode that replaces it.
        session.setAction(KeyAction(code: "OSM", modifiers: [.leftShift]))
        model.openKeycodePicker(prefilled: "a")
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

        // A toggle stays in Recent under its new title.
        model.openPalette(query: "hide inspector")
        model.run(try #require(model.paletteItems.first))
        model.openPalette()
        #expect(model.paletteItems.first?.group == .recent)
        #expect(model.paletteItems.first?.title == "Show Inspector")
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

    @Test func commandPaletteShortcutTogglesLikeSpotlight() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19)
        model.togglePalette()
        #expect(model.palette?.scope == .general)
        model.togglePalette()
        #expect(model.palette == nil, "⌘K again closes it")
        model.openKeycodePicker()
        model.togglePalette()
        #expect(model.palette?.scope == .general, "from the picker it switches")
        model.openPalette(.keys)
        model.togglePalette()
        #expect(model.palette?.scope == .general, "from Find Key too")
    }

    /// A click keeps the panel open on the panel, and on a key while picking (it retargets the picker).
    @Test func aClickOutsideClosesExceptOnAKeyWhilePicking() {
        let layout = BoardGeometry.voyager.layout(keySize: 60, spacing: 6.6)
        let board = CGRect(origin: CGPoint(x: 200, y: 100), size: layout.size)
        let hits = PanelHits(panel: CGRect(x: 1400, y: 50, width: 400, height: 300), board: board, layout: layout)
        let key = layout.frames[7].center
        let onKey = CGPoint(x: board.minX + key.x, y: board.minY + key.y)
        #expect(hits.keepsOpen(CGPoint(x: 1500, y: 100), picking: false))
        #expect(hits.keepsOpen(onKey, picking: true))
        #expect(!hits.keepsOpen(onKey, picking: false), "a key closes the general palette")
        #expect(!hits.keepsOpen(CGPoint(x: board.midX, y: board.minY + 2), picking: true), "the gap between the halves")
        #expect(!hits.keepsOpen(CGPoint(x: 10, y: 10), picking: true))
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

    @Test func theHookStaysAnUnappliedNoArgumentMethod() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19)
        // The inspector passes it as `Button(action: model.openKeycodePicker)`.
        let open: @MainActor () -> Void = model.openKeycodePicker
        open()
        #expect(model.isPicking)
    }

    @Test func onlyHIDKeycodesKeepTheChordAndNoKeycodeKeepsAColour() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        session.setAction(KeyAction(code: "KC_1", modifiers: [.leftShift]))
        model.assign(KeyAction(code: "QK_BOOT"))
        #expect(session.selectedAction == KeyAction(code: "QK_BOOT"), "LSFT(QK_BOOT) would be QK_KB_0")
        session.setAction(KeyAction(code: "RGB", color: HexColor(hex: "#FF0000")))
        model.assign(KeyAction(code: "KC_A"))
        #expect(session.selectedAction?.color == nil)
    }

    @Test func changingScopeStartsAtTheTopWithNoCategory() async throws {
        let model = try await openUserLayout()
        model.session?.select(key: 19)
        model.openPalette()
        model.palette?.highlight = 1
        let changeHold = try #require(model.paletteItems[safe: 1])
        #expect(changeHold.title == "Change Hold")
        model.run(changeHold)
        #expect(model.isPicking && model.session?.selection.slot == .hold)
        #expect(model.palette?.highlight == 0)
        model.palette?.category = .letters
        model.dropScopeToken()
        #expect(model.palette?.category == nil)
    }

    @Test func recentLayerKeycodesSkipDeletedLayers() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19, slot: .hold)
        model.assign(.momentary(2))
        session.deleteLayer(2)
        model.openKeycodePicker()
        #expect(!model.paletteItems.contains { $0.keycode?.layer == 2 })
    }

    /// The column at the 1120 × 640 and 1440 × 900 windows, with sidebar and inspector.
    @Test(arguments: [CGSize(width: 640, height: 588), CGSize(width: 960, height: 848)])
    func thePickerNeverCoversItsKey(column: CGSize) {
        let geometry = BoardGeometry.voyager
        // The board area is the column less its 44 + 36 pt top and 76 + 32 pt bottom bands; BoardView centres it at 46%.
        let area = CGSize(width: column.width, height: column.height - 188)
        let cap = BoardView.capSize(for: area, boardUnits: geometry.bounds.size, range: 36...76)
        let board = geometry.layout(keySize: cap, spacing: cap * 0.11)
        let origin = CGPoint(x: (area.width - board.size.width) / 2, y: 80 + area.height * 0.46 - board.size.height / 2)
        for frame in board.frames {
            let key = frame.boundingBox.offsetBy(dx: origin.x, dy: origin.y)
            let panel = PaletteHost.pickerFrame(beside: key, in: column)
            #expect(!panel.insetBy(dx: -7.5, dy: 0).intersects(key), "key \(frame.index) stays 8 pt clear")
            #expect(CGRect(origin: .zero, size: column).contains(panel))
            #expect(panel.width >= column.width / 2 - 24, "key \(frame.index): narrows only by the key's reach")
        }
    }

    /// A target that isn't a key (a combo output, a macro step) gets the keycode; the selected key never changes (ADR 0037).
    @Test func aTargetThatIsNotAKeyNeverChangesTheSelectedKey() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19, slot: .hold)
        let before = session.layout
        var assigned: [KeyAction] = []
        let target = AssignTarget(title: "Combo 3 › Output", current: KeyAction(code: "KC_ESCAPE")) { assigned.append($0) }
        model.openKeycodePicker(target)
        #expect(model.isPicking && model.pickerTarget == "Combo 3 › Output" && model.pickerCurrent == "Now KC_ESCAPE")
        #expect(model.paletteItems.first?.keycode == KeyAction(code: "KC_ESCAPE"), "Suggested is the target's, not the key's Hold")
        model.cycleSlot()
        model.palette?.query = "esc"
        #expect(model.pickerPreview == nil && model.paletteItems.first?.isCurrent == true)
        model.runHighlighted(advance: true)
        #expect(assigned == [KeyAction(code: "KC_ESCAPE")] && model.palette == nil, "⌘⏎ has no next key")
        #expect(session.selection == EditorSelection(layer: 0, keyIndex: 19, slot: .hold) && session.layout == before)

        model.destination = .macros
        model.openKeycodePicker(target)
        #expect(model.isPicking, "a target works on any page")
        model.dropScopeToken()
        #expect(model.palette?.target == nil && !model.isPicking, "dropping the token drops its target")
    }

    /// A key target previews what it writes: the keycode as picked, without the selected slot's chord, and only on the
    /// shown layer's board (ADR 0037).
    @Test func aKeyTargetPreviewsWhatItWrites() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        session.setModifiers([.leftShift])
        var assigned: [KeyAction] = []
        model.openKeycodePicker(AssignTarget(title: "Key 5", key: KeyRef(layer: 0, index: 5, slot: .tap)) { assigned.append($0) })
        model.palette?.query = "KC_B"
        #expect(model.pickerPreview?.index == 5 && model.pickerPreview?.legend.legend.primary?.qmk == "KC_B")
        model.runHighlighted()
        #expect(assigned == [KeyAction(code: "KC_B")])
        model.openKeycodePicker(AssignTarget(title: "Key 5 on Sym", key: KeyRef(layer: 2, index: 5, slot: .tap)) { _ in })
        #expect(model.pickerPreview == nil, "the board shows layer 0")
    }

    /// ⌘K's layer rows and Find Key's hits show the board from a page, even on the layer already shown.
    @Test func layerAndKeyRowsShowTheBoardFromAPage() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        model.destination = .firmwareSettings
        model.openPalette(query: session.layout.layers[0].title)
        model.run(try #require(model.paletteItems.first { $0.id.hasPrefix("layer-") }))
        #expect(model.destination == .layer(0))
        model.destination = .macros
        model.openPalette(.keys)
        model.run(try #require(model.paletteItems.first { $0.id.hasPrefix("key-0-") }))
        #expect(model.destination == .layer(0) && model.hasSelectedKey)
    }

    /// "Change Tap…" rows suggest only for a key the board shows: on a page the assign scope would have no target.
    @Test func slotSuggestionsOnlyWhereTheKeyIsShown() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        model.openPalette()
        #expect(model.paletteItems.contains { $0.id == "slot-hold" })
        for page in [Destination.combos, .history, .macros, .firmwareSettings] {
            model.destination = page
            model.openPalette()
            #expect(!model.paletteItems.contains { $0.id.hasPrefix("slot-") }, "\(page)")
            model.palette?.query = "change hold"
            #expect(!model.paletteItems.contains { $0.id.hasPrefix("slot-") }, "\(page), searched")
        }
    }

    @Test func paletteSearchRanksExactPrefixWordSubstring() {
        #expect(PaletteSearch.score("main", ["Main"]) > PaletteSearch.score("main", ["Mainly"]))
        #expect(PaletteSearch.score("lay", ["Layer 1"]) > PaletteSearch.score("lay", ["New Layer"]))
        #expect(PaletteSearch.score("layer", ["New Layer"]) > PaletteSearch.score("ayer", ["New Layer"]))
        #expect(PaletteSearch.score("new duplicate", ["New Layer"]) == 0, "every word must match")
    }
}
