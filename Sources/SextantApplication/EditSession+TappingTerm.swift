import Foundation
import SextantDomain

extension EditSession {
    /// Sets a key's own tapping term, nil for the global one (``KeyboardLayout/setTappingTerm(_:layer:index:)``). A custom
    /// term also turns per-key terms on in the same undo step, since the firmware ignores it otherwise.
    public func setTappingTerm(_ term: Int?, layer: Int? = nil, index: Int? = nil) {
        guard let (l, i) = target(layer, index) else { return }
        edit(String(localized: "Set Tapping Term")) { doc in
            doc.setTappingTerm(term, layer: l, index: i)
            if doc.key(layer: l, index: i)?.tappingTerm != nil { doc.settings["perKeyTappingTerm"] = .bool(true) }
        }
    }
}
