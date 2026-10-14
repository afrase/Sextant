import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

/// History and Save Revision (spec §8.7) over the edited-revision fixture: revision 2 on Brd+Sys against its parent.
extension Scenes {
    static func history(_ f: Fixtures) async -> [SnapshotScene] {
        guard let model = await historyModel(f) else { return [] }
        var scenes: [SnapshotScene] = []
        let make = { LayoutWindow(model: model, layoutID: .constant(model.session?.id)) }
        scenes += SnapshotScene.pair("window-history", size: full) { make() }
        scenes.append(SnapshotScene("window-history-min-light", size: CGSize(width: 1120, height: 640)) { make() })
        // Accessibility variants are board scenes, as for the kinds board (Scenes.boards).
        let size = CGSize(width: 1100, height: 560)
        scenes += SnapshotScene.pair("board-history-contrast", size: size, chrome: .content) {
            ChangesBoard(model: model).background(Tokens.benchBase.color).environment(\._colorSchemeContrast, .increased)
        }
        scenes.append(
            SnapshotScene("board-history-dwc-light", size: size, chrome: .content) {
                ChangesBoard(model: model).background(Tokens.benchBase.color).environment(\._accessibilityDifferentiateWithoutColor, true)
            })

        // A long History scrolls its timeline, so the selected revision's details stay in view.
        if let many = await historyModel(f), let session = many.session {
            for n in 1...12 {
                _ = try? await session.recordRevision(RevisionDraft(source: .flash, message: "Flash \(n)", layout: session.layout))
            }
            if let revision = session.revisions.dropFirst().first { await many.showRevision(revision.id) }
            scenes.append(
                SnapshotScene("window-history-many-light", size: full) { LayoutWindow(model: many, layoutID: .constant(many.session?.id)) })
        }
        // No revisions yet (§12.4): only a package made outside Sextant starts without one.
        if let empty = await emptyHistoryModel() {
            scenes.append(
                SnapshotScene("window-history-empty-light", size: full) {
                    LayoutWindow(model: empty, layoutID: .constant(empty.session?.id))
                })
        }

        // Save Revision over the window, with the message it suggests for the working copy's edit.
        if let saving = await historyModel(f) {
            saving.destination = .layer(0)
            await saving.beginSaveRevision()
            scenes += SnapshotScene.pair("save-revision", size: full, overlays: [.sheet(width: 440) { SaveRevisionSheet(model: saving) }]) {
                LayoutWindow(model: saving, layoutID: .constant(saving.session?.id))
            }
        }
        scenes += await flashedHistory(f)
        return scenes
    }

    /// Two flashes with their images (ADR 0043): the newest shows its firmware's size and the change since the other, and
    /// Flash This Revision… waits for flash mode with the revision named in the sheet.
    private static func flashedHistory(_ f: Fixtures) async -> [SnapshotScene] {
        guard let model = await historyModel(f), let session = model.session,
            let root = await model.library.location(of: session.id)?.deletingLastPathComponent()
        else { return [] }
        let store = PackageLibrary(root: root)
        // As Build & Flash words them: "Flashed" and the date.
        let message = "Flashed \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        for bytes in [65_494, 65_786] {
            guard let revision = try? await session.recordRevision(RevisionDraft(source: .flash, message: message, layout: session.layout))
            else { return [] }
            try? await store.storeFirmware(Data(count: bytes + 16), md5: "", revisionID: revision.id, to: session.id)
            session.setCode("KC_F14", layer: 2, index: 0)
        }
        guard let newest = session.revisions.last else { return [] }
        await model.showRevision(newest.id)
        var scenes = SnapshotScene.pair("window-history-flashed", size: full) {
            LayoutWindow(model: model, layoutID: .constant(model.session?.id))
        }
        scenes.append(
            SnapshotScene("window-history-flashed-min-light", size: CGSize(width: 1120, height: 640)) {
                LayoutWindow(model: model, layoutID: .constant(model.session?.id))
            })

