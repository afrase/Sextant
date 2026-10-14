import Foundation

/// A colour ramp through evenly spaced stops, interpolated in OKLab so the steps look even to the eye (spec §10.1's
/// heat ramp).
public struct HeatRamp: Hashable, Sendable {
    public var stops: [HexColor]

    public init(_ stops: [HexColor]) { self.stops = stops }

    /// The colour at `t` (0 is the first stop, 1 the last).
    public func color(at t: Double) -> HexColor {
        guard let first = stops.first else { return HexColor(red: 0, green: 0, blue: 0) }
        guard stops.count > 1 else { return first }
        let scaled = min(max(t.isNaN ? 0 : t, 0), 1) * Double(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        return OKLab(stops[i]).mixed(with: OKLab(stops[i + 1]), by: scaled - Double(i)).color
    }
}

/// Björn Ottosson's OKLab (2020), from and to sRGB.
struct OKLab: Hashable {
    var l: Double
    var a: Double
    var b: Double

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ color: HexColor) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (linear(color.red), linear(color.green), linear(color.blue))
        let lms = (
            cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b),
            cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b),
            cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        )
        l = 0.2104542553 * lms.0 + 0.7936177850 * lms.1 - 0.0040720468 * lms.2
        a = 1.9779984951 * lms.0 - 2.4285922050 * lms.1 + 0.4505937099 * lms.2
        self.b = 0.0259040371 * lms.0 + 0.7827717662 * lms.1 - 0.8086757660 * lms.2
    }

    var color: HexColor {
        let l3 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m3 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s3 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        func gamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
        return HexColor(
            red: gamma(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
            green: gamma(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
            blue: gamma(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3))
    }

    func mixed(with other: Self, by t: Double) -> Self {
        Self(l: l + (other.l - l) * t, a: a + (other.a - a) * t, b: b + (other.b - b) * t)
    }
}
