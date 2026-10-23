import Observation
import SextantDomain

/// The Lighting lens's window state (spec §6.2): the brush, and the layer confirmations and sheet its inspector and
/// menus open. Painting itself is an `EditSession` edit; the window's `brush` says when this brush is live.
@MainActor
@Observable
final class LightingModel {
    /// The brush colour; `isErasing` paints no colour of their own instead.
    var brushColor = KeyboardLayout.defaultSwatch.first ?? HexColor(red: 1, green: 0.58, blue: 0)
    var isErasing = false
    /// A layer waiting for Clear Key Colours' confirmation.
    var keyColoursPendingClear: Int?
    /// The layer whose Custom… colour sheet is open.
    var layerPendingColour: Int?

    /// What a stroke gives the keys it crosses: the colour, or (the eraser) none of their own.
    var brush: Brush { Brush(color: isErasing ? nil : brushColor) }

    /// Picking a colour puts the eraser down.
    func pickBrush(_ color: HexColor) {
        brushColor = color
        isErasing = false
    }
}
