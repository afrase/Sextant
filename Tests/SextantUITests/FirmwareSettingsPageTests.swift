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
}
