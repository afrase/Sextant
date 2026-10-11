import SwiftUI

/// What the toolbar's activity capsule shows (spec §3.5). The device and build steps feed it; the window draws it.
public struct ActivityState: Hashable, Sendable {
    public enum Device: Hashable, Sendable {
        case absent
        /// A keyboard in normal mode. `serial` is its `layout/revision`; a mismatch adds an orange ≠.
        case connected(serial: String?, matchesLayout: Bool)
        case flashMode
    }

    public enum Status: Hashable, Sendable {
        case noKeyboard
        case onKeyboard(revisionDate: Date)
        case notOnKeyboard(edits: Int)
        case otherLayout(serial: String)
        case heldByAnotherApp(String)
        case issues(count: Int, firstKey: Int?)
        case building(file: String, done: Int, total: Int)
        case built(bytes: Int, percentOfFlash: Int)
        case waitingForFlashMode
        case writing(fraction: Double, bytes: Int)
        case verifying(fraction: Double, bytes: Int)
        case flashed(revision: String)
        case buildFailed(errors: Int, key: Int?)
        case flashFailed
    }

    public var device: Device
    public var status: Status

    public init(device: Device = .absent, status: Status = .noKeyboard) {
        self.device = device
        self.status = status
    }

    var isKeyboardConnected: Bool {
        if case .connected = device { true } else { false }
    }

    /// A build or flash is running, so Build & Flash becomes Stop or Writing… (spec §3.4).
    var isBusy: Bool {
        switch status {
        case .building, .waitingForFlashMode, .writing, .verifying: true
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
        case let .onKeyboard(date):
            ActivityLook(
                symbol: "checkmark.circle.fill", tone: .success, text: String(localized: "On keyboard"),
                detail: date.formatted(.dateTime.day().month()))
        case let .notOnKeyboard(edits):
            ActivityLook(
                symbol: "arrow.up.circle", tone: .warning, text: String(localized: "Not on keyboard"),
                detail: edits == 1 ? String(localized: "1 edit") : String(localized: "\(edits) edits"))
        case let .otherLayout(serial):
            ActivityLook(
                symbol: "exclamationmark.triangle.fill", tone: .warning, text: String(localized: "Keyboard runs another layout"),
                detail: serial)
        case let .heldByAnotherApp(app):
            ActivityLook(symbol: "lock.fill", tone: .secondary, text: String(localized: "In use by \(app)"))
        case let .issues(count, key):
            ActivityLook(
                symbol: "exclamationmark.triangle.fill", tone: .warning,
                text: count == 1 ? String(localized: "1 issue") : String(localized: "\(count) issues"),
                detail: key.map { String(localized: "key \($0)") })
        case let .building(file, done, total):
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Compiling \(file)"),
                detail: String(localized: "\(done) of \(total)"),
                progress: .determinate(total > 0 ? Double(done) / Double(total) : 0))
        case let .built(bytes, percent):
            ActivityLook(
                symbol: "checkmark.circle.fill", tone: .success, text: String(localized: "Built"),
                detail: String(localized: "\(bytes.formatted()) B · \(percent)%"))
        case .waitingForFlashMode:
            ActivityLook(
                symbol: "paperclip", tone: .warning, text: String(localized: "Waiting for flash mode"),
                detail: String(localized: "Press the reset pinhole"), progress: .indeterminate)
        case let .writing(fraction, bytes):
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Writing · \(Int((fraction * 100).rounded()))%"),
                detail: String(localized: "\(bytes.formatted()) B"), progress: .determinate(fraction))
        case let .verifying(fraction, bytes):
            ActivityLook(
                symbol: nil, tone: .secondary, text: String(localized: "Verifying · \(Int((fraction * 100).rounded()))%"),
                detail: String(localized: "\(bytes.formatted()) B"), progress: .determinate(fraction))
        case let .flashed(revision):
            ActivityLook(symbol: "checkmark.seal.fill", tone: .success, text: String(localized: "Flashed"), detail: revision)
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
/// (spec §3.5). Two VoiceOver elements, one per segment.
public struct ActivityCapsule: View {
    var state: ActivityState
    var boardName: String
    /// Opens the build log or sheet; nil until Build & Flash is wired.
    var onShowLog: (() -> Void)?
    @State private var width: CGFloat = 440

    public init(state: ActivityState, boardName: String, onShowLog: (() -> Void)? = nil) {
        self.state = state
        self.boardName = boardName
        self.onShowLog = onShowLog
    }

    public var body: some View {
        let look = state.status.look
        let compact = width < 360
        HStack(spacing: 0) {
            deviceSegment(compact: compact)
                .padding(.horizontal, 12)
            Divider().frame(height: 16)
            Button {
                onShowLog?()
            } label: {
                statusSegment(look, compact: compact)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onShowLog == nil)
            .accessibilityLabel([look.text, look.detail].compactMap { $0 }.joined(separator: ", "))
        }
        .frame(minWidth: 280, idealWidth: 440, maxWidth: 520, minHeight: 28)
        .overlay(alignment: .bottom) { hairline(look.progress) }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
    }

    // shortcut: the device segment becomes a button when the Device popover exists (spec step 9).
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
                Text(verbatim: serial).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
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

    private func statusSegment(_ look: ActivityLook, compact: Bool) -> some View {
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
            if let detail = look.detail, !compact {
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private func hairline(_ progress: ActivityLook.Progress) -> some View {
        switch progress {
        case .none: EmptyView()
        case let .determinate(fraction):
            GeometryReader { proxy in
                Capsule().fill(Color.accentColor).frame(width: proxy.size.width * min(max(fraction, 0), 1), height: 2)
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
        case .indeterminate:
            // shortcut: a static line (the Reduce Motion look); the shimmer comes with the flash step (spec §10.6).
            Capsule().fill(Color.accentColor.opacity(0.4)).frame(height: 2).padding(.horizontal, 14)
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
