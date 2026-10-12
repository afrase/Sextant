import SwiftUI

/// Motion tokens (spec §10.6). Each one has a short ease, or nothing, under Reduce Motion.
struct SextantMotion {
    var reduceMotion: Bool

    /// The selection ring moving between keys: a snappy spring, instant under Reduce Motion.
    var selection: Animation? { reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86) }
    /// Lens-lane capsules appearing and leaving.
    var standard: Animation { reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.82) }
    /// Caps crossfading on a layer change (the same with Reduce Motion). Ease-out, so the first frames after a click
    /// already show the new layer: ease-in-out moved the board 7% in its first 33 ms.
    static let layerChange = Animation.easeOut(duration: 0.18)
    /// The layer atmosphere on the bench.
    static let atmosphere = Animation.linear(duration: 0.3)
    /// A live key fading back after release; presses light instantly.
    static let keyRelease = Animation.easeOut(duration: 0.12)
}

extension EnvironmentValues {
    var motion: SextantMotion { SextantMotion(reduceMotion: accessibilityReduceMotion) }
}
