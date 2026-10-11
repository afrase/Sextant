import SextantDomain
import Testing

@testable import SextantUI

/// Spec §10.1 / §11: legend and band text at least 4.5:1, signal bars at least 3:1 on the cap, in light and dark.
struct TokenContrastTests {
    enum Mode: CaseIterable { case light, dark }

    /// The token as drawn over `background` (alpha-blended).
    func resolve(_ token: Token, _ mode: Mode, over background: HexColor) -> HexColor {
        let (c, a) = mode == .dark ? (token.dark, token.darkAlpha) : (token.light, token.lightAlpha)
        return HexColor(
            red: c.red * a + background.red * (1 - a), green: c.green * a + background.green * (1 - a),
            blue: c.blue * a + background.blue * (1 - a))
    }

    func cap(_ mode: Mode) -> HexColor { mode == .dark ? Tokens.capTop.dark : Tokens.capTop.light }

    @Test(arguments: Mode.allCases)
    func legendsReadOnCaps(mode: Mode) {
        for token in [Tokens.capLegend, Tokens.capLegend2] {
            #expect(resolve(token, mode, over: cap(mode)).contrast(with: cap(mode)) >= 4.5)
        }
    }

    @Test(arguments: Mode.allCases)
    func bandInkAndSignalBars(mode: Mode) {
        // Disabled keys draw a hatch, never a band or a bar, so their token isn't checked here.
        let kinds = KeyKind.allCases.filter { $0 != .disabled }.compactMap(Tokens.kind) + [Tokens.holdKey]
        for k in kinds {
            var band = k.tint
            (band.lightAlpha, band.darkAlpha) = (0.12, 0.18)
            let bandColor = resolve(band, mode, over: mode == .dark ? Tokens.capBottom.dark : Tokens.capBottom.light)
            let ink = resolve(k.ink, mode, over: bandColor)
            #expect(ink.contrast(with: bandColor) >= 4.5, "ink \(ink.hex) on band \(bandColor.hex)")
            #expect(resolve(k.tint, mode, over: cap(mode)).contrast(with: cap(mode)) >= 3, "bar \(k.tint.light.hex)")
        }
    }
}
