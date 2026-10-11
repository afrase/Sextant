import SextantApplication
import SextantDomain
import SwiftUI

/// The window's device and Build & Flash wiring: the sheet, following the keyboard, VoiceOver announcements, and the
/// capsule's "Flashed" giving way to the keyboard's status after 8 s when the sheet is hidden (spec §3.5, §7, §8.2, §11).
struct DeviceWiring: ViewModifier {
    @Bindable var model: LayoutWindowModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.showsBuildSheet) { BuildFlashSheet(model: model) }
            .task { await model.followKeyboard() }
            .task(id: model.isFlashedOutOfSight) {
                guard model.isFlashedOutOfSight, (try? await Task.sleep(for: .seconds(8))) != nil else { return }
                model.buildFlash?.stop()
            }
            .onChange(of: model.buildFlash?.phase) { old, new in
                if let text = BuildFlashText.announcement(from: old, to: new) { AccessibilityNotification.Announcement(text).post() }
            }
    }
}

extension LayoutWindowModel {
    /// A flash finished while the sheet was hidden: the capsule says "Flashed" for a while.
    var isFlashedOutOfSight: Bool {
        if case .done = buildFlash?.phase { !showsBuildSheet } else { false }
    }
}

/// The Build & Flash sheet (spec §7.2, §7.3): five steps, the spec's copy for every phase, and the actions that phase
/// allows. It only shows what `BuildFlashSession` reports: writing starts on its own once a validated image meets
/// exactly one bootloader, so there is no "Flash Now", and nothing stops a flash once it writes.
public struct BuildFlashSheet: View {
    var model: LayoutWindowModel

    public init(model: LayoutWindowModel) { self.model = model }

    public var body: some View {
        if let build = model.buildFlash, let session = model.session {
            let phase = build.phase
            let step = BuildFlashText.step(phase)
            let keyboard = [model.boardName, model.live?.firmwareSerial].compactMap { $0 }.joined(separator: " ")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BuildFlashText.title(phase)).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text(verbatim: "\(session.layout.title) → \(keyboard)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("Step \(step) of 5").font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
                StepIndicator(
                    step: step, isStepDone: phase == .built || step == 5, failed: phase.isFailure, sublabels: sublabels(phase, build)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                Divider()
                BuildFlashBody(model: model, build: build, phase: phase).padding(20)
                Divider()
                footer(phase, build)
            }
            .frame(width: 640)
            .presentationSizing(.fitted)
        }
    }

    private func sublabels(_ phase: BuildFlashSession.Phase, _ build: BuildFlashSession) -> [String?] {
        let step = BuildFlashText.step(phase)
        let percent: String? =
            switch phase {
            case let .erasing(done, total), let .writing(done, total):
                total > 0 ? "\(Int((Double(done) / Double(total) * 100).rounded()))%" : nil
            default: nil
            }
        return [
            build.usedBytes.map { Int64($0).formatted(.byteCount(style: .file)) },
            step == 2 ? String(localized: "Waiting") : step > 2 ? String(localized: "Found") : nil,
            percent, nil, nil,
        ]
    }

