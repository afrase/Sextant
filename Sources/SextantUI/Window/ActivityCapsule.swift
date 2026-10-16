import SwiftUI

/// What the toolbar's activity capsule shows (spec §3.5). The window derives it from the live session and Build & Flash.
public struct ActivityState: Hashable, Sendable {
    public enum Device: Hashable, Sendable {
        case absent
        /// A keyboard in normal mode. `serial` is its `layout/revision`; a mismatch adds an orange ≠.
        case connected(serial: String?, matchesLayout: Bool)
        case flashMode
    }

    public enum Status: Hashable, Sendable {
        case noKeyboard
        /// A keyboard, with no layout open to compare it with.
        case keyboardConnected
        case onKeyboard(revisionDate: Date)
        /// An earlier build of this layout is on the keyboard; `edits` when Sextant can count them.
        case notOnKeyboard(edits: Int?)
        /// The keyboard runs another layout: its name when the library holds it (the serial already shows beside it).
        case otherLayout(name: String?)
        /// The keyboard runs revision `number` of this layout, which Sextant read from the keyboard and added to History
        /// without making it the working copy (ADR 0061). [Use It] restores it.
        case keyboardRunsRevision(number: Int)
        case heldByAnotherApp(String)
        /// The keyboard sits in flash mode with no flash running.
        case inFlashMode
        case issues(count: Int, firstKey: Int?)
        /// The build tools need their one-time setup (spec §7.3).
        case needsSetup
        /// Downloading, then installing (at 1), the build tools.
        case settingUp(fraction: Double)
        case generating
        case building(file: String, done: Int, total: Int)
        case linking
        case built(bytes: Int, percentOfFlash: Int)
        case waitingForFlashMode
        case erasing(fraction: Double)
        case writing(fraction: Double, bytes: Int)
        /// Waiting for the keyboard to come back with the new firmware; it has no percentage.
        case verifying
        case flashed(revision: String)
        /// Flashed, but the flash couldn't be recorded in History; the sheet says why.
        case flashedNotSaved
        /// Another window's Build & Flash holds flash mode (spec §7.6).
        case flashingElsewhere(layout: String)
        case buildFailed(errors: Int, key: Int?)
        case flashFailed
    }

    public var device: Device
    public var status: Status

    public init(device: Device = .absent, status: Status = .noKeyboard) {
        self.device = device
        self.status = status
    }

    /// A serial short enough for the capsule: an Oryx one (`KlgM7/40xJ7M`) as it is, Sextant's longer `sx-` one cut in
    /// the middle (`sx-C57F…DE1F`). The whole serial is the tooltip and what VoiceOver reads.
    static func shortSerial(_ serial: String) -> String {
        serial.count <= 14 ? serial : "\(serial.prefix(7))…\(serial.suffix(4))"
    }

    var isKeyboardConnected: Bool {
        if case .connected = device { true } else { false }
    }

    /// A build or flash is running, so Build & Flash becomes Stop or Writing… (spec §3.4).
    var isBusy: Bool {
        switch status {
        case .settingUp, .generating, .building, .linking, .waitingForFlashMode, .erasing, .writing, .verifying: true
        default: false
        }
    }
}

/// How one status row of spec §3.5 looks.
struct ActivityLook: Equatable {
    enum Tone: Equatable { case secondary, success, warning, danger }
    enum Progress: Equatable { case none, determinate(Double), indeterminate }
    /// SF Symbol, or nil for a spinner.
    var symbol: String?
    var tone: Tone
    var text: String
    var detail: String?
    var progress: Progress = .none
}

