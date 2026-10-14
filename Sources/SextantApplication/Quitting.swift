import Foundation

/// What a quit waits for (spec §7.4): a firmware write and its verify, which can't be stopped, and every open document's
/// pending autosave (each lands up to a second after the last edit). The app delegate replies when ``run(quitAnyway:)``
/// returns.
@MainActor
public struct Quitting {
    /// Writes every open document's pending edit; false when one couldn't be saved.
    let flush: @MainActor () async -> Bool
    let isWriting: @MainActor () -> Bool
    /// One step of a wait for a write: 200 ms in the app.
    let pause: @MainActor () async -> Void

    /// Rounds of waiting and flushing after the first flush. Each round's wait ends a write that started while the flush
    /// before it awaited the disk (another window's run, waiting for flash mode); a few rounds bound the quit, and the
    /// wait after the last one still cuts no write off.
    static let rounds = 3

    public init(library: Library, live: LiveSession?) {
        self.init(flush: { await library.flushOpenSessions() }, isWriting: { live?.isWritingFirmware == true }) {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    init(
        flush: @escaping @MainActor () async -> Bool, isWriting: @escaping @MainActor () -> Bool,
        pause: @escaping @MainActor () async -> Void
    ) {
        self.flush = flush
        self.isWriting = isWriting
        self.pause = pause
    }

    /// True to quit now. Waits for a write, writes every pending edit, and asks `quitAnyway` when one couldn't be saved.
    /// A run waiting for flash mode may start writing while a flush awaits the disk; edits made during that write would
    /// wait for an autosave, so a round that waited for one flushes again. It ends on a wait, so no write starts between
    /// it and the reply, which nothing awaits.
    public func run(quitAnyway: @MainActor () -> Bool) async -> Bool {
        await waitForWrite()
        var asked = false
        if await !flush() {
            guard quitAnyway() else { return false }
            asked = true
        }
        for _ in 0..<Self.rounds {
            guard await waitForWrite() else { return true }
            if await !flush(), !asked {
                guard quitAnyway() else { return false }
                asked = true
            }
        }
        await waitForWrite()
        return true
    }

    /// Waits while the keyboard is being written or verified; true when it was. A cut-off write leaves the keyboard in
    /// flash mode, and a cut-off verify loses the record of what was flashed. The flasher's capped polling and timeouts,
    /// and the 10 s verify timeout, bound the wait.
    @discardableResult
    private func waitForWrite() async -> Bool {
        var waited = false
        while isWriting() {
            waited = true
            await pause()
        }
        return waited
    }
}
