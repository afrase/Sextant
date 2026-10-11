import Foundation
import Observation

/// A key position in a layout.
public struct KeyRef: Hashable, Sendable, Codable {
    public var layer: Int
    public var index: Int
    public init(layer: Int, index: Int) {
        self.layer = layer
        self.index = index
    }
}

/// A built firmware image.
public struct FirmwareImage: Hashable, Sendable {
    public var fileName: String
    /// Bytes.
    public var size: Int
    public var md5: String
    public var builtAt: Date
}

/// Firmware size against the Voyager's application flash window (120 KiB at 0x08002000).
public struct FirmwareSizeMeter: Hashable, Sendable {
    public struct Part: Hashable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        public var bytes: Int
    }
    /// Bytes used.
    public var used: Int
    /// Bytes available (122,880 on the Voyager).
    public var capacity: Int
    /// Approximate breakdown, largest first (illustrative; QMK doesn't report per-feature sizes).
    public var parts: [Part]

    public var fraction: Double { Double(used) / Double(capacity) }
    public var remaining: Int { capacity - used }
    public var isOverCapacity: Bool { used > capacity }

    /// The user's real build: 65,786 bytes.
    public static let sample = FirmwareSizeMeter(used: 65_786, capacity: 122_880, parts: [
        Part(name: "QMK core & USB", bytes: 27_420),
        Part(name: "RGB Matrix + 48 animations", bytes: 18_960),
        Part(name: "ChibiOS & drivers", bytes: 9_310),
        Part(name: "Oryx live connection", bytes: 3_880),
        Part(name: "Navigator module", bytes: 3_410),
        Part(name: "Keymap & layer colours", bytes: 2_806),
    ])

    /// A layout that doesn't fit (for the overflow error state).
    public static let overflow = FirmwareSizeMeter(used: 126_212, capacity: 122_880, parts: [
        Part(name: "QMK core & USB", bytes: 27_420), Part(name: "RGB Matrix + 48 animations", bytes: 18_960),
        Part(name: "Macros (24 × 24 steps)", bytes: 41_300), Part(name: "Tap dances (31)", bytes: 18_416),
        Part(name: "ChibiOS & drivers", bytes: 9_310), Part(name: "Other", bytes: 10_806),
    ])
}

/// A line of build or flash output.
public struct BuildLogLine: Identifiable, Hashable, Sendable {
    public enum Level: String, Hashable, Sendable { case info, step, warning, error, success }
    public var id: Int
    /// Seconds since the build started.
    public var time: TimeInterval
    public var level: Level
    public var text: String
    /// Key the line refers to, when it can be mapped.
    public var key: KeyRef?
}

/// Why a build or flash failed, mapped back to a key when possible.
public struct BuildFailure: Hashable, Sendable {
    public var title: String
    public var message: String
    /// Generated source location, e.g. `keymap.c` line 47.
    public var file: String?
    public var line: Int?
    /// The key that caused it.
    public var key: KeyRef?
    public var slot: KeySlot?
    public var suggestion: String?
    /// Raw compiler output excerpt.
    public var compilerOutput: String

    /// An unknown keycode on Brd+Sys key 45 (the "Prev Tab" shortcut), as if a hand-edited code had a typo.
    public static let unknownKeycode = BuildFailure(
        title: "Unknown keycode on Brd+Sys",
        message: "The Prev Tab key uses KC_LBRACKETT, which the firmware doesn't know.",
        file: "keymap.c", line: 31, key: KeyRef(layer: 2, index: 45), slot: .tap,
        suggestion: "Did you mean KC_LBRC ([)?",
        compilerOutput: """
        keymap.c:31:83: error: 'KC_LBRACKETT' undeclared here (not in a function); did you mean 'KC_LBRACKET'?
           31 |     KC_TRANSPARENT, ..., RGUI(KC_LBRC), LGUI(LSFT(KC_LBRACKETT)), LGUI(LSFT(KC_RBRC)), ...
              |                                                   ^~~~~~~~~~~~
        """)

    /// Firmware larger than the flash window.
    public static let tooLarge = BuildFailure(
        title: "Firmware is too large",
        message: "The build is 126,212 bytes; the Voyager has room for 122,880. That's 3,332 bytes over.",
        file: nil, line: nil, key: nil, slot: nil,
        suggestion: "Turn off unused RGB animations in Settings → RGB Lighting to save up to 15 KB.",
        compilerOutput: "region `FLASH' overflowed by 3332 bytes")
}

/// Phases of the guided build → flash flow.
public enum BuildFlashPhase: Hashable, Sendable {
    case idle
    /// Writing keymap.c / config.h / rules.mk from the layout.
    case generating
    case compiling(progress: Double, file: String)
    case linking
    case built(FirmwareImage)
    /// Waiting for the user to press the reset pinhole (or a QK_BOOT key).
    case waitingForBootloader
    case erasing(progress: Double)
    case flashing(progress: Double, bytesWritten: Int, totalBytes: Int)
    case verifying(progress: Double)
    case done(FirmwareImage)
    case failed(BuildFailure)

