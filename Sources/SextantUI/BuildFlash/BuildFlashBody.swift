import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// The sheet's body for each phase (spec §7.3).
struct BuildFlashBody: View {
    var model: LayoutWindowModel
    var build: BuildFlashSession
    var phase: BuildFlashSession.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            Text("Sextant builds the firmware on this Mac, then writes it once you put the keyboard in flash mode.")
            log
        case let .blocked(issues):
            Text("Sextant checks the layout before every build. These keys need fixing first.")
            capped {
                ForEach(issues) { issue in
                    issueRow(
                        message: model.session.map { KeyText.issueText(issue, layout: $0.layout) } ?? "", location: nil, key: issue.key)
                }
            }
        case let .confirmingReplace(serial, title):
            Text(replaceText(serial: serial, title: title)).fixedSize(horizontal: false, vertical: true)
        case let .needsSetup(detail):
            Text(
                """
                Sextant builds firmware on this Mac with the compiler ZSA uses, the QMK tools and ZSA’s firmware \
                source. Each build runs sandboxed: no network, and no access to your files.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: detail).font(.callout).foregroundStyle(.secondary)
            Label(
                "Downloads come from Arm, the Python project, Homebrew, PyPI and GitHub, each checked against a pinned checksum.",
                systemImage: "checkmark.shield"
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case let .settingUp(received, total):
            let file = ByteCountFormatter.self
            if received < total {
                Text("Downloading the build tools…")
                ProgressView(value: Double(received), total: Double(max(total, 1)))
                Text(
                    "\(file.string(fromByteCount: received, countStyle: .file)) of \(file.string(fromByteCount: total, countStyle: .file))"
                )
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing the build tools…")
                }
            }
            Text("This happens once. The build starts as soon as the tools are ready.").font(.callout).foregroundStyle(.secondary)
        case .generating, .compiling, .linking:
            building
            log
        case .built:
            if let used = build.usedBytes { SizeMeter(used: used, capacity: build.capacity) }
            Text("Built without flashing. Flash it now, or any time with Build & Flash (⌘R).").foregroundStyle(.secondary)
            log
        case let .waitingForFlashMode(stillWaiting):
            FlashModeCards(layout: model.session?.layout)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the keyboard to enter flash mode…")
            }
            Text(
                """
                The keyboard’s lights go dark and it disconnects while in flash mode. That’s expected. \
                Sextant starts writing as soon as it sees the bootloader.
                """
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if stillWaiting {
                Label(
                    """
                    Still waiting? Connect the cable straight to this Mac rather than through a hub, \
                    then press the pinhole once more.
                    """,
                    systemImage: "info.circle"
                )
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        case .validating, .erasing, .writing, .verifying:
            flashing
        case let .done(revision, saveError):
            DoneSeal()
            done(revision: revision, saveError: saveError)
        case let .failed(error):
            failed(error)
        }
    }

    // MARK: Parts

    private var log: some View {
        @Bindable var model = model
        return Group {
            if !build.log.isEmpty {
                DisclosureGroup("Show Log", isExpanded: $model.showsBuildLog) {
                    ScrollView {
                        Text(verbatim: build.log.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 96)  // six lines, tailing the build
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                }
            }
        }
    }

    private var building: some View {
        let stage =
            switch phase {
            case .generating: 0
            case .compiling: 1
            default: 2
            }
        let compile: (detail: String?, fraction: Double?) =
            if case let .compiling(_, done, total) = phase, total > 0 {
                (String(localized: "\(done) of \(total)"), Double(done) / Double(total))
            } else {
                (nil, nil)
            }
        return VStack(alignment: .leading, spacing: 8) {
            stageRow(String(localized: "Generate source"), state: stage > 0 ? 1 : 0)
            stageRow(String(localized: "Compile"), state: stage > 1 ? 1 : stage == 1 ? 0 : -1, detail: compile.detail)
            if let fraction = compile.fraction { ProgressView(value: fraction).padding(.leading, 26) }
            stageRow(String(localized: "Link"), state: stage == 2 ? 0 : -1)
        }
    }

    /// `state`: -1 waiting, 0 running, 1 done.
    private func stageRow(_ title: String, state: Int, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Group {
                if state == 0 {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state > 0 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(state > 0 ? AnyShapeStyle(Tokens.success.color) : AnyShapeStyle(.tertiary))
                }
            }
            .frame(width: 18)
            Text(title).foregroundStyle(state < 0 ? .secondary : .primary)
            Spacer()
            if let detail { Text(detail).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    private var flashing: some View {
        let (fraction, name, segment): (Double?, String, Int) =
            switch phase {
            case let .erasing(done, total): (total > 0 ? Double(done) / Double(total) : 0, String(localized: "Erasing"), 0)
            case let .writing(done, total): (total > 0 ? Double(done) / Double(total) : 0, String(localized: "Writing"), 1)
            case .verifying: (nil, String(localized: "Verifying"), 2)
            default: (nil, String(localized: "Checking"), 0)
            }
        var facts = [String(format: "0x%08X", model.board.flashStart)]
        if case let .bootloader(device)? = model.live?.connection { facts.insert(device.kind.rawValue.uppercased(), at: 0) }
        if case let .writing(done, total) = phase { facts.append(String(localized: "\(done.formatted()) of \(total.formatted()) bytes")) }
        return HStack(alignment: .center, spacing: 24) {
            SextantRing(fraction: segment == 2 ? 1 : fraction, label: name, showsPercent: fraction != nil)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(
                        Array([String(localized: "Erase"), String(localized: "Write"), String(localized: "Verify")].enumerated()),
                        id: \.offset
                    ) {
                        index, title in
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(index <= segment ? Color.accentColor : Color.secondary.opacity(0.2)).frame(height: 4)
                            Text(title).font(.caption).foregroundStyle(index == segment ? .primary : .secondary)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Step \(segment + 1) of 3: \(name)"))
                Text(verbatim: facts.joined(separator: " · ")).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                if segment == 2 {
                    Text("The keyboard restarts with the new firmware. Sextant waits for it to report its new serial.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Label {
                    Text("Keep the keyboard connected until this finishes.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.warning.color)
                }
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Tokens.warning.color.opacity(0.12)))
            }
        }
    }

    @ViewBuilder private func done(revision: RevisionSummary?, saveError: LibraryError?) -> some View {
        let title = model.session?.layout.title ?? ""
        VStack(spacing: 6) {
            if let revision {
                Text("Your \(model.boardName) is running ‘\(title)’, revision \(revision.number).")
            } else {
                Text("Your \(model.boardName) is running ‘\(title)’.")
            }
            if let serial = build.identity?.serial {
                Text("It reconnected and reported \(serial) ✓.").foregroundStyle(.secondary)
            }
            if let saveError {
                Text("Sextant couldn’t record this flash in History. \(saveError.localizedDescription)").foregroundStyle(
                    Tokens.danger.color)
            } else {
                Text("Saved as a revision in History.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder private func failed(_ error: BuildFlashError) -> some View {
        switch error {
        case let .toolchain(.compileFailed(diagnostics)):
            let errors = diagnostics.filter { $0.severity == .error }
            capped {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, d in
                    issueRow(message: d.message, location: location(d), key: d.key)
                }
            }
            if errors.isEmpty || errors.contains(where: { $0.key == nil }) {
                HStack {
                    Text("The compiler reported an error Sextant couldn’t place on a key.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(build.log.joined(separator: "\n"), forType: .string)
                    }
                }
            }
            log
        case let .toolchain(.tooLarge(over)):
            SizeMeter(used: build.capacity + over, capacity: build.capacity)
            Text("Turn off features you don’t use in Firmware Settings, such as RGB animations, then build again.")
                .foregroundStyle(.secondary)
            log
        case .flash(.dfuError), .flash(.timeout), .flash(.transfer), .flash(.deviceNotFound), .flash(.deviceBusy):
            Text(
                """
                Nothing is broken: the bootloader can’t be overwritten, so you can always try again. \
                Put the keyboard in flash mode again to retry.
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Show Details") {
                Text(verbatim: BuildFlashText.details(error)).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .generator(.unsupported(_, key?)):
            issueRow(message: error.localizedDescription, location: nil, key: key)
            log
        default:
            Text(error.localizedDescription).fixedSize(horizontal: false, vertical: true)
            if case .generator = error { log }
        }
    }

    /// A list that scrolls past about seven rows, so a long one doesn't bury what follows it.
    private func capped(@ViewBuilder _ rows: () -> some View) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) { rows() } }.scrollBounceBehavior(.basedOnSize).frame(maxHeight: 280)
    }

    private func issueRow(message: String, location: String?, key: KeyRef?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(Tokens.danger.color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).fixedSize(horizontal: false, vertical: true)
                if let location { Text(verbatim: location).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if let key {
                Button("Show Key") {
                    model.showIssue(key)
                    model.showsBuildSheet = false
                }
                .controlSize(.small)
            }
        }
    }

    /// "keymap.c:31 · Brd+Sys key 45 · Tap".
    private func location(_ d: Diagnostic) -> String {
        var parts = ["\(d.file.split(separator: "/").last.map(String.init) ?? d.file):\(d.line)"]
        if let key = d.key {
            let layer = model.session?.layout.layers[safe: key.layer]?.title ?? ""
            parts.append(String(localized: "\(layer) key \(key.index)"))
            if let slot = key.slot { parts.append(slot.title) }
        }
        return parts.joined(separator: " · ")
    }

    private func replaceText(serial: String?, title: String?) -> String {
        let layout = model.session?.layout.title ?? ""
        return switch (serial, title) {
        case let (serial?, title?):
            String(
                localized: """
                    This keyboard runs ‘\(title)’ (\(serial)). Flashing replaces it with ‘\(layout)’. \
                    You can flash the old one back from History.
                    """)
        case let (serial?, nil):
            String(localized: "This keyboard runs \(serial), a layout that isn’t in your library. Flashing replaces it with ‘\(layout)’.")
        default: String(localized: "This keyboard’s firmware doesn’t say which layout it runs. Flashing replaces it with ‘\(layout)’.")
        }
    }
}

/// `checkmark.seal.fill`, bouncing once (none under Reduce Motion; spec §10.6).
private struct DoneSeal: View {
    @State private var bounced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 44))
            .foregroundStyle(Tokens.success.color)
            .symbolEffect(.bounce, value: bounced)
            .frame(maxWidth: .infinity)
            .onAppear { bounced = !reduceMotion }
            .accessibilityHidden(true)
    }
}
