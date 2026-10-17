import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// Sextant ▸ Check for Updates… and the menu bar's Details… (ADR 0063): what the last check found, and what to do about
/// it. It only tells: the user downloads the zip, or runs Homebrew, themselves.
public struct SoftwareUpdateWindow: View {
    static let sceneID = "software-update"

    @Bindable var updates: UpdateChecker
    /// Homebrew installed Sextant, so it updates with `brew upgrade` rather than a download.
    var installedWithHomebrew: Bool
    @Environment(\.openURL) private var openURL

    public init(updates: UpdateChecker, installedWithHomebrew: Bool) {
        self.updates = updates
        self.installedWithHomebrew = installedWithHomebrew
    }

    static let brewCommand = "brew upgrade --cask sextant"

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    if let detail { Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if case .checking = updates.status { ProgressView().controlSize(.small).accessibilityLabel(Text("Checking")) }
                }
            }
            if let release = updates.available, installedWithHomebrew { homebrew(release) }
            HStack {
                // Skip This Version stops the menu bar's notice until a newer release is out.
                if updates.notice != nil { Button("Skip This Version") { updates.dismiss() } }
                Spacer()
                buttons
            }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                Spacer()
                if let last = updates.saved.lastChecked {
                    // Redrawn each minute, so "3 hours ago" stays true while the window is open.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("Last checked \(last.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
                            .font(.caption).foregroundStyle(.secondary).id(context.date)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var title: String {
        switch updates.status {
        case .idle: String(localized: "Check for Updates")
        case .checking: String(localized: "Checking for updates…")
        case .upToDate: String(localized: "Sextant is up to date")
        case let .available(release): String(localized: "Sextant \(release.version.description) is available")
        case .failed: String(localized: "Sextant couldn’t check for updates")
        case let .unknownVersion(release): String(localized: "The newest Sextant is \(release.version.description)")
        }
    }

    private var detail: String? {
        let current = updates.current?.description
        switch updates.status {
        case .idle: return String(localized: "Sextant asks GitHub for its newest release. Nothing is downloaded or installed.")
        case .checking: return nil
        case .upToDate: return current.map { String(localized: "\($0) is the newest version.") }
        case .available:
            return current.map { String(localized: "You have \($0). The release notes say what’s new.") }
        case let .failed(error): return error.localizedDescription
        case .unknownVersion: return String(localized: "This build doesn’t say its version, so Sextant can’t compare.")
        }
    }

    @ViewBuilder private var buttons: some View {
        switch updates.status {
        case .checking: Button("Check Now") {}.disabled(true)
        case let .available(release), let .unknownVersion(release):
            Button("Release Notes") { openURL(release.page) }
            if !installedWithHomebrew, case .available = updates.status, let download = release.download {
                Button("Download") { openURL(download) }.keyboardShortcut(.defaultAction)
            }
        case .idle, .upToDate, .failed:
            Button(updates.status == .idle ? "Check Now" : "Check Again") { Task { await updates.check() } }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// The Homebrew command, to copy into Terminal.
    private func homebrew(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Homebrew installed Sextant. To update, run:").font(.callout)
            HStack {
                Text(verbatim: Self.brewCommand).font(.callout.monospaced()).textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.brewCommand, forType: .string)
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.5)))
        }
    }
}

/// Settings › General's update choices (ADR 0063), kept in UserDefaults; the composition root reads them at launch and
/// ``UpdateChecker`` saves through ``save(_:in:)``.
public enum UpdateSettings {
    static let checksAutomatically = "checksForUpdates"
    static let lastChecked = "updatesLastChecked"
    static let dismissed = "updatesDismissedVersion"
    /// The newer release the last answer named, as JSON.
    static let found = "updatesFoundRelease"

    /// On by default (the user's choice, 2026-10-17).
    public static func saved(in defaults: UserDefaults = .standard) -> UpdateChecker.Saved {
        UpdateChecker.Saved(
            checksAutomatically: defaults.object(forKey: checksAutomatically) as? Bool ?? true,
            lastChecked: defaults.object(forKey: lastChecked) as? Date,
            dismissed: defaults.string(forKey: dismissed).flatMap(AppVersion.init),
            found: defaults.data(forKey: found).flatMap { try? JSONDecoder().decode(AppRelease.self, from: $0) })
    }

    public static func save(_ saved: UpdateChecker.Saved, in defaults: UserDefaults = .standard) {
        defaults.set(saved.checksAutomatically, forKey: checksAutomatically)
        defaults.set(saved.lastChecked, forKey: lastChecked)
        defaults.set(saved.dismissed?.description, forKey: dismissed)
        defaults.set(saved.found.flatMap { try? JSONEncoder().encode($0) }, forKey: found)
    }

    /// Whether Homebrew's cask installed this copy: the cask's Caskroom folder exists (Apple silicon or Intel) and Sextant
    /// runs from /Applications, where the cask puts it, not from a build folder.
    public static func installedWithHomebrew(
        bundlePath: String = Bundle.main.bundlePath, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        bundlePath == "/Applications/Sextant.app"
            && ["/opt/homebrew/Caskroom/sextant", "/usr/local/Caskroom/sextant"].contains(where: fileExists)
    }
}

/// Sextant ▸ Check for Updates…, named for the version once one is found. A view, so the menu follows the checker:
/// a `Commands` body reading it directly may not.
struct UpdateMenuItem: View {
    var updates: UpdateChecker
    var windows: WindowRouter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(
            updates.notice.map { String(localized: "Update to Sextant \($0.version.description)…") }
                ?? String(localized: "Check for Updates…")
        ) {
            windows.showWindow { openWindow(id: SoftwareUpdateWindow.sceneID) }
            if updates.notice == nil { Task { await updates.check() } }
        }
    }
}

/// Settings › General's Updates section.
struct UpdatesSection: View {
    @Bindable var updates: UpdateChecker
    var openWindow: @MainActor () -> Void

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
            LabeledContent {
                Button("Check Now") {
                    openWindow()
                    Task { await updates.check() }
                }
                .disabled(updates.status == .checking)
            } label: {
                Text(status)
            }
        } header: {
            Text("Updates")
        } footer: {
            Group {
                if updates.checksAutomatically {
                    Text(
                        """
                        Once a day, Sextant asks GitHub for its newest release and tells you when there is one. GitHub sees \
                        your IP address and Sextant’s version. Nothing is downloaded or installed by itself.
                        """)
                } else {
                    Text("Sextant asks GitHub for its newest release only when you check. Nothing is downloaded or installed by itself.")
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        switch updates.status {
        case let .available(release): String(localized: "Sextant \(release.version.description) is available.")
        case .upToDate: String(localized: "Sextant is up to date.")
        case .checking: String(localized: "Checking…")
        case .failed: String(localized: "The last check didn’t get an answer.")
        case .idle, .unknownVersion:
            updates.current.map { String(localized: "This is Sextant \($0.description).") }
                ?? String(localized: "This build doesn’t say its version.")
        }
    }
}