    /// Overall 0...1 progress across the whole flow (nil when idle or failed).
    public var overallProgress: Double? {
        switch self {
        case .idle, .failed: nil
        case .generating: 0.02
        case let .compiling(p, _): 0.04 + p * 0.38
        case .linking: 0.44
        case .built: 0.48
        case .waitingForBootloader: 0.5
        case let .erasing(p): 0.5 + p * 0.1
        case let .flashing(p, _, _): 0.6 + p * 0.3
        case let .verifying(p): 0.9 + p * 0.1
        case .done: 1
        }
    }

    /// Short title for the current step.
    public var title: String {
        switch self {
        case .idle: "Ready to build"
        case .generating: "Generating firmware source"
        case .compiling: "Compiling"
        case .linking: "Linking"
        case .built: "Firmware built"
        case .waitingForBootloader: "Put the keyboard in flash mode"
        case .erasing: "Erasing"
        case .flashing: "Flashing"
        case .verifying: "Verifying"
        case .done: "Keyboard updated"
        case let .failed(f): f.title
        }
    }

    /// Guidance text for the user.
    public var guidance: String? {
        switch self {
        case .waitingForBootloader:
            "Press the reset pinhole on the top edge of the left half with a paperclip, or hold Space and press Reset (Brd+Sys, top-right key)."
        case .flashing, .erasing: "Keep the keyboard connected until this finishes."
        case .done: "Your keyboard restarted with the new layout."
        default: nil
        }
    }

    public var isBusy: Bool {
        switch self {
        case .generating, .compiling, .linking, .erasing, .flashing, .verifying: true
        default: false
        }
    }
}

/// Simulated build → flash flow with logs, size meter and a failure path. No toolchain, no USB.
///
/// For snapshots call ``jump(to:)`` with a ``Step``; for interactive prototypes call ``startBuild()``,
/// then ``continueAfterBootloader()`` when the user confirms flash mode.
@MainActor
@Observable
public final class BuildFlashSimulator {
    /// Named checkpoints for deterministic snapshots.
    public enum Step: String, CaseIterable, Sendable {
        case idle, compiling, built, waitingForBootloader, flashing, verifying, done, failedUnknownKeycode, failedTooLarge
    }

    public private(set) var phase: BuildFlashPhase = .idle
    public private(set) var log: [BuildLogLine] = []
    public private(set) var sizeMeter: FirmwareSizeMeter? = nil
    /// Make the next build fail with ``BuildFailure/unknownKeycode``.
    public var simulateFailure = false
    /// Simulated speed multiplier.
    public var speed: Double = 1

    public let layout: KeyboardLayout
    private var task: Task<Void, Never>?
    private var logID = 0

    public static let sampleImage = FirmwareImage(fileName: "zsa_voyager_KlgM7.bin", size: 65_786,
                                                  md5: "4d59bb3dba601672ecefd27e2641561c",
                                                  builtAt: Date(timeIntervalSince1970: 1_789_535_320))

    public init(layout: KeyboardLayout = Samples.layout) { self.layout = layout }

    /// A simulator already at `step`.
    public static func at(_ step: Step, layout: KeyboardLayout = Samples.layout) -> BuildFlashSimulator {
        let s = BuildFlashSimulator(layout: layout)
        s.jump(to: step)
        return s
    }

    /// Sets a deterministic state with a matching log.
    public func jump(to step: Step) {
        task?.cancel()
        log = []
        logID = 0
        sizeMeter = nil
        let files = Self.compileFiles
        switch step {
        case .idle:
            phase = .idle
        case .compiling:
            appendGenerateLog()
            for (i, f) in files.prefix(9).enumerated() { append(1.0 + Double(i) * 0.4, .info, "Compiling \(f)") }
            phase = .compiling(progress: 0.42, file: files[8])
        case .built, .waitingForBootloader, .flashing, .verifying, .done:
            appendGenerateLog()
            for (i, f) in files.enumerated() { append(1.0 + Double(i) * 0.4, .info, "Compiling \(f)") }
            appendLinkLog()
            sizeMeter = .sample
            phase = .built(Self.sampleImage)
            if step != .built {
                appendBootloaderLog()
                phase = .waitingForBootloader
            }
            if step == .flashing || step == .verifying || step == .done {
                append(16.2, .step, "Found the Voyager bootloader (3297:0791)")
                append(16.4, .info, "Erasing 33 pages")
                append(17.1, .info, "Writing 65,786 bytes")
                phase = .flashing(progress: 0.64, bytesWritten: 42_103, totalBytes: 65_786)
            }
            if step == .verifying || step == .done {
                append(19.6, .info, "Verifying")
                phase = .verifying(progress: 0.5)
            }
            if step == .done {
                append(20.4, .success, "Verified 65,786 bytes. Restarting the keyboard.")
                append(21.3, .success, "Connected: ZSA Voyager KlgM7/40xJ7M, firmware 25.0")
                phase = .done(Self.sampleImage)
            }
        case .failedUnknownKeycode:
            appendGenerateLog()
            for (i, f) in files.prefix(4).enumerated() { append(1.0 + Double(i) * 0.4, .info, "Compiling \(f)") }
            let f = BuildFailure.unknownKeycode
            append(2.7, .error, f.compilerOutput.components(separatedBy: "\n").first ?? f.message, key: f.key)
            append(2.7, .error, "Build failed: 1 error on Brd+Sys · Prev Tab (key 45).", key: f.key)
            phase = .failed(f)
        case .failedTooLarge:
            appendGenerateLog()
            for (i, f) in files.enumerated() { append(1.0 + Double(i) * 0.4, .info, "Compiling \(f)") }
            append(14.0, .step, "Linking zsa_voyager_KlgM7.elf")
            append(14.6, .error, "region `FLASH' overflowed by 3332 bytes")
            sizeMeter = .overflow
            phase = .failed(.tooLarge)
        }
    }

