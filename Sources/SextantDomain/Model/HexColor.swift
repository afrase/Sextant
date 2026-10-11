import Foundation

/// An sRGB colour stored as plain data (layer colours, per-key LED colours, set-colour keys).
///
/// Colours are plain values so the model stays `Sendable` and `Codable`; the UI converts them.
public struct HexColor: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Red, 0...1.
    public var red: Double
    /// Green, 0...1.
    public var green: Double
    /// Blue, 0...1.
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        // Clamp, and turn NaN into 0, so `hex` can never trap.
        func unit(_ v: Double) -> Double { v.isNaN ? 0 : min(max(v, 0), 1) }
        self.red = unit(red)
        self.green = unit(green)
        self.blue = unit(blue)
    }

    /// Parses `#RRGGBB`, `RRGGBB` or `#RGB` (case-insensitive). Returns nil for anything else.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// Uppercase `#RRGGBB`.
    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public var description: String { hex }

    /// Hue (0...1), saturation and brightness, handy for LED maths (QMK stores HSV).
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxV = max(red, green, blue), minV = min(red, green, blue), delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    /// Relative luminance (WCAG), useful for picking a legible legend colour on a tinted key.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    // Codable as a hex string, matching Oryx's storage.
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let c = Self(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad color \(s)"))
        }
        self = c
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}
