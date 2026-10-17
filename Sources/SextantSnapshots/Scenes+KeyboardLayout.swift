import AppKit
import Foundation
import SextantApplication
import SextantDomain
import SextantStorage
import SextantUI
import SwiftUI

// Reading the layout back from the keyboard (ADR 0061): the device card's prompt in each state, then a real pull reading
// the layout a scripted Sextant build stores, in the card, the Device popover and the Layout on the Keyboard window.
// Nothing here touches hardware.

extension Scenes {
    static func keyboardLayout(_ f: Fixtures) async -> [SnapshotScene] {
        guard let root = await f.windowModel().library.location(of: f.entry.id)?.deletingLastPathComponent(),
            let base = await f.windowModel().session?.layout
        else { return [] }
        // The user's layout as another Mac has it, one key changed since, built there with its layout stored.
        var other = base
        other.layers[0].keys[0] = Key("KC_F13")
        let otherMac = UUID()
        let serial = FirmwareIdentity(layout: other, libraryID: otherMac, importedLayout: nil).serial
        let record = (try? LayoutRecord(layout: other, libraryIDs: [otherMac]).encoded()) ?? []

        // The card's prompt in each state, as values.
        let prompts: [KeyboardLayoutPrompt] = [
            .notInLibrary(serial: serial), .reading(0.4), .noRecord, .found(title: other.title),
            .failed(PullFailure.keyboard(.timedOut).localizedDescription),
        ]
        var cards: [LayoutWindowModel] = []
        for prompt in prompts {
            let model = await promptModel(f, root: root, serial: serial)
            model.keyboardLayoutPrompt = prompt
            cards.append(model)
        }

        // A real pull over Live View: it finds the layout and suggests the user's, from the same Oryx layout.
        let store = PackageLibrary(root: root)
        let library = Library(store: store)
        let link = StoredLayoutLink(record: record)
        let live = LiveSession(watcher: PluggedInKeyboard(serial: serial), link: link, secureInputProbe: { false })
        live.start()
        live.startLive()
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        onKeyboard.start()
        let pull = KeyboardLayoutPull(live: live, onKeyboard: onKeyboard, library: library, store: store)
        await library.refresh()
        _ = await waitUntil { live.canSend }
        await pull.read()
        let found = LayoutWindowModel(library: library, live: live, onKeyboard: onKeyboard, keyboardLayout: pull)
        await found.open(f.entry.id)
        cards.append(found)

        var scenes = SnapshotScene.pair("device-card-keyboard-layout", size: CGSize(width: 228, height: 1040), chrome: .content) {
            VStack(spacing: 0) { ForEach(cards.indices, id: \.self) { DeviceCard(model: cards[$0]) } }.frame(width: 228)
        }
        scenes += SnapshotScene.pair("device-popover-keyboard-layout", size: CGSize(width: 360, height: 640), chrome: .content) {
            DevicePopover(model: found)
        }
        let size = NSHostingView(rootView: KeyboardLayoutWindow(pull: pull, library: library)).fittingSize
        scenes += SnapshotScene.pair("keyboard-layout-window", size: size, chrome: .window(title: "Layout on the Keyboard")) {
            KeyboardLayoutWindow(pull: pull, library: library)
        }
        return scenes
    }

    /// A window with the user's layout open while a keyboard that runs `serial` is plugged in, Live View off.
    private static func promptModel(_ f: Fixtures, root: URL, serial: String) async -> LayoutWindowModel {
        let keyboard = PluggedInKeyboard(serial: serial)
        let live = LiveSession(watcher: keyboard, link: keyboard, secureInputProbe: { false })
        live.start()
        let model = LayoutWindowModel(library: Library(store: PackageLibrary(root: root)), live: live)
        await model.open(f.entry.id)
        return model
    }

    /// Polls `condition` for up to 5 s.
    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<250 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }
}

/// A Sextant build that stores `record` (ADR 0061): each session pairs, then answers every read of the record as the
/// firmware does, 24 bytes at a time.
private final class StoredLayoutLink: KeyboardLink {
    private let record: [UInt8]

    init(record: [UInt8]) { self.record = record }

    func session(
        with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>
    ) -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self)
        continuation.yield(.protocolVersion(5))
        continuation.yield(.layer(0))
        let record = record
        let answers = Task {
            for await command in commands {
                guard case let .readLayoutRecord(offset) = command else { continue }
                let bytes = offset < record.count ? Array(record[offset..<min(offset + 24, record.count)]) : []
                continuation.yield(.layoutRecord(LayoutRecordChunk(offset: offset, size: record.count, bytes: bytes)))
            }
        }
        continuation.onTermination = { _ in answers.cancel() }
        return stream
    }
}
