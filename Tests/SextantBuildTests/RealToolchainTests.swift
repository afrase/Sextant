import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// The real setup and build (ADR 0033), against the network and the toolchain in `~/Library/Caches`. Off unless
/// `SEXTANT_REAL_TOOLCHAIN=1`: it downloads about 200 MB the first time. Nothing reaches a keyboard.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SEXTANT_REAL_TOOLCHAIN"] == "1"), .serialized)
struct RealToolchainTests {
    let installer = ToolchainInstaller()

    @Test func setsUpAndBuildsTheUsersLayout() async throws {
        if !installer.isInstalled {
            var events: [SetupEvent] = []
            for await event in installer.setUp() {
                if case .downloading = event { continue }
                events.append(event)
            }
            #expect(events.last == .finished, "setup: \(events)")
        }
        try #require(installer.isInstalled)

        let layout = try KeyboardLayout(
            oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.examples.appending(path: "my-layout-KlgM7-full.json")))
        let source = try QMKGenerator().generate(layout, identity: FirmwareIdentity(serial: "KlgM7/40xJ7M"))
        var log: [String] = []
        var result: BuildEvent?
        for await event in NativeToolchain(installer: installer).build(source, board: .voyager) {
            switch event {
            case let .output(line): log.append(line)
            case .finished, .failed: result = event
            default: break
            }
        }
        guard case let .finished(artifact)? = result else {
            Issue.record("build: \(String(describing: result))\n\(log.suffix(60).joined(separator: "\n"))")
            return
        }
        // The flasher's own checks: suffix, CRC, vendor and product, size, stack pointer and reset vector.
        try FirmwareImage(data: artifact.image).validate(forBootloaderPID: 0x0791, board: .voyager)
        // The Navigator trackpad must stay in (CLAUDE.md), and the serial Oryx and Keymapp read must be there.
        #expect(log.contains { $0.contains("navigator_trackpad.c") })
        #expect(artifact.image.range(of: Data("KlgM7/40xJ7M".utf8)) != nil)
        // Oryx built 65,786 bytes from the same 167 files. Arm's build of GCC 12.2.1 and its newlib come out about 5%
        // smaller than Debian's (measured 2026-10-11: 62,350 bytes); their readable strings match.
        let used = try #require(artifact.usedBytes)
        #expect(abs(used - 65_786) < 6_500, "used \(used) bytes")
        print("Built \(artifact.image.count) bytes (payload \(used)):\n\(log.joined(separator: "\n"))")
        if let out = ProcessInfo.processInfo.environment["SEXTANT_REAL_TOOLCHAIN_OUT"] { try artifact.image.write(to: URL(filePath: out)) }
    }
}
