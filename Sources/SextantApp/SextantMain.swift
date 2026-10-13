// Composition root (architecture §4.1): the only place that wires concrete adapters to ports.

import CryptoKit
import Foundation
import SextantApplication
import SextantBuild
import SextantDevice
import SextantDomain
import SextantOryx
import SextantStorage
import SextantUI
import SwiftUI
import os

@main
struct SextantMain: App {
    @State private var services: SextantServices
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    /// One toolchain, so every window shares its setup (only one runs at a time).
    private let toolchain = NativeToolchain(installer: ToolchainInstaller())

    init() {
        let services = Self.makeServices(toolchain: toolchain)
        _services = State(initialValue: services)
        appDelegate.library = services.library
        appDelegate.live = services.live
        services.live.start()
        services.onKeyboard.start()
        // `--import <oryx.json>`: add an Oryx layout file to the library at launch.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--import"), args.indices.contains(i + 1) {
            let url = URL(fileURLWithPath: args[i + 1])
            Task { @MainActor in
                do {
                    try await services.library.importOryxJSON(Data(contentsOf: url))
                } catch {
                    Logger(subsystem: "com.sextant.app", category: "app").error(
                        "Import failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    var body: some Scene {
        SextantScenes(
            services: services, buildToolsStatus: { [toolchain] in await toolchain.status() },
            firmwareSource: (ToolchainPins.firmwareCommit, ToolchainPins.modulesCommit))
    }

    /// Builds every adapter and use case. Flashing is always wired: the user's Build & Flash is the consent, and the
    /// flasher's guards hold either way (ADR 0056). The raw-HID link stays off until `SextantLiveAccessEnabled` (or the older
    /// `SextantHardwareEnabled`) is set, since its pairing request writes to the keyboard without a click (ADR 0034).
    /// Read-only USB presence is always on.
    @MainActor
    static func makeServices(toolchain: NativeToolchain) -> SextantServices {
        let defaults = UserDefaults.standard, both = defaults.bool(forKey: "SextantHardwareEnabled")
        let liveAccessEnabled = both || defaults.bool(forKey: "SextantLiveAccessEnabled")
        let store = PackageLibrary(root: PackageLibrary.defaultRoot())
        let library = Library(store: store)
        let watcher = IOKitDeviceWatcher()
        // The raw-HID log sees only what the link writes and reads, only while it is on, and nothing during secure input
        // (ADR 0045).
        let trace = RawHIDTrace(secureInputProbe: SecureInputProbe.isEnabled)
        let link: any KeyboardLink = liveAccessEnabled ? RawHIDLink(trace: trace.record) : RefusingKeyboardLink()
        let flasher: any Flasher = DFUFlasher()
        let live = LiveSession(
            watcher: watcher, link: link, followsOnConnect: KeyboardSettings.followsOnConnect, secureInputProbe: SecureInputProbe.isEnabled)
        let oryx = OryxClient()
        let generator = QMKGenerator()
        let md5: @Sendable (Data) -> String = { Insecure.MD5.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        return SextantServices(
            library: library, live: live, trace: trace, onKeyboard: OnKeyboard(library: library, store: store, live: live),
            makeImport: { ImportFromOryx(oryx: oryx, library: library) },
            makeBuildFlash: { session in
                // ADR 0033: the native toolchain, every build sandboxed.
                BuildFlashSession(
                    session: session, library: store, generator: generator, toolchain: toolchain, watcher: watcher,
                    flasher: flasher, md5: md5, live: live)
            })
    }
}

/// Quitting waits for a firmware write (spec §7.4: it can't be stopped) and for open documents' pending autosaves (each
/// lands up to a second after the last edit), and asks first when an edit couldn't be saved.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var library: Library?
    var live: LiveSession?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let library else { return .terminateNow }
        // End text editing so a typed label commits (its field commits when focus leaves) before the last save.
        for window in sender.windows { window.makeFirstResponder(nil) }
        Task {
            // SwiftUI reports the focus change on a later run-loop turn; let one pass first.
            await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            // A cut-off write leaves the keyboard in flash mode. The flasher's capped polling and timeouts bound the wait.
            while live?.isWritingFirmware == true { try? await Task.sleep(for: .milliseconds(200)) }
            let saved = await library.flushOpenSessions()
            sender.reply(toApplicationShouldTerminate: saved || Self.quitAnyway())
        }
        return .terminateLater
    }

    @MainActor private static func quitAnyway() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Sextant couldn’t save your latest edits")
        alert.informativeText = String(localized: "Quitting now may lose them. The layout’s window says what went wrong.")
        alert.addButton(withTitle: String(localized: "Don’t Quit"))
        alert.addButton(withTitle: String(localized: "Quit Anyway"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}