extension ActivityState.Status {
    var look: ActivityLook {
        switch self {
        case .noKeyboard:
            ActivityLook(symbol: "circle.fill", tone: .secondary, text: String(localized: "No keyboard"))
        case .keyboardConnected:
            ActivityLook(symbol: "keyboard", tone: .secondary, text: String(localized: "Keyboard connected"))
        case let .onKeyboard(date):
            ActivityLook(
                symbol: "checkmark.circle.fill", tone: .success, text: String(localized: "On keyboard"),
                detail: date.formatted(.dateTime.day().month()))
        case let .notOnKeyboard(edits):
            ActivityLook(
                symbol: "arrow.up.circle", tone: .warning, text: String(localized: "Not on keyboard"),
                detail: edits.map { $0 == 1 ? String(localized: "1 edit") : String(localized: "\($0) edits") })
        case let .otherLayout(name):
            ActivityLook(
                symbol: "exclamationmark.triangle.fill", tone: .warning,
                text: name.map { String(localized: "Keyboard runs ‘\($0)’") } ?? String(localized: "Keyboard runs another layout"))
        case let .keyboardRunsRevision(number):
            ActivityLook(symbol: "arrow.down.circle", tone: .warning, text: String(localized: "Keyboard runs revision \(number)"))
        case let .heldByAnotherApp(app):
            ActivityLook(symbol: "lock.fill", tone: .secondary, text: String(localized: "In use by \(app)"))
        case .inFlashMode:
            ActivityLook(symbol: "button.horizontal.top.press", tone: .warning, text: String(localized: "Keyboard in flash mode"))
        case let .issues(count, key):
            ActivityLook(
                symbol: "exclamationmark.triangle.fill", tone: .warning,
                text: count == 1 ? String(localized: "1 issue") : String(localized: "\(count) issues"),
                detail: key.map { String(localized: "key \($0)") })
        case .needsSetup:
            ActivityLook(
                symbol: "hammer.fill", tone: .warning, text: String(localized: "Build tools needed"), detail: String(localized: "Set up"))
        case let .settingUp(fraction) where fraction >= 1:
            ActivityLook(symbol: nil, tone: .secondary, text: String(localized: "Installing build tools"), progress: .indeterminate)
        case let .settingUp(fraction):
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Downloading build tools · \(Int((fraction * 100).rounded()))%"),
                progress: .determinate(fraction))
        case .generating:
            ActivityLook(symbol: nil, tone: .secondary, text: String(localized: "Generating source"), progress: .indeterminate)
        case let .building(file, done, total):
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Compiling \(file)"),
                detail: String(localized: "\(done) of \(total)"),
                progress: .determinate(total > 0 ? Double(done) / Double(total) : 0))
        case .linking:
            ActivityLook(symbol: nil, tone: .secondary, text: String(localized: "Linking"), progress: .indeterminate)
        case let .built(bytes, percent):
            ActivityLook(
                symbol: "checkmark.circle.fill", tone: .success, text: String(localized: "Built"),
                detail: String(localized: "\(bytes.formatted()) B · \(percent)%"))
        case .waitingForFlashMode:
            ActivityLook(
                symbol: "button.horizontal.top.press", tone: .warning, text: String(localized: "Waiting for flash mode"),
                progress: .indeterminate)
        case let .erasing(fraction):
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Erasing · \(Int((fraction * 100).rounded()))%"),
                progress: .determinate(fraction))
        case let .writing(fraction, bytes):
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Writing · \(Int((fraction * 100).rounded()))%"),
                detail: String(localized: "\(bytes.formatted()) B"), progress: .determinate(fraction))
        case .verifying:
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Verifying"), detail: String(localized: "Reconnecting"),
                progress: .indeterminate)
        case let .flashed(revision):
            ActivityLook(symbol: "checkmark.seal.fill", tone: .success, text: String(localized: "Flashed"), detail: revision)
        case .flashedNotSaved:
            ActivityLook(
                symbol: "checkmark.seal.fill", tone: .warning, text: String(localized: "Flashed"),
                detail: String(localized: "Not saved in History"))
        case let .flashingElsewhere(layout):
            ActivityLook(symbol: "bolt.fill", tone: .secondary, text: String(localized: "Flashing from ‘\(layout)’"))
        case let .buildFailed(errors, key):
            ActivityLook(
                symbol: "xmark.octagon.fill", tone: .danger, text: String(localized: "Build Failed"),
                detail: [
                    errors == 1 ? String(localized: "1 error") : String(localized: "\(errors) errors"),
                    key.map { String(localized: "key \($0)") },
                ]
                .compactMap { $0 }.joined(separator: " · "))
        case .flashFailed:
            ActivityLook(
                symbol: "xmark.octagon.fill", tone: .danger, text: String(localized: "Flashing didn't finish"),
                detail: String(localized: "Try again"))
        }
    }
}

/// The toolbar's centre capsule: `[● Voyager KlgM7/40xJ7M] │ [icon status … detail]` with a progress hairline
/// (spec §3.5). Two buttons, one per segment, each with its own VoiceOver label.
public struct ActivityCapsule: View {
    var state: ActivityState
    var boardName: String
    /// Opens the Device popover; nil where there is no live session.
    var onShowDevice: (() -> Void)?
    /// Opens the Build & Flash sheet; nil where building is off.
    var onShowLog: (() -> Void)?
    /// [Use It] while the keyboard runs a revision the working copy isn't (``ActivityState/Status/keyboardRunsRevision(number:)``):
    /// restores that revision. Nil where there is nothing to restore it in.
    var onUseRevision: (() -> Void)?
    /// Narrower in small windows, so the toolbar's trailing items stay out of its overflow menu.
    var idealWidth: CGFloat
    @State private var width: CGFloat = 440

