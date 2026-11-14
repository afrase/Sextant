import AppKit
import SextantApplication
import SextantDomain
import SwiftUI

/// Where Settings › Navigator's values are kept: JSON in the app's defaults. The composition root reads them at launch
/// and hands the driver `save`.
public enum NavigatorSettingsStore {
    public static func saved() -> TrackpadSettings {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.navigatorTrackpad) else { return TrackpadSettings() }
        // A file that isn't JSON at all reads as the defaults: off, so nothing is switched without the user.
        return (try? JSONDecoder().decode(TrackpadSettings.self, from: data)) ?? TrackpadSettings()
    }

    @MainActor public static func save(_ settings: TrackpadSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKey.navigatorTrackpad)
    }
}

/// Settings › Navigator (ADR 0068): the switch that lets Sextant drive the Navigator trackpad, what it still needs, and
/// every tuning value in units people know. Values that macOS has its own setting for follow it unless overridden.
public struct NavigatorSettings: View {
    var driver: TrackpadDriver

    public init(driver: TrackpadDriver) { self.driver = driver }

    public var body: some View {
        Form {
            Section {
                Toggle(
                    "Use Sextant for the Navigator trackpad",
                    isOn: Binding(get: { driver.settings.isEnabled }, set: { on in Task { await driver.setEnabled(on) } }))
                NavigatorStatusRow(driver: driver)
            } footer: {
                Text(
                    """
                    Sextant switches the trackpad to touchpad mode and turns your touches into pointer moves, clicks and \
                    scrolling. Quit ZSA’s Navigator app while it does. Turning this off, or quitting Sextant, gives the \
                    trackpad back its own mouse mode.
                    """
                )
                .foregroundStyle(.secondary)
            }
            Group {
                PointerSection(driver: driver)
                ScrollingSection(driver: driver)
                TappingSection(driver: driver)
                DraggingSection(driver: driver)
                Section {
                    Button("Reset to Defaults") { driver.resetToDefaults() }
                }
            }
            .disabled(!driver.settings.isEnabled)
        }
        .formStyle(.grouped)
        .task { await driver.refresh() }
    }
}

/// What the driver is doing. While a permission is missing, both permissions show with what each is for, whether it's
/// granted, and a button that asks macOS and opens its pane; Reset Permissions clears stale grants and asks afresh.
private struct NavigatorStatusRow: View {
    var driver: TrackpadDriver

    private var needsPermission: Bool {
        driver.status == .needsInputMonitoring || driver.status == .needsAccessibility
    }

