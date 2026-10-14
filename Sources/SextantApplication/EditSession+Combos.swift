import Foundation
import SextantDomain

/// Combo edits (spec §6.4, ADR 0046). Each is one named undo step that selects the combo it changed, so undo and redo
/// bring the inspector back to it.
extension EditSession {
    /// The selected combo, while the layout still has it.
    public var selectedCombo: Combo? { selection.combo.flatMap { layout.combo(id: $0) } }

    public func selectCombo(_ id: String?) { selection.combo = id }

    /// Makes a combo from keys chosen on the board and its output, and selects it. `layer` is where it reads its keys.
    @discardableResult
    public func newCombo(keys: [Int], layer: Int?, output: KeyAction) -> String {
        let id = UUID().uuidString
        edit(String(localized: "New Combo"), select: { $0.combo = id }) { doc in
            doc.addCombo(Combo(id: id, keyIndices: [], layer: layer, output: output))
            doc.setComboKeys(keys, in: id)
        }
        return id
    }

    public func deleteCombo(_ id: String) {
        edit(String(localized: "Delete Combo"), select: { if $0.combo == id { $0.combo = nil } }) { $0.removeCombo(id: id) }
    }

    public func toggleComboKey(_ index: Int, in id: String) {
        edit(String(localized: "Change Combo Keys"), select: { $0.combo = id }) { $0.toggleComboKey(index, in: id) }
    }

    public func setComboKeys(_ keys: [Int], in id: String) {
        edit(String(localized: "Change Combo Keys"), select: { $0.combo = id }) { $0.setComboKeys(keys, in: id) }
    }

    public func setComboOutput(_ output: KeyAction, in id: String) {
        edit(String(localized: "Set Combo Output"), select: { $0.combo = id }) { $0.setComboOutput(output, in: id) }
    }

    /// The layer the combo reads its keys from (ADR 0046); nil is the base layer.
    public func setComboLayer(_ layer: Int?, in id: String) {
        edit(String(localized: "Change Combo Layer"), select: { $0.combo = id }) { $0.setComboLayer(layer, in: id) }
    }

    public func renameCombo(_ id: String, to name: String) {
        edit(String(localized: "Rename Combo"), select: { $0.combo = id }) { $0.renameCombo(id: id, to: name) }
    }
}
