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
    /// A fresh Import from Oryx flow (one per sheet).
    public let makeImport: @MainActor () -> ImportFromOryx
    /// The Build & Flash state machine for one open layout.
    public let makeBuildFlash: @MainActor (EditSession) -> BuildFlashSession

    public init(
        library: Library, live: LiveSession, trace: RawHIDTrace, onKeyboard: OnKeyboard,
        makeImport: @escaping @MainActor () -> ImportFromOryx, makeBuildFlash: @escaping @MainActor (EditSession) -> BuildFlashSession
    ) {
        self.library = library
        self.live = live
        self.trace = trace
        self.onKeyboard = onKeyboard
        self.makeImport = makeImport
        self.makeBuildFlash = makeBuildFlash
    }
}
