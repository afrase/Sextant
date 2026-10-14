import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantUI

/// History's actions from the menus and the palette, and the firmware size line (spec §8.7, §11; ADR 0043).
@MainActor
struct HistoryActionsTests {
    /// The user's layout with an edit since its import, on History showing the import.
    func onHistory() async throws -> (LayoutWindowModel, RevisionSummary) {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        let revision = try #require(session.revisions.first)
        session.setCode("KC_F13", layer: 0, index: 1)
        await model.showRevision(revision.id)
        return (model, revision)
    }

    @Test func historyCommandsAreOnlyOnHistory() async throws {
        let (model, revision) = try await onHistory()
        #expect(model.shownRevision == revision)
        model.destination = .layer(0)
        #expect(model.shownRevision == nil, "the board shows no revision")
        model.openPalette(query: "restore this revision")
        #expect(!model.paletteItems.contains { $0.title == "Restore This Revision" })
    }

    @Test func thePaletteRestoresAndCompares() async throws {
        let (model, revision) = try await onHistory()
        let session = try #require(model.session)
        let imported = try #require(model.history?.layouts[revision.id])
        model.openPalette(query: "compare current")
        model.run(try #require(model.paletteItems.first { $0.title == "Compare with: Current" }))
        #expect(model.history?.comparison == .current)
        model.openPalette(query: "compare")
        #expect(!model.paletteItems.contains { $0.title == "Compare with: Current" }, "already compared with Current")
        #expect(!model.paletteItems.contains { $0.title == "Compare with: On keyboard" }, "no keyboard runs this layout")

        model.openPalette(query: "restore this revision")
        model.run(try #require(model.paletteItems.first { $0.title == "Restore This Revision" }))
        for _ in 0..<200 where session.layout != imported { try await Task.sleep(for: .milliseconds(10)) }
        #expect(session.layout == imported, "the import is the layout again")
    }

    /// Without Build & Flash (tests, snapshots) there is nothing to flash or build a source from.
    @Test func flashAndExportNeedBuildAndFlash() async throws {
        let (model, revision) = try await onHistory()
        #expect(!model.canFlash(revision) && !model.canExportSource(of: revision))
        model.openPalette(query: "flash this revision")
        #expect(!model.paletteItems.contains { $0.title == "Flash This Revision…" })
        await model.loadFirmwareSize()
        #expect(model.history?.firmware == nil, "no Build & Flash to read it through")
    }

    @Test func theSizeLineSaysHowTheFirmwareChanged() {
        let earlier = RevisionSummary(id: "0002-a", number: 2, createdAt: Date(), source: .flash, message: nil, contentHash: "")
        // The size is the system's file size, in the user's locale ("65.8 KB").
        let total = Int64(65_786).formatted(.byteCount(style: .file))
        #expect(FirmwareSize(bytes: 65_786).text == "Firmware \(total)")
        #expect(
            FirmwareSize(bytes: 65_786, change: .init(revision: earlier, bytes: 292)).text == "Firmware \(total) · +292 B since revision 2")
        #expect(
            FirmwareSize(bytes: 65_786, change: .init(revision: earlier, bytes: -1_204)).text
                == "Firmware \(total) · \u{2212}\(1_204.formatted()) B since revision 2")
        #expect(
            FirmwareSize(bytes: 65_786, change: .init(revision: earlier, bytes: 0)).text == "Firmware \(total) · same size as revision 2")
        #expect(
            FirmwareSize(bytes: 65_786, change: .init(revision: earlier, bytes: 292)).spokenText
                == "Firmware \(total), 292 bytes larger than revision 2")
    }
}
