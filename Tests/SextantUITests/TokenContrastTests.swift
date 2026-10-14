import AppKit
import SextantDomain
import SwiftUI
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
            let band = Token(light: k.tint.light, dark: k.tint.dark, lightAlpha: 0.12, darkAlpha: 0.18)
            let bandColor = resolve(band, mode, over: mode == .dark ? Tokens.capBottom.dark : Tokens.capBottom.light)
            let ink = resolve(k.ink, mode, over: bandColor)
            #expect(ink.contrast(with: bandColor) >= 4.5, "ink \(ink.hex) on band \(bandColor.hex)")
            #expect(resolve(k.tint, mode, over: cap(mode)).contrast(with: cap(mode)) >= 3, "bar \(k.tint.light.hex)")
        }
    }

    /// The 8 combo colours (spec §10.1, ADR 0046): rings and traces at least 3:1 on the cap and the bench, and the output
    /// pill's ink, black or white by luminance as ComboOverlay picks it, at least 4.5:1 on the pill.
    @Test(arguments: Mode.allCases)
    func comboColours(mode: Mode) {
        #expect(Tokens.combos.count == 8 && Set(Tokens.combos.map(\.light.hex)).count == 8)
        let surfaces =
            mode == .dark
            ? [Tokens.capTop.dark, Tokens.benchBase.dark, Tokens.benchLift.dark]
            : [
                Tokens.capTop.light, Tokens.benchBase.light, Tokens.benchLift.light,
            ]
        for token in Tokens.combos {
            let color = mode == .dark ? token.dark : token.light
            for surface in surfaces { #expect(color.contrast(with: surface) >= 3, "ring \(color.hex) on \(surface.hex)") }
            let ink: HexColor = color.luminance > 0.179 ? .black : .white
            #expect(ink.contrast(with: color) >= 4.5, "pill ink on \(color.hex)")
        }
        #expect(Tokens.combo(8) == Tokens.combo(0), "the palette goes round")
    }
}

/// The heat ramp (spec §8.5, §10.1): one blue hue at every step, the legend's ink (black or white by luminance, as
/// KeyCap picks it) at least 4.5:1 on each step, and the hottest step at least 3:1 against the cap, in light and dark.
struct HeatRampContrastTests {
    @Test(arguments: TokenContrastTests.Mode.allCases)
    func everyStepReads(mode: TokenContrastTests.Mode) {
        #expect(Tokens.heatSteps.count == 21)
        let fills = Tokens.heatSteps.map { mode == .dark ? $0.dark : $0.light }
        for fill in fills {
            let ink: HexColor = fill.luminance > 0.179 ? .black : .white
            #expect(ink.contrast(with: fill) >= 4.5, "ink on \(fill.hex)")
            #expect(abs(fill.hsb.hue - 0.6) < 0.05, "\(fill.hex) is the ramp's blue")
        }
        let cap = mode == .dark ? Tokens.capTop.dark : Tokens.capTop.light
        #expect((fills.last?.contrast(with: cap) ?? 0) >= 3)
        // Light mode runs light to dark, dark mode dark to light, so heat always moves away from the cap.
        let luminance = fills.map(\.luminance)
        #expect(mode == .dark ? luminance == luminance.sorted() : luminance == luminance.sorted(by: >))
        #expect(Tokens.heat(-1) == Tokens.heat(0) && Tokens.heat(2) == Tokens.heat(1) && Tokens.heat(.nan) == Tokens.heat(0))
    }
}

/// A token builds its colour once (a fresh dynamic colour on every read made each cap slower to redraw); it still
/// resolves per drawing appearance.
struct TokenColourTests {
    func alpha(_ token: Token, in name: NSAppearance.Name) -> Double? {
        var alpha: Double?
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            alpha = NSColor(token.color).usingColorSpace(.sRGB).map { Double($0.alphaComponent) }
        }
        return alpha
    }

    @Test func builtOnceAndSharedByEveryRead() {
        let (edge, edgeAgain) = (Tokens.capEdge.color, Tokens.capEdge.color)
        #expect(edge == edgeAgain)
        let (bar, barAgain) = (Tokens.kind(.modifier)?.tint.color, Tokens.kind(.modifier)?.tint.color)
        #expect(bar == barAgain)
    }

    /// Light and dark only: a high-contrast appearance can't be made by name while the system setting is off.
    @Test func resolvesPerAppearance() throws {
        for (name, value) in [(NSAppearance.Name.aqua, 0.13), (.darkAqua, 0.10)] {
            let resolved = try #require(alpha(Tokens.capEdge, in: name))
            #expect(abs(resolved - value) < 0.001, "\(name.rawValue)")
        }
    }
}
