import SextantApplication
import SextantDomain
import SwiftUI

/// What Sextant offers while the keyboard runs a layout it doesn't have (ADR 0061), by the keyboard layout pull's status:
/// the line in the device card, the Device popover and the menu bar panel.
public enum KeyboardLayoutPrompt: Equatable, Sendable {
    /// Nothing read: [Get Layout] reads the layout the firmware stores, turning on Live View first. `serial` is the
    /// keyboard's.
    case notInLibrary(serial: String)
    /// Reading; the fraction read so far.
    case reading(Double)
    /// The firmware stores no layout: Oryx's build, or a Sextant build that doesn't.
    case noRecord
    /// Read, and no library layout is linked to it: [Add to Library…] opens the Layout on the Keyboard window.
    case found(title: String)
    /// Reading or adding it failed, and why: [Try Again].
    case failed(String)

    /// The prompt for the pull's `status` while the keyboard reports `serial` and Sextant doesn't have the layout it runs;
    /// nil otherwise, and once the pull has put it in the library.
    public init?(_ status: KeyboardLayoutPull.Status, serial: String?, runsKnownLayout: Bool) {
        guard let serial, !runsKnownLayout else { return nil }
        switch status {
        case .idle: self = .notInLibrary(serial: serial)
        case let .reading(fraction): self = .reading(fraction)
        case .noRecord: self = .noRecord
        case let .found(found): self = .found(title: found.layout.title)
        case let .failed(failure): self = .failed(failure.localizedDescription)
        case .added: return nil
        }
    }

    /// The prompt for the keyboard as Sextant sees it now: the card's, the Device popover's and the menu bar's. None until
    /// ``OnKeyboard`` has looked the serial up, or a layout the library has would read as missing for a moment on every
    /// connect. None for an Oryx serial of an Oryx layout in the library either, as before Sextant read layouts back:
    /// Oryx's build stores no layout, and Import from Oryx brings in its revision (spec §3.6).
    @MainActor
    init?(_ status: KeyboardLayoutPull.Status, live: LiveSession, onKeyboard: OnKeyboard, entries: [LibraryEntry]) {
        let serial = live.firmwareSerial
        guard onKeyboard.resolvedSerial == serial, !LayoutWindowModel.oryxLayoutInLibrary(serial, entries: entries) else {
            return nil
        }
        self.init(status, serial: serial, runsKnownLayout: onKeyboard.running != nil)
    }

    /// ``noRecord``'s words, in the prompt and in the Layout on the Keyboard window.
    static var noRecordText: String {
        String(
            localized: """
                This firmware doesn’t store its layout. On the Mac that has the layout, turn on Store the layout in the \
                firmware in Settings › Build, then Build & Flash once; after that any Mac can read it.
                """)
    }
}

/// A ``KeyboardLayoutPrompt``'s line and its buttons: [Get Layout], [Add to Library…] or [Try Again], beside the Oryx
/// [Import] when there is one.
struct KeyboardLayoutPromptView: View {
    /// How ``KeyboardLayoutPrompt/notInLibrary(serial:)`` reads.
    enum Wording {
        /// "Runs ‹serial› · not in your library": the device card and the Device popover.
        case serial
        /// Without the serial, which the menu bar panel's header already names.
        case plain
        /// Only its button: a note just above already says Sextant doesn't have the layout.
        case buttonOnly
    }

    var prompt: KeyboardLayoutPrompt
    /// Live View is on, so Get Layout only reads.
    var isLive: Bool
    var wording = Wording.serial
    var font = Font.caption
    var getLayout: @MainActor () -> Void
    var addToLibrary: @MainActor () -> Void
    /// The Oryx [Import], for an Oryx serial.
    var importFromOryx: (@MainActor () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            message
            if hasButtons {
                HStack(spacing: 6) {
                    action
                    if let importFromOryx { Button("Import", action: importFromOryx) }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var message: some View {
        switch prompt {
        case let .notInLibrary(serial):
            switch wording {
            case .serial: line(Text("Runs \(serial) · not in your library"))
            case .plain: line(Text("Sextant doesn’t have the keyboard’s layout."))
            case .buttonOnly: EmptyView()
            }
        case let .reading(fraction):
            VStack(alignment: .leading, spacing: 4) {
                line(Text("Reading the layout from the keyboard…"))
                ProgressView(value: min(max(fraction, 0), 1)).progressViewStyle(.linear).controlSize(.small)
                    .accessibilityLabel(Text("Reading the layout from the keyboard, \(Int((fraction * 100).rounded())) percent"))
            }
        case .noRecord:
            line(Text(KeyboardLayoutPrompt.noRecordText))
        case let .found(title):
            line(Text("Runs ‘\(title)’ from another Mac"))
        case let .failed(reason):
            Label {
                line(Text(verbatim: reason))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tokens.warning.color).font(font)
            }
        }
    }

    /// The prompt's own button; none while reading or for firmware that stores no layout.
    @ViewBuilder private var action: some View {
        switch prompt {
        case .notInLibrary: Button("Get Layout", action: getLayout).help(getLayoutHelp)
        case .found: Button("Add to Library…", action: addToLibrary)
        case .failed: Button("Try Again", action: getLayout)
        case .reading, .noRecord: EmptyView()
        }
    }

    private var getLayoutHelp: Text {
        if isLive { return Text("Reads the layout Sextant stored in the keyboard’s firmware") }
        return Text("Turns on Live View and reads the layout Sextant stored in the keyboard’s firmware")
    }

    private var hasButtons: Bool {
        switch prompt {
        case .notInLibrary, .found, .failed: true
        case .reading, .noRecord: importFromOryx != nil
        }
    }

    private func line(_ text: Text) -> some View {
        text.font(font).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

extension OpenWindowAction {
    /// The Layout on the Keyboard window (ADR 0061), with the Dock icon back first when Sextant is only in the menu bar.
    @MainActor func keyboardLayout(_ windows: WindowRouter?) {
        guard let windows else { return self(id: KeyboardLayoutWindow.sceneID) }
        windows.showWindow { self(id: KeyboardLayoutWindow.sceneID) }
    }
}
