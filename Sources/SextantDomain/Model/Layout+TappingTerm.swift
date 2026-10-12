import Foundation

extension Key {
    /// True when QMK's tapping term times this key: it has a hold, a double tap or a tap then hold. Read from the slots,
    /// not ``kind``, which a label or macro overrides.
    public var usesTappingTerm: Bool { hold != nil || doubleTap != nil || tapHold != nil }

    /// True when both keys do the same thing in every slot. QMK looks tapping terms up by keycode, so such keys share one.
    func hasSameActions(as other: Key) -> Bool {
        tap == other.tap && hold == other.hold && doubleTap == other.doubleTap && tapHold == other.tapHold
    }
}

extension KeyboardLayout {
    /// The range the generator accepts for a key's own term, in ms.
    public static let tappingTermRange = 0...1000

    /// The layout's tapping term in ms, read as the generator reads it for `TAPPING_TERM`.
    public var globalTappingTerm: Int { settingValue("tappingTerm")?.doubleValue.flatMap { Int(exactly: $0.rounded()) } ?? 200 }

    /// Keys' own terms reach the firmware only while this setting is on.
    public var perKeyTappingTermsOn: Bool { settingValue("perKeyTappingTerm")?.boolValue == true }

    /// Sets a key's own tapping term, nil for the global one, on it and on every key with the same actions. A term is
    /// kept within ``tappingTermRange``, and one equal to the global term is stored as nil, as Oryx does.
    public mutating func setTappingTerm(_ term: Int?, layer: Int, index: Int) {
        guard let key = key(layer: layer, index: index) else { return }
        let bounded = term.map { min(max($0, Self.tappingTermRange.lowerBound), Self.tappingTermRange.upperBound) }
        let stored = bounded == globalTappingTerm ? nil : bounded
        for li in layers.indices {
            for ki in layers[li].keys.indices where layers[li].keys[ki].hasSameActions(as: key) { layers[li].keys[ki].tappingTerm = stored }
        }
    }
}