    public init(
        state: ActivityState, boardName: String, onShowDevice: (() -> Void)? = nil, onShowLog: (() -> Void)? = nil,
        onUseRevision: (() -> Void)? = nil, idealWidth: CGFloat = 440
    ) {
        self.state = state
        self.boardName = boardName
        self.onShowDevice = onShowDevice
        self.onShowLog = onShowLog
        self.onUseRevision = onUseRevision
        self.idealWidth = idealWidth
    }

    public var body: some View {
        let look = state.status.look
        let compact = width < 360
        HStack(spacing: 0) {
            segment(onShowDevice) { deviceSegment(compact: compact) }
            Divider().frame(height: 16)
            if let useRevision {
                // Its own button, so the segment isn't one: a button in a button takes no clicks. VoiceOver reads one
                // element, without the symbol, whose action is Use It.
                statusSegment(look, compact: compact, useRevision: useRevision).padding(.horizontal, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(look.text)
                    .accessibilityHint(Text("Make the revision the keyboard runs your working copy. Your edits stay in History."))
                    .accessibilityAction(named: Text("Use It"), useRevision)
            } else {
                segment(onShowLog) { statusSegment(look, compact: compact) }
                    .accessibilityLabel([look.text, look.detail].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .frame(minWidth: 280, idealWidth: idealWidth, maxWidth: 520, minHeight: 28)
        .overlay(alignment: .bottom) { ProgressHairline(progress: look.progress) }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
    }

    /// [Use It]'s action while the status offers it.
    private var useRevision: (() -> Void)? {
        if case .keyboardRunsRevision = state.status { onUseRevision } else { nil }
    }

    /// A button when there is something to open, else just its label.
    @ViewBuilder private func segment(_ action: (() -> Void)?, @ViewBuilder label: () -> some View) -> some View {
        let content = label().padding(.horizontal, 12).contentShape(Rectangle())
        if let action { Button(action: action) { content }.buttonStyle(.plain) } else { content }
    }

    private func deviceSegment(compact: Bool) -> some View {
        let (dot, serial, mismatch): (Color, String?, Bool) =
            switch state.device {
            case .absent: (.secondary, nil, false)
            case let .connected(serial, matches): (Tokens.success.color, serial, !matches)
            case .flashMode: (Tokens.warning.color, nil, false)
            }
        return HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(verbatim: boardName).font(.callout.weight(.semibold)).lineLimit(1)
            if let serial, !compact {
                Text(verbatim: ActivityState.shortSerial(serial)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).help(serial)
            }
            if mismatch { Text(verbatim: "≠").font(.callout.weight(.bold)).foregroundStyle(Tokens.warning.color) }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deviceLabel(serial: serial, mismatch: mismatch))
    }

    private func deviceLabel(serial: String?, mismatch: Bool) -> String {
        let status =
            switch state.device {
            case .absent: String(localized: "not connected")
            case .connected: String(localized: "connected")
            case .flashMode: String(localized: "in flash mode")
            }
        let parts = [boardName, status, serial, mismatch ? String(localized: "runs a different layout") : nil]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    private func statusSegment(_ look: ActivityLook, compact: Bool, useRevision: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            if let symbol = look.symbol {
                Image(systemName: symbol)
                    .imageScale(look.tone == .secondary && symbol == "circle.fill" ? .small : .medium)
                    .foregroundStyle(color(look.tone))
            } else {
                ProgressView().controlSize(.mini)
            }
            Text(look.text).font(.callout).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 6)
            if let useRevision {
                Button("Use It", action: useRevision).controlSize(.small)
                    .help(Text("Make the revision the keyboard runs your working copy. Your edits stay in History."))
            } else if let detail = look.detail, !compact {
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func color(_ tone: ActivityLook.Tone) -> Color {
        switch tone {
        case .secondary: .secondary
        case .success: Tokens.success.color
        case .warning: Tokens.warning.color
        case .danger: Tokens.danger.color
        }
    }
}

/// The capsule's 2 pt progress line: a fill for a known fraction, a shimmer while waiting (static under Reduce
/// Motion, spec §10.6).
private struct ProgressHairline: View {
    var progress: ActivityLook.Progress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch progress {
        case .none: EmptyView()
        case let .determinate(fraction):
            GeometryReader { proxy in
                Capsule().fill(Color.accentColor).frame(width: proxy.size.width * min(max(fraction, 0), 1), height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
        case .indeterminate:
            Capsule().fill(Color.accentColor.opacity(0.3)).frame(height: 2)
                .overlay {
                    if !reduceMotion {
                        TimelineView(.animation) { context in
                            GeometryReader { proxy in
                                // One sweep every 2.4 s.
                                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                                Capsule().fill(Color.accentColor).frame(width: proxy.size.width / 4, height: 2)
                                    .offset(x: (proxy.size.width * 1.25) * phase - proxy.size.width / 4)
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
        }
    }
}
