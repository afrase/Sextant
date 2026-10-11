import Foundation

// WCAG contrast and the layer-colour display transforms (spec §4.5). Layer colours are user data and
// firmware LED colours, so the UI never changes them; it derives legible display and ink variants.

extension HexColor {
    /// Builds a colour from hue, saturation and brightness, each 0...1.
    public init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - floor(hue)) * 6, s = min(max(saturation, 0), 1), v = min(max(brightness, 0), 1)
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) =
            switch Int(h) {
            case 0: (c, x, 0)
            case 1: (x, c, 0)
            case 2: (0, c, x)
            case 3: (0, x, c)
            case 4: (x, 0, c)
            default: (c, 0, x)
            }
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    /// WCAG 2 contrast ratio, 1...21.
    public func contrast(with other: HexColor) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Lowers HSB brightness in 0.02 steps until the contrast against `background` reaches `ratio`
    /// (light-mode `layer.display` at 3:1 and `layer.ink` at 4.5:1 against white).
    public func darkened(toContrast ratio: Double, against background: HexColor) -> HexColor {
        let (h, s, v) = hsb
        var out = self
        var b = v
        while out.contrast(with: background) < ratio, b > 0 {
            b = max(0, b - 0.02)
            out = HexColor(hue: h, saturation: s, brightness: b)
        }
        return out
    }

    /// Mixes toward white in 2% steps until the contrast against `background` reaches `ratio`
    /// (dark-mode `layer.ink` at 4.5:1 against the band).
    public func lightened(toContrast ratio: Double, against background: HexColor) -> HexColor {
        var out = self
        var t = 0.0
        while out.contrast(with: background) < ratio, t < 1 {
            t = min(1, t + 0.02)
            out = HexColor(red: red + (1 - red) * t, green: green + (1 - green) * t, blue: blue + (1 - blue) * t)
        }
        return out
    }
}
