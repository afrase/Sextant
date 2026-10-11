import SextantApplication

/// The use cases the UI may call, built by the composition root. The UI never sees an adapter (CLAUDE.md).
@MainActor
public struct SextantServices {
    public let library: Library
    /// App-wide keyboard presence and live state.
    public let live: LiveSession
    /// A fresh Import from Oryx flow (one per sheet).
    public let makeImport: @MainActor () -> ImportFromOryx
    /// The Build & Flash state machine for one open layout.
    public let makeBuildFlash: @MainActor (EditSession) -> BuildFlashSession

    public init(
        library: Library, live: LiveSession, makeImport: @escaping @MainActor () -> ImportFromOryx,
        makeBuildFlash: @escaping @MainActor (EditSession) -> BuildFlashSession
    ) {
        self.library = library
        self.live = live
        self.makeImport = makeImport
        self.makeBuildFlash = makeBuildFlash
    }
}
