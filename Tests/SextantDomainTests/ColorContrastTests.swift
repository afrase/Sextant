import SextantDomain
import Testing

/// Spec §10.1: the layer transforms must meet their contrast thresholds for the user's colours and the swatches.
struct ColorContrastTests {
    static let white = HexColor(red: 1, green: 1, blue: 1)
    static let darkBand = HexColor(hex: "#2A2A2E")!
    static let colors = ["#00F0FF", "#42FF00"].compactMap(HexColor.init(hex:)) + KeyboardLayout.defaultSwatch

    @Test(arguments: colors)
    func displayAndInkMeetThresholds(color: HexColor) {
        #expect(color.darkened(toContrast: 3, against: Self.white).contrast(with: Self.white) >= 3)
        #expect(color.darkened(toContrast: 4.5, against: Self.white).contrast(with: Self.white) >= 4.5)
        #expect(color.lightened(toContrast: 4.5, against: Self.darkBand).contrast(with: Self.darkBand) >= 4.5)
    }

    /// The transform stops at the first step that clears the threshold, so colours stay as bright as allowed.
    /// (Spec §4.5's "#00F0FF → about #00959E" overshoots its own 3:1 rule; the rule wins.)
    @Test func userColoursStayAsBrightAsAllowed() {
        let cyan = HexColor(hex: "#00F0FF")!.darkened(toContrast: 3, against: Self.white)
        #expect(cyan.contrast(with: Self.white) < 3.3, "\(cyan.hex)")
        let green = HexColor(hex: "#42FF00")!.darkened(toContrast: 4.5, against: Self.white)
        #expect(abs(green.green - Double(0x80) / 255) < 0.03, "about #218000, got \(green.hex)")
    }

    @Test func hsbRoundTrips() {
        for c in Self.colors {
            let (h, s, b) = c.hsb
            #expect(HexColor(hue: h, saturation: s, brightness: b).hex == c.hex)
        }
    }
}