    /// Runs generate → compile → link, then waits for the bootloader.
    public func startBuild() {
        task?.cancel()
        log = []
        logID = 0
        sizeMeter = nil
        task = Task { [weak self] in
            guard let self else { return }
            let files = Self.compileFiles
            self.phase = .generating
            self.appendGenerateLog()
            await self.pause(0.6)
            for (i, f) in files.enumerated() {
                if Task.isCancelled { return }
                self.phase = .compiling(progress: Double(i + 1) / Double(files.count), file: f)
                self.append(1.0 + Double(i) * 0.4, .info, "Compiling \(f)")
                if self.simulateFailure && i == 3 {
                    self.jump(to: .failedUnknownKeycode)
                    return
                }
                await self.pause(0.18)
            }
            self.phase = .linking
            await self.pause(0.5)
            self.appendLinkLog()
            self.sizeMeter = .sample
            self.phase = .built(Self.sampleImage)
            await self.pause(0.6)
            self.appendBootloaderLog()
            self.phase = .waitingForBootloader
        }
    }

    /// Continues from ``BuildFlashPhase/waitingForBootloader`` through erase, flash and verify.
    public func continueAfterBootloader() {
        guard case .waitingForBootloader = phase else { return }
        task = Task { [weak self] in
            guard let self else { return }
            self.append(16.2, .step, "Found the Voyager bootloader (3297:0791)")
            for p in stride(from: 0.0, through: 1.0, by: 0.25) { self.phase = .erasing(progress: p); await self.pause(0.12) }
            let total = Self.sampleImage.size
            for i in 0...20 {
                if Task.isCancelled { return }
                let p = Double(i) / 20
                self.phase = .flashing(progress: p, bytesWritten: Int(Double(total) * p), totalBytes: total)
                await self.pause(0.1)
            }
            for p in stride(from: 0.0, through: 1.0, by: 0.2) { self.phase = .verifying(progress: p); await self.pause(0.1) }
            self.append(20.4, .success, "Verified \(total.formatted()) bytes. Restarting the keyboard.")
            self.phase = .done(Self.sampleImage)
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    // MARK: Log helpers

    static let compileFiles = [
        "keymap.c", "quantum/keyboard.c", "quantum/action.c", "quantum/action_tapping.c", "quantum/keymap_common.c",
        "quantum/rgb_matrix/rgb_matrix.c", "quantum/process_keycode/process_combo.c", "keyboards/zsa/voyager/voyager.c",
        "keyboards/zsa/voyager/matrix.c", "modules/zsa/oryx/oryx.c", "modules/zsa/navigator/navigator.c",
        "drivers/led/issi/is31fl3731.c", "tmk_core/protocol/chibios/usb_main.c", "platforms/chibios/bootloaders/custom.c",
    ]

    private func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s / max(speed, 0.01))) }

    private func append(_ t: TimeInterval, _ level: BuildLogLine.Level, _ text: String, key: KeyRef? = nil) {
        logID += 1
        log.append(BuildLogLine(id: logID, time: t, level: level, text: text, key: key))
    }

    private func appendGenerateLog() {
        append(0.0, .step, "Generating source for “\(layout.title)” (\(layout.layers.count) layers, \(layout.keyCount) keys)")
        append(0.2, .info, "Wrote keymap.c, config.h, rules.mk, keymap.json")
        append(0.5, .info, "Toolchain: arm-none-eabi-gcc 12.2.1 · QMK firmware25 (ZSA fork)")
    }

    private func appendLinkLog() {
        append(14.0, .step, "Linking zsa_voyager_KlgM7.elf")
        append(14.5, .info, "Firmware size: 65,786 of 122,880 bytes (53.5%)")
        append(14.7, .success, "Built zsa_voyager_KlgM7.bin · md5 4d59bb3d…561c")
    }

    private func appendBootloaderLog() {
        append(15.0, .step, "Waiting for the keyboard to enter flash mode…")
    }
}
