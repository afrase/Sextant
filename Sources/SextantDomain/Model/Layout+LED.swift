import Foundation

extension KeyboardLayout {
    /// The color a key's LED shows on a layer, as the firmware's LED map has it: the key's own color, else the layer's,
    /// else nil (off). Nil too for a layer or key the layout doesn't have.
    public func ledColor(layer: Int, index: Int) -> HexColor? {
        guard layers.indices.contains(layer), layers[layer].keys.indices.contains(index) else { return nil }
        return layers[layer].keys[index].glowColor ?? layers[layer].color
    }
}

/// One LED's color as the keyboard takes it over raw HID: 8-bit red, green and blue.
public struct LEDColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public static let off = Self(red: 0, green: 0, blue: 0)

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The color at `brightness` (0...1) of its full value, rounded.
    public init(_ color: HexColor, brightness: Double = 1) {
        let scale = min(max(brightness.isNaN ? 0 : brightness, 0), 1)
        func byte(_ unit: Double) -> UInt8 { UInt8((unit * scale * 255).rounded()) }
        self.init(red: byte(color.red), green: byte(color.green), blue: byte(color.blue))
    }
}
