import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// The Firmware Settings page with every setting (spec §8.8, v1 slice 2.3): search, Modified only and the picker's
/// International gating.
@MainActor
struct FirmwareSettingsPageTests {
    func layout() throws -> KeyboardLayout { try KeyboardLayout(oryxJSON: try #require(userLayoutData)) }

    func ids(_ sections: [SettingsSection]) -> [String] { sections.flatMap(\.settings).map(\.id) }

    /// Search keeps the matching settings of the sections the page shows, synonyms included, and never a hidden one.
    @Test func searchFiltersTheShownSettings() throws {
        let layout = try layout()
        let all = FirmwareSettings.sections(for: layout)
        #expect(FirmwareSettings.sections(for: layout, query: "", modifiedOnly: false) == all)
        let chatter = FirmwareSettings.sections(for: layout, query: "chatter", modifiedOnly: false)
        #expect(chatter.map(\.id) == ["debounce"] && ids(chatter) == ["debounce"], "no Navigator rows: the query doesn't name them")
        #expect(ids(FirmwareSettings.sections(for: layout, query: "steno", modifiedOnly: false)).isEmpty, "hidden")
        #expect(ids(FirmwareSettings.sections(for: layout, query: "german", modifiedOnly: false)).isEmpty, "no German keycodes")
        let hold = ids(FirmwareSettings.sections(for: layout, query: "hold", modifiedOnly: false))
        #expect(hold.contains("permissiveHold") && hold.contains("chordalHold") && !hold.contains("dancesTapAction"))
        // The Navigator section stays for its module choice when the query names it.
        let trackball = FirmwareSettings.sections(for: layout, query: "trackball", modifiedOnly: false)
        #expect(trackball.last?.id == FirmwareSettings.navigator)
        #expect(FirmwareSettings.showsNavigatorChoice(query: "side", modifiedOnly: false))
        #expect(!FirmwareSettings.showsNavigatorChoice(query: "", modifiedOnly: true))
    }

    /// Modified only shows changed settings Sextant offers; a hidden imported value doesn't count.
    @Test func modifiedOnlyShowsChangedSettings() throws {
        var layout = try layout()
        #expect(FirmwareSettings.sections(for: layout, query: "", modifiedOnly: true).isEmpty)
        layout.store(.number(8), for: try #require(SettingsCatalog.voyager.setting(id: "debounce")))
        layout.store(.bool(true), for: try #require(SettingsCatalog.voyager.setting(id: "chordalHold")))
        layout.settings["liveTraining"] = .bool(false)
        let modified = FirmwareSettings.sections(for: layout, query: "", modifiedOnly: true)
        #expect(ids(modified) == ["debounce", "chordalHold", "chordalHoldExcludeThumbs"])
        #expect(ids(FirmwareSettings.sections(for: layout, query: "thumbs", modifiedOnly: true)) == ["chordalHoldExcludeThumbs"])
    }

    /// Modified only and the changed count agree: a value whose row the page hides (its dependency is off) is kept,
    /// not counted.
    @Test func modifiedOnlyMatchesTheChangedCount() throws {
        var layout = try layout()
        for (id, value) in [("oneShotAutoMouse", SettingValue.bool(true)), ("oneShotAutoMouseTimeout", .number(5))] {
            layout.store(value, for: try #require(SettingsCatalog.voyager.setting(id: id)))
        }
        #expect(ids(FirmwareSettings.sections(for: layout, query: "", modifiedOnly: true)) == layout.changedSettings().map(\.id))
        layout.store(nil, for: try #require(SettingsCatalog.voyager.setting(id: "oneShotAutoMouse")))
        #expect(layout.changedSettings().isEmpty && FirmwareSettings.sections(for: layout, query: "", modifiedOnly: true).isEmpty)
    }

    /// The header counts the Navigator's module choice when the query names it, so "trackball" doesn't read 0 matches.
    @Test func countIncludesTheNavigatorChoice() throws {
        let layout = try layout()
        func count(_ query: String, modifiedOnly: Bool = false) -> Int {
            FirmwareSettings.count(
                FirmwareSettings.sections(for: layout, query: query, modifiedOnly: modifiedOnly), query: query, modifiedOnly: modifiedOnly)
        }
        #expect(count("trackball") == 1 && count("left") == 1)
        #expect(count("chatter") == 1 && count("zzzz") == 0)
        #expect(count("", modifiedOnly: true) == 0)
    }

    /// Choosing a setting in the palette clears a filter that keeps its section but hides its row.
    @Test func paletteJumpClearsAFilterThatHidesTheSetting() async throws {
        let model = try await openUserLayout()
        model.firmwareSettings.query = "hold"
        let session = try #require(model.session)
        #expect(FirmwareSettings.shows("tappingTerm", in: session.layout, query: "hold", modifiedOnly: false))
        #expect(!FirmwareSettings.shows("tapCodeDelay", in: session.layout, query: "hold", modifiedOnly: false))
        model.openPalette(.general, query: "media key delay")
        model.paletteItems.first { $0.id == "setting-tapCodeDelay" }?.perform()
        #expect(model.firmwareSettings.query.isEmpty && model.settingsScrollTarget == "tapping")
        // A filter that already shows the row stays.
        model.firmwareSettings.query = "hold"
        model.openPalette(.general, query: "tapping term")
        model.paletteItems.first { $0.id == "setting-tappingTerm" }?.perform()
        #expect(model.firmwareSettings.query == "hold")
    }

    /// Each coupling says so on its row; the Auto Shift options wait for Auto Shift.
    @Test func couplingsAreSaidInline() {
        for id in ["tappingTerm", "chordalHold", "autoshift"] { #expect(FirmwareSettings.couplingNote(id) != nil, "\(id)") }
        #expect(FirmwareSettings.couplingNote("debounce") == nil)
        #expect(FirmwareSettings.follows["autoshiftEnableAlpha"] == "autoshift" && FirmwareSettings.follows["autoshift"] == nil)
    }

    /// The picker's International category offers a locale's codes only while its toggle is on.
    @Test func internationalTogglesGateThePicker() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        model.openKeycodePicker()
        model.palette?.category = .international
        func codes() -> Set<String> { Set(model.paletteItems.compactMap(\.keycode?.code)) }
        #expect(!codes().contains("UK_PND") && !codes().contains("US_EACU") && codes().contains("KC_INTERNATIONAL_1"))
        session.setSetting("uk", to: .bool(true))
        #expect(codes().contains("UK_PND") && !codes().contains("US_EACU"))
        #expect(model.pickerCount(.international) == model.paletteItems.count)
        session.setSetting("usint", to: .bool(true))
        model.palette?.category = nil
        model.palette?.query = "e acute"
        #expect(model.paletteItems.first?.keycode?.code == "US_EACU", "search too")
    }

    /// A search that matches a locale's codes while its toggle is off says so and goes to the toggle; a recent code
    /// from that locale leaves Suggested too.
    @Test func hiddenLocaleCodesSayWhereTheyAre() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(key: 19)
        session.setSetting("uk", to: .bool(true))
        model.openKeycodePicker()
        model.palette?.query = "pound"
        #expect(model.paletteItems.contains { $0.keycode?.code == "UK_PND" } && !model.paletteItems.contains { $0.id == "locale-uk" })
        model.assign(KeyAction(code: "UK_PND"))
        model.openKeycodePicker()
        #expect(model.paletteItems.contains { $0.keycode?.code == "UK_PND" }, "recent")
        session.setSetting("uk", to: nil)
        #expect(!model.paletteItems.contains { $0.keycode?.code == "UK_PND" }, "no longer offered")
        model.palette?.query = "pound"
        let hint = try #require(model.paletteItems.first { $0.id == "locale-uk" })
        #expect(!model.paletteItems.contains { $0.keycode?.code == "UK_PND" })
        model.firmwareSettings.modifiedOnly = true
        hint.perform()
        #expect(model.palette == nil && model.destination == .firmwareSettings && model.settingsScrollTarget == "international")
        #expect(!model.firmwareSettings.modifiedOnly)
    }

    /// The hint counts only codes the picker's target could take: a macro step types no locale's codes, so turning the
    /// toggle on would show it nothing.
    @Test func noHintForCodesTheTargetRefuses() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.newMacro()
        let draft = try #require(session.selection.macro)
        model.destination = .macros
        model.openStepPicker(step: nil, in: draft)
        model.palette?.query = "pound"
        #expect(model.paletteItems.contains { $0.keycode?.code == "KC_HASH" })
        #expect(!model.paletteItems.contains { $0.id == "locale-uk" })
    }

    /// ⌘F on the page focuses its search and closes an open ⌘K, which would float over the field.
    @Test func findSettingClosesThePalette() async throws {
        let model = try await openUserLayout()
        model.destination = .firmwareSettings
        model.openPalette()
        model.findSetting()
        #expect(model.palette == nil && model.firmwareSettings.searchFocusRequests == 1)
    }
}