    private func footer(_ phase: BuildFlashSession.Phase, _ build: BuildFlashSession) -> some View {
        let pid = model.board.bootloaderProductIDs.first { $0.value == .stm32 }?.key ?? 0
        let usb = String(format: "%04X:%04X", model.board.vendorID, pid)
        return HStack(spacing: 12) {
            Label {
                Text("Sextant writes only to the keyboard’s bootloader (\(usb)) and checks the image first.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            buttons(phase, build)
        }
        .padding(16)
    }

    @ViewBuilder private func buttons(_ phase: BuildFlashSession.Phase, _ build: BuildFlashSession) -> some View {
        let hide = { model.showsBuildSheet = false }
        let stop = {
            build.stop()
            model.showsBuildSheet = false
        }
        switch phase {
        case .idle:
            Button("Close", action: hide).keyboardShortcut(.cancelAction)
            Button("Build & Flash") { model.build(.buildAndFlash) }.keyboardShortcut(.defaultAction).disabled(!model.canBuild)
        case .blocked:
            Button("Close", action: hide).keyboardShortcut(.defaultAction)
        case .confirmingReplace:
            Button("Cancel", action: stop).keyboardShortcut(.cancelAction)
            Button("Replace and Flash") { build.confirmReplace() }.keyboardShortcut(.defaultAction)
        case .needsSetup:
            Button("Cancel", action: stop).keyboardShortcut(.cancelAction)
            // shortcut: the setup step that downloads the build tools comes after the user approves the download.
            Button("Download and Build") {}.disabled(true)
        case .generating, .compiling, .linking:
            Button("Hide", action: hide).keyboardShortcut(.cancelAction)
            Button("Stop", action: stop)
        case .built:
            Button("Close", action: hide).keyboardShortcut(.cancelAction)
            Button("Flash…") { build.flash(connectedKeyboard: model.connectedKeyboard) }.keyboardShortcut(.defaultAction)
        case .waitingForFlashMode:
            Button("Hide", action: hide).keyboardShortcut(.cancelAction)
            Button("Cancel", action: stop)
        case .validating, .erasing, .writing, .verifying:
            Button("Hide", action: hide).keyboardShortcut(.cancelAction)
            Button("Cancel") {}
                .disabled(true)
                .help(
                    Text(
                        "Can’t stop while writing. If the cable comes out, the keyboard stays in flash mode and you can simply flash again."
                    ))
        case .done:
            Button("Done", action: stop).keyboardShortcut(.defaultAction)
        case .failed:
            Button("Close", action: hide).keyboardShortcut(.cancelAction)
            Button("Try Again") { build.retry() }.keyboardShortcut(.defaultAction)
        }
    }
}

extension BuildFlashSession.Phase {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}

/// The sheet's words that depend only on the phase (spec §7.3, §11).
enum BuildFlashText {
    static func title(_ phase: BuildFlashSession.Phase) -> String {
        switch phase {
        case .idle: String(localized: "Build & Flash")
        case let .blocked(issues) where issues.count == 1: String(localized: "Fix 1 issue before building")
        case let .blocked(issues): String(localized: "Fix \(issues.count) issues before building")
        case .confirmingReplace: String(localized: "Replace the layout on this keyboard?")
        case .needsSetup: String(localized: "Set up the build tools")
        case .generating, .compiling, .linking: String(localized: "Building firmware")
        case .built: String(localized: "Firmware built")
        case .waitingForFlashMode: String(localized: "Put the keyboard in flash mode")
        case .validating, .erasing, .writing: String(localized: "Flashing")
        case .verifying: String(localized: "Verifying")
        case .done: String(localized: "Flashed")
        case let .failed(error): failureTitle(error)
        }
    }

    static func failureTitle(_ error: BuildFlashError) -> String {
        switch error {
        case let .toolchain(.compileFailed(diagnostics)):
            let count = max(diagnostics.filter { $0.severity == .error }.count, 1)
            return count == 1 ? String(localized: "Build failed: 1 error") : String(localized: "Build failed: \(count) errors")
        case let .toolchain(.tooLarge(over)): return String(localized: "Firmware is \(over.formatted()) bytes too large")
        case .generator, .toolchain: return String(localized: "Build failed")
        case .flash(.imageRejected), .flash(.checksumMismatch): return String(localized: "Sextant won’t flash this image")
        case .flash(.hardwareAccessOff): return String(localized: "Flashing is off")
        case .flash: return String(localized: "Flashing didn’t finish")
        case .multipleBootloaders, .notReconnected, .unexpectedSerial: return String(localized: "Build & Flash stopped")
        }
    }

    /// The step indicator's position: Build · Flash mode · Write · Verify · Done (spec §7.2).
    static func step(_ phase: BuildFlashSession.Phase) -> Int {
        switch phase {
        case .waitingForFlashMode, .failed(.multipleBootloaders): 2
        case .validating, .erasing, .writing, .failed(.flash): 3
        case .verifying, .failed(.notReconnected), .failed(.unexpectedSerial): 4
        case .done: 5
        default: 1
        }
    }

    /// What VoiceOver says as a run moves on: the build's outcome, flashing at each quarter, and the end (spec §11).
    static func announcement(from old: BuildFlashSession.Phase?, to new: BuildFlashSession.Phase?) -> String? {
        switch new {
        case .built: return String(localized: "Build succeeded")
        case .done: return String(localized: "Flashed")
        case let .failed(error): return failureTitle(error)
        case let .writing(done, total) where total > 0:
            let quarter = done * 4 / total
            let before = if case let .writing(d, t) = old, t > 0 { d * 4 / t } else { 0 }
            return (1...3).contains(quarter) && quarter > before ? String(localized: "Flashing, \(quarter * 25) percent") : nil
        default: return nil
        }
    }
}
