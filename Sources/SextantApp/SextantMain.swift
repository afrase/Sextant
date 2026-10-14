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
    private let hotKeys = KeyboardShortcutsHotKeys()

    init() {
        let services = Self.makeServices(toolchain: toolchain, hotKeys: hotKeys)
        _services = State(initialValue: services)
        appDelegate.library = services.library
        appDelegate.live = services.live
        appDelegate.lightingPreview = services.lightingPreview
        services.live.start()
        services.onKeyboard.start()
        services.layerShortcuts.start()
        services.lightingPreview.start()
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
            firmwareSource: (ToolchainPins.firmwareCommit, ToolchainPins.modulesCommit),
            layerShortcutRecorder: hotKeys.recorder(for: services.layerShortcuts))
    }

    /// Builds every adapter and use case. The real flasher and raw-HID link are always wired: Build & Flash and the live
    /// view each write to the keyboard only after the user starts them (ADRs 0056, 0057). Read-only USB presence is
    /// always on.
    @MainActor
    static func makeServices(toolchain: NativeToolchain, hotKeys: some HotKeys) -> SextantServices {
        let store = PackageLibrary(root: PackageLibrary.defaultRoot())
        let library = Library(store: store)
        let watcher = IOKitDeviceWatcher()
        // The raw-HID log sees only what the link writes and reads, only while it is on, and nothing during secure input
        // (ADR 0045).
        let trace = RawHIDTrace(secureInputProbe: SecureInputProbe.isEnabled)
        let link = RawHIDLink(trace: trace.record)
        let flasher: any Flasher = DFUFlasher()
        let live = LiveSession(
            watcher: watcher, link: link, followsOnConnect: KeyboardSettings.followsOnConnect, secureInputProbe: SecureInputProbe.isEnabled)
        let oryx = OryxClient()
        let generator = QMKGenerator()
        let md5: @Sendable (Data) -> String = { Insecure.MD5.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        let onKeyboard = OnKeyboard(library: library, store: store, live: live)
        // Off by default; a press that moves nothing beeps, since Sextant may be in the background (ADR 0048).
        let layerShortcuts = LayerShortcuts(
            hotKeys: hotKeys, onKeyboard: onKeyboard, isOn: KeyboardSettings.layerShortcutsOn(),
            persist: KeyboardSettings.saveLayerShortcutsOn
        ) { _ in NSSound.beep() }
        return SextantServices(
            library: library, live: live, trace: trace, onKeyboard: onKeyboard, layerShortcuts: layerShortcuts,
            lightingPreview: LightingPreview(live: live),
            makeImport: { ImportFromOryx(oryx: oryx, library: library) },
            makeBuildFlash: { session in
                // ADR 0033: the native toolchain, every build sandboxed.
                BuildFlashSession(
                    session: session, library: store, generator: generator, toolchain: toolchain, watcher: watcher,
                    flasher: flasher, md5: md5, live: live)
            })
    }
}

/// Quitting waits for a firmware write and its verify (spec §7.4: neither can be stopped) and for open documents' pending
/// autosaves (each lands up to a second after the last edit), and asks first when an edit couldn't be saved. Quitting and
/// sleep end the keyboard lighting preview (ADR 0051).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var library: Library?
    var live: LiveSession?
    var lightingPreview: LightingPreview?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DeleteMenuItem.showDeleteKey()
        // A Mac that sleeps may wake without Sextant's session: give the keyboard its own lighting back first. Observed for
        // the app's lifetime, so the token is never needed.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [lightingPreview] _ in
            MainActor.assumeIsolated { lightingPreview?.releaseAll() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let library else { return .terminateNow }
        // End text editing so a typed label commits (its field commits when focus leaves) before the last save.
        for window in sender.windows { window.makeFirstResponder(nil) }
        Task {
            // SwiftUI reports the focus change on a later run-loop turn; let one pass first.
            await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            let quits = await Quitting(library: library, live: live).run(quitAnyway: Self.quitAnyway)
            // Bounded: the write has no timeout. If it runs out, the colors stay until the keyboard is unplugged.
            if quits { await lightingPreview?.releaseAndWait() }
            sender.reply(toApplicationShouldTerminate: quits)
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