    var body: some View {
        Group {
            switch driver.status {
            case .off:
                EmptyView()
            case .needsInputMonitoring, .needsAccessibility:
                permission(
                    "Input Monitoring", detail: "Lets Sextant read your touches.", granted: driver.hasInputMonitoring,
                    pane: "Privacy_ListenEvent")
                permission(
                    "Accessibility", detail: "Lets Sextant move the pointer, click and scroll.", granted: driver.hasAccessibility,
                    pane: "Privacy_Accessibility")
                LabeledContent {
                    Button("Reset Permissions") { Task { await driver.resetPermissions() } }
                } label: {
                    Text("Sextant missing from the list, or on there but not here? Reset reopens Sextant and asks again.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .waitingForTrackpad:
                Label("Waiting for a Navigator trackpad", systemImage: "cable.connector").foregroundStyle(.secondary)
            case .running:
                Label("Driving the Navigator trackpad", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            case let .failed(error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            }
        }
        // While a permission is missing, checks again every second, so flipping the switch in System Settings is the
        // last step: the rows clear by themselves.
        .task(id: needsPermission) {
            while needsPermission, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await driver.refresh()
            }
        }
    }

    private func permission(_ name: LocalizedStringKey, detail: LocalizedStringKey, granted: Bool, pane: String) -> some View {
        LabeledContent {
            if granted {
                Text("Allowed").foregroundStyle(.secondary)
            } else {
                Button("Allow…") {
                    Task {
                        // Asking first lists Sextant in that pane, so there's a switch to turn on.
                        await driver.requestPermissions()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? .green : .orange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(granted ? Text("Allowed") : Text("Not allowed"))
        }
    }
}

private struct PointerSection: View {
    var driver: TrackpadDriver
    @State private var showsAdvanced = false

    var body: some View {
        let pointer = driver.settings.pointer
        Section {
            Toggle(
                "Match the Mac’s tracking speed",
                isOn: Binding(
                    get: { pointer.trackingSpeed == nil },
                    set: { follows in driver.update { $0.pointer.trackingSpeed = follows ? nil : 1 } }))
            if let speed = pointer.trackingSpeed {
                ValueSlider(
                    title: "Tracking speed", value: speed, range: TrackpadSettings.Pointer.trackingSpeedRange, step: 0.0625,
                    low: "Slow", high: "Fast", digits: 2
                ) { value in driver.update { $0.pointer.trackingSpeed = value } }
            } else {
                LabeledContent("Tracking speed") {
                    Text(driver.systemPreferences.trackingSpeed.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ValueSlider(
                title: "Pad rotation", value: driver.settings.rotation, range: TrackpadSettings.rotationRange, step: 1,
                low: "−180°", high: "180°", digits: 0, unit: "°"
            ) { value in driver.update { $0.rotation = value } }
            ValueSlider(
                title: "Fast moves", value: pointer.fastMoves, range: TrackpadSettings.Pointer.fastMovesRange, step: 0.05,
                low: "Gentler", high: "Mac", digits: 0, unit: "%", scale: 100
            ) { value in driver.update { $0.pointer.fastMoves = value } }
            DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                ValueSlider(
                    title: "Fast moves start at", value: pointer.fastMoveThreshold,
                    range: TrackpadSettings.Pointer.fastMoveThresholdRange, step: 10, low: "Sooner", high: "Later",
                    digits: 0, unit: String(localized: "mm/s")
                ) { value in driver.update { $0.pointer.fastMoveThreshold = value } }
                ValueSlider(
                    title: "Pad scale", value: pointer.padScale, range: TrackpadSettings.Pointer.padScaleRange, step: 0.05,
                    low: "Smaller", high: "Larger", digits: 2, unit: "×"
                ) { value in driver.update { $0.pointer.padScale = value } }
                Toggle(
                    "Ignore the fingertip rolling off",
                    isOn: Binding(get: { pointer.filtersLiftOff }, set: { on in driver.update { $0.pointer.filtersLiftOff = on } }))
            }
        } header: {
            Text("Pointer")
        } footer: {
            Text(
                """
                If the pointer moves at an angle to your finger, turn Pad rotation until straight up on the pad is \
                straight up on screen; it applies to scrolling too. \
                The pointer follows macOS’s own trackpad acceleration. The Navigator is small, so it starts one step \
                faster than the Mac’s default. Lower Fast moves if long moves overshoot.
                """
            )
            .foregroundStyle(.secondary)
        }
    }
}

private struct ScrollingSection: View {
    var driver: TrackpadDriver

    var body: some View {
        let scrolling = driver.settings.scrolling
        Section {
            ValueSlider(
                title: "Scroll speed", value: scrolling.speed, range: TrackpadSettings.Scrolling.speedRange, step: 0.05, low: "Slow",
                high: "Fast", digits: 2, unit: "×"
            ) { value in driver.update { $0.scrolling.speed = value } }
            Toggle(
                "Invert horizontal scrolling",
                isOn: Binding(get: { scrolling.invertsHorizontal }, set: { on in driver.update { $0.scrolling.invertsHorizontal = on } }))
            Toggle(
                "Invert vertical scrolling",
                isOn: Binding(get: { scrolling.invertsVertical }, set: { on in driver.update { $0.scrolling.invertsVertical = on } }))
            Toggle(
                "Keep scrolling after you lift your fingers",
                isOn: Binding(get: { scrolling.hasMomentum }, set: { on in driver.update { $0.scrolling.hasMomentum = on } }))
            if scrolling.hasMomentum {
                ValueSlider(
                    title: "Glide", value: scrolling.momentumHalfLife, range: TrackpadSettings.Scrolling.momentumHalfLifeRange, step: 10,
                    low: "Short", high: "Long", digits: 0, unit: String(localized: "ms")
                ) { value in driver.update { $0.scrolling.momentumHalfLife = value } }
            }
        } header: {
            Text("Scrolling")
        } footer: {
            Text(
                """
                Scroll with two fingers. The direction follows System Settings’ natural scrolling; inverting flips \
                one direction from that. Glide is how long scrolling takes to lose half its speed.
                """
            )
            .foregroundStyle(.secondary)
        }
    }
}

private struct TappingSection: View {
    var driver: TrackpadDriver

    var body: some View {
        let tapping = driver.settings.tapping
        Section {
            Toggle("Tap to click", isOn: Binding(get: { tapping.tapToClick }, set: { on in driver.update { $0.tapping.tapToClick = on } }))
            Toggle(
                "Tap with two fingers to right-click",
                isOn: Binding(
                    get: { tapping.twoFingerRightClick }, set: { on in driver.update { $0.tapping.twoFingerRightClick = on } }))
            Group {
                ValueSlider(
                    title: "Longest tap", value: tapping.longestTap, range: TrackpadSettings.Tapping.longestTapRange, step: 10,
                    low: "Quick", high: "Slow", digits: 0, unit: String(localized: "ms")
                ) { value in driver.update { $0.tapping.longestTap = value } }
                ValueSlider(
                    title: "Movement in a tap", value: tapping.tapMovement, range: TrackpadSettings.Tapping.tapMovementRange, step: 0.1,
                    low: "Strict", high: "Relaxed",
                    digits: 1, unit: String(localized: "mm")
                ) { value in driver.update { $0.tapping.tapMovement = value } }
                Toggle(
                    "Match the Mac’s double-click speed",
                    isOn: Binding(
                        get: { tapping.doubleClickInterval == nil },
                        set: { follows in driver.update { $0.tapping.doubleClickInterval = follows ? nil : 0.5 } }))
                if let interval = tapping.doubleClickInterval {
                    ValueSlider(
                        title: "Double-click speed", value: interval, range: TrackpadSettings.Tapping.doubleClickIntervalRange, step: 0.05,
                        low: "Fast", high: "Slow", digits: 2, unit: String(localized: "s")
                    ) { value in driver.update { $0.tapping.doubleClickInterval = value } }
                }
            }
            .disabled(!tapping.tapToClick)
        } header: {
            Text("Tapping")
        } footer: {
            Text("The trackpad has no button to press: a short, still touch is a click.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DraggingSection: View {
    var driver: TrackpadDriver

    var body: some View {
        let dragging = driver.settings.dragging
        Section {
            Toggle(
                "Tap, then touch and move to drag",
                isOn: Binding(get: { dragging.tapThenDrag }, set: { on in driver.update { $0.dragging.tapThenDrag = on } }))
            Group {
                ValueSlider(
                    title: "Touch again within", value: dragging.window, range: TrackpadSettings.Dragging.windowRange, step: 10,
                    low: "Quick", high: "Slow", digits: 0, unit: String(localized: "ms")
                ) { value in driver.update { $0.dragging.window = value } }
                ValueSlider(
                    title: "And within", value: dragging.radius, range: TrackpadSettings.Dragging.radiusRange, step: 0.5, low: "Strict",
                    high: "Relaxed", digits: 1, unit: String(localized: "mm")
                ) { value in driver.update { $0.dragging.radius = value } }
                Toggle(
                    "Keep dragging briefly after you lift",
                    isOn: Binding(
                        get: { dragging.regrip != nil },
                        set: { on in driver.update { $0.dragging.regrip = on ? TrackpadSettings.Dragging.defaultRegrip : nil } }))
                if let regrip = dragging.regrip {
                    ValueSlider(
                        title: "For", value: regrip, range: TrackpadSettings.Dragging.regripRange, step: 0.05, low: "Short", high: "Long",
                        digits: 2, unit: String(localized: "s")
                    ) { value in driver.update { $0.dragging.regrip = value } }
                }
            }
            .disabled(!dragging.tapThenDrag)
        } header: {
            Text("Dragging")
        } footer: {
            Text(
                """
                A drag starts only when the second touch lands where you tapped, so lifting your finger to \
                reposition never drags. For the steadiest drags, put Left Click on a key and hold it while you move.
                """
            )
            .foregroundStyle(.secondary)
        }
    }
}

/// A slider over a Double with a field beside it to type an exact value into, ends labeled. A typed value is held to
/// the range and rounded to the digits shown, but not to the slider's steps.
struct ValueSlider: View {
    var title: LocalizedStringKey
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var low: LocalizedStringKey
    var high: LocalizedStringKey
    /// Decimal places the field shows.
    var digits: Int
    var unit: String = ""
    /// What the field shows is the value times this: 100 for a share shown as a percentage.
    var scale: Double = 1
    var set: (Double) -> Void

    private var spoken: String {
        let number = NumberField.text(value * scale, digits: digits)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Slider(
                    value: Binding(get: { value }, set: { set(($0 / step).rounded() * step) }), in: range,
                    label: { Text(title) }, minimumValueLabel: { Text(low).font(.caption) },
                    maximumValueLabel: { Text(high).font(.caption) }
                )
                .labelsHidden()
                .accessibilityValue(Text(verbatim: spoken))
                NumberField(
                    title: title, value: value * scale, range: (range.lowerBound * scale)...(range.upperBound * scale), digits: digits
                ) { set($0 / scale) }
                .accessibilityValue(Text(verbatim: spoken))
                Text(verbatim: unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading).accessibilityHidden(true)
            }
        }
    }
}

/// A field for typing a number. It keeps its own text while being edited and commits on Return, on losing focus and
/// when it goes away (a popover closing), but only text the user changed; afterwards it shows what was stored, so a
/// value out of range reads back as the limit it was held to.
struct NumberField: View {
    var title: LocalizedStringKey
    var value: Double
    var range: ClosedRange<Double>
    var digits: Int
    var set: (Double) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    nonisolated static func text(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    /// The number in `text`, held to `range` and rounded to `digits`; nil when it isn't a number. Reads the user's
    /// decimal separator, and a plain period too.
    nonisolated static func parse(_ text: String, range: ClosedRange<Double>, digits: Int) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "−", with: "-")
        guard let typed = (try? Double(trimmed, format: .number)) ?? Double(trimmed), typed.isFinite else { return nil }
        let factor = pow(10, Double(digits))
        return min(max((typed * factor).rounded() / factor, range.lowerBound), range.upperBound)
    }

    private var shown: String { Self.text(value, digits: digits) }

    var body: some View {
        TextField(title, text: $text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 58)
            .focused($isFocused)
            .accessibilityLabel(Text(title))
            .onAppear { text = shown }
            .onChange(of: value) { if !isFocused { text = shown } }
            .onChange(of: isFocused) { if !isFocused { commit() } }
            .onSubmit(commit)
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard text != shown else { return }
        guard let parsed = Self.parse(text, range: range, digits: digits) else {
            text = shown  // not a number: back to what is stored
            return
        }
        set(parsed)
        // What was stored, which may be the limit the typed number was held to.
        text = Self.text(parsed, digits: digits)
    }
}
