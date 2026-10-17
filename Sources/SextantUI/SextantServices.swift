import SextantApplication

/// The use cases the UI may call, built by the composition root. The UI never sees an adapter (AGENTS.md).
@MainActor
public struct SextantServices {
    public let library: Library
    /// App-wide keyboard presence and live state.
    public let live: LiveSession
    /// The Developer raw-HID log the live link feeds (ADR 0045).
    public let trace: RawHIDTrace
    /// Which library layout the keyboard runs, app-wide.
    public let onKeyboard: OnKeyboard
    /// The global layer shortcuts, app-wide (ADR 0048).
    public let layerShortcuts: LayerShortcuts
    /// The keyboard lighting preview, app-wide: one window at a time (ADR 0051).
    public let lightingPreview: LightingPreview
    /// The overlay HUD, app-wide (ADR 0050).
    public let overlay: OverlayHUD
    /// Heatmap recording, app-wide (ADR 0053).
    public let heatmap: HeatmapRecorder
    /// App Layers, app-wide (ADR 0054).
    public let appLayers: AppLayerSwitcher
    /// Reads the layout a Sextant build stores in the keyboard when the library doesn't have it, app-wide (ADR 0061).
    public let keyboardLayout: KeyboardLayoutPull
    /// Tells the user when a newer Sextant is out, app-wide (ADR 0063).
    public let updates: UpdateChecker
    /// Homebrew installed Sextant, so an update is `brew upgrade` rather than a download.
    public let installedWithHomebrew: Bool
    /// A fresh Import from Oryx flow (one per sheet).
    public let makeImport: @MainActor () -> ImportFromOryx
    /// The Build & Flash state machine for one open layout.
    public let makeBuildFlash: @MainActor (EditSession) -> BuildFlashSession

    public init(
        library: Library, live: LiveSession, trace: RawHIDTrace, onKeyboard: OnKeyboard, layerShortcuts: LayerShortcuts,
        lightingPreview: LightingPreview, overlay: OverlayHUD, heatmap: HeatmapRecorder, appLayers: AppLayerSwitcher,
        keyboardLayout: KeyboardLayoutPull, updates: UpdateChecker, installedWithHomebrew: Bool,
        makeImport: @escaping @MainActor () -> ImportFromOryx,
        makeBuildFlash: @escaping @MainActor (EditSession) -> BuildFlashSession
    ) {
        self.library = library
        self.live = live
        self.trace = trace
        self.onKeyboard = onKeyboard
        self.layerShortcuts = layerShortcuts
        self.lightingPreview = lightingPreview
        self.overlay = overlay
        self.heatmap = heatmap
        self.appLayers = appLayers
        self.keyboardLayout = keyboardLayout
        self.updates = updates
        self.installedWithHomebrew = installedWithHomebrew
        self.makeImport = makeImport
        self.makeBuildFlash = makeBuildFlash
    }
}