        // Flash This Revision… on revision 2, built and waiting for the keyboard in flash mode.
        guard let flashing = await historyModel(f), let document = flashing.session, let revision = document.revisions.dropFirst().first,
            let layout = try? await document.revisionLayout(revision.id)
        else { return scenes }
        let build = BuildFlashSession(
            session: document, library: store, generator: RevisionSceneGenerator(), toolchain: RevisionSceneToolchain(),
            watcher: NoBootloader(), flasher: NeverFlashes(), md5: { _ in "" })
        flashing.buildFlash = build
        build.buildAndFlash(connectedKeyboard: nil, revision: RevisionLayout(revision: revision, layout: layout))
        for _ in 0..<250 where build.phase != .waitingForFlashMode(stillWaiting: false) { try? await Task.sleep(for: .milliseconds(20)) }
        scenes.append(
            SnapshotScene("buildflash-revision-light", size: full, overlays: [.sheet(width: 640) { BuildFlashSheet(model: flashing) }]) {
                LayoutWindow(model: flashing, layoutID: .constant(flashing.session?.id))
            })
        scenes += await blockedRevision(f, store: store)
        return scenes
    }

    /// Flash This Revision… on a saved revision with a key on a layer that doesn't exist, fixed since in the working copy.
    private static func blockedRevision(_ f: Fixtures, store: PackageLibrary) async -> [SnapshotScene] {
        guard let model = await historyModel(f), let document = model.session else { return [] }
        var broken = document.layout
        broken.updateKey(layer: 0, index: 3) { $0 = Key(tap: .momentary(9)) }
        guard let revision = try? await document.recordRevision(RevisionDraft(source: .save, message: "Try layer 9", layout: broken))
        else { return [] }
        await model.showRevision(revision.id)
        let build = BuildFlashSession(
            session: document, library: store, generator: RevisionSceneGenerator(), toolchain: RevisionSceneToolchain(),
            watcher: NoBootloader(), flasher: NeverFlashes(), md5: { _ in "" })
        model.buildFlash = build
        build.buildAndFlash(connectedKeyboard: nil, revision: RevisionLayout(revision: revision, layout: broken))
        for _ in 0..<250 where build.phase == .idle { try? await Task.sleep(for: .milliseconds(20)) }
        return SnapshotScene.pair(
            "buildflash-revision-blocked", size: full, overlays: [.sheet(width: 640) { BuildFlashSheet(model: model) }]
        ) {
            LayoutWindow(model: model, layoutID: .constant(model.session?.id))
        }
    }

    /// The fixture on its History page, showing revision 2 on Brd+Sys. Snapshots run no tasks, so the page's load runs here.
    private static func historyModel(_ f: Fixtures) async -> LayoutWindowModel? {
        guard let model = await f.editedRevisionModel(), let session = model.session else { return nil }
        model.buildFlash = await idleBuildFlash(model)
        model.activity = ActivityState(device: connected, status: .notOnKeyboard(edits: 7))
        session.select(layer: 2)
        if let revision = session.revisions.dropFirst().first { await model.showRevision(revision.id) }
        return model
    }

    private static func emptyHistoryModel() async -> LayoutWindowModel? {
        let store = PackageLibrary(root: FileManager.default.temporaryDirectory.appending(path: "sextant-snapshots-\(UUID().uuidString)"))
        guard let data = try? Data(contentsOf: Fixtures.layoutFile), let layout = try? KeyboardLayout(oryxJSON: data),
            let entry = try? await store.create(layout, origin: .local, firstRevision: nil)
        else { return nil }
        let library = Library(store: store)
        await library.refresh()
        let model = LayoutWindowModel(library: library)
        await model.open(entry.id)
        model.destination = .history
        return model
    }
}

/// A Voyager plugged in with live access off: its serial is known from enumeration, and nothing is read or sent.
struct PluggedInKeyboard: DeviceWatcher, KeyboardLink {
    var serial: String

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        AsyncStream { continuation in
            continuation.yield(.attached(.keyboard(KeyboardDevice(id: 1, productID: 0x1977, serial: serial))))
            continuation.finish()
        }
    }

    func session(with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>) -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in
            continuation.yield(.ended(.hardwareAccessOff))
            continuation.finish()
        }
    }
}

// MARK: - Flash This Revision fakes: a build that finishes at once, and flash mode that never comes, so nothing is written.

private struct RevisionSceneGenerator: FirmwareGenerator {
    func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        GeneratedSource(files: [:], sourceMap: [:])
    }
}

private struct RevisionSceneToolchain: Toolchain {
    func status() async -> ToolchainStatus { .ready("scene") }
    func setUp() -> AsyncStream<SetupEvent> { AsyncStream { $0.finish() } }
    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        AsyncStream {
            $0.yield(.finished(BuildArtifact(image: Data(count: 65_802), usedBytes: 65_786, log: [])))
            $0.finish()
        }
    }
}

private struct NoBootloader: DeviceWatcher {
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> { AsyncStream { _ in } }
}

private struct NeverFlashes: Flasher {
    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) { throw .hardwareAccessOff }
}
