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

    init() {
        let services = Self.makeServices()
        _services = State(initialValue: services)
        appDelegate.library = services.library
        services.live.start()
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
        SextantScenes(services: services, buildToolsStatus: { await Self.toolchain($0).status() })
    }

    /// The toolchain for Settings › Build's choice. Constructing one only names its folder; status never downloads.
    static func toolchain(_ backend: BuildBackend) -> any Toolchain {
        backend == .native ? NativeToolchain() : ContainerToolchain()
    }

    /// Builds every adapter and use case. Raw-HID writes and flashing stay off until the user sets the
    /// `SextantHardwareEnabled` default by hand (ADR 0012); read-only USB presence is always on.
    @MainActor
    static func makeServices() -> SextantServices {
        let hardwareEnabled = UserDefaults.standard.bool(forKey: "SextantHardwareEnabled")
        let store = PackageLibrary(root: PackageLibrary.defaultRoot())
        let library = Library(store: store)
        let watcher = IOKitDeviceWatcher()
        let link: any KeyboardLink = hardwareEnabled ? RawHIDLink() : RefusingKeyboardLink()
        let flasher: any Flasher = hardwareEnabled ? DFUFlasher() : RefusingFlasher()
        let live = LiveSession(watcher: watcher, link: link, secureInputProbe: SecureInputProbe.isEnabled)
        let oryx = OryxClient()
        let generator = QMKGenerator()
        let md5: @Sendable (Data) -> String = { Insecure.MD5.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        return SextantServices(
            library: library, live: live,
            makeImport: { ImportFromOryx(oryx: oryx, library: library) },
            makeBuildFlash: { session in
                // ADR 0018: container builds by default; Settings › Build can pick the native fallback.
                BuildFlashSession(
                    session: session, library: store, generator: generator, toolchain: toolchain(.current), watcher: watcher,
                    flasher: flasher, md5: md5)
            })
    }
}

/// Quitting waits for open documents' pending autosaves (each lands up to a second after the last edit).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var library: Library?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let library else { return .terminateNow }
        Task {
            await library.flushOpenSessions()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
