import Foundation
import Observation
import SextantApplication
import SextantDomain

/// Presentation state for one layout window. It owns the open `EditSession` and asks `Library` for layouts.
@MainActor
@Observable
public final class LayoutWindowModel {
    public let library: Library
    /// The open layout, once loaded.
    public private(set) var session: EditSession?
    public var legendMode: LegendMode = .symbols
    public private(set) var loadError: LibraryError?

    public init(library: Library) {
        self.library = library
    }

    /// Opens `id`, or the most recently modified layout when `id` is nil or no longer in the library (a stale
    /// restored window). Leaves `session` nil for an empty library. Returns the id actually opened.
    @discardableResult
    public func open(_ id: UUID?) async -> UUID? {
        await library.refresh()
        let known = library.entries.map(\.id)
        guard let target = id.flatMap({ known.contains($0) ? $0 : nil }) ?? known.first else { return nil }
        guard target != session?.id else { return target }
        do {
            let next = try await library.open(target)
            if let old = session {
                await old.flush()
                // Undo steps point at the old session; drop them so ⌘Z can't reach a released document.
                old.undoManager?.removeAllActions(withTarget: old)
            }
            session = next
            loadError = nil
            return target
        } catch {
            loadError = error
            return nil
        }
    }
}
