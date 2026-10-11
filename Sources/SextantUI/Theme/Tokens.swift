import AppKit
import SextantDomain
import SwiftUI

// Colour tokens from spec §10.1, as code (ADR 0008): one place for light, dark and high-contrast values.
// TokenContrastTests checks legends on caps and band ink at 4.5:1 and signal bars at 3:1, in light and dark.

/// A colour with light, dark and optional high-contrast variants, resolved by the drawing appearance.
public struct Token: Sendable {
    public var light: HexColor
    public var dark: HexColor
    public var lightAlpha: Double = 1
    public var darkAlpha: Double = 1
    /// High-contrast alphas, when they differ (cap edges, ghost strokes).
    public var lightAlphaHC: Double?
    public var darkAlphaHC: Double?

    public var color: Color { Color(nsColor: nsColor) }

    public var nsColor: NSColor {
        let t = self
        return NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isHC = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            let c = isDark ? t.dark : t.light
            let a = isDark ? (isHC ? t.darkAlphaHC : nil) ?? t.darkAlpha : (isHC ? t.lightAlphaHC : nil) ?? t.lightAlpha
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: a)
        }
    }
}

extension HexColor {
    /// SwiftUI colour in the sRGB colour space.
    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    static let white = HexColor(red: 1, green: 1, blue: 1)
    static let black = HexColor(red: 0, green: 0, blue: 0)
}

private func hex(_ v: UInt32) -> HexColor {
    HexColor(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// Spec §10.1 bench, cap and kind tokens.
public enum Tokens {
    static func pair(_ light: UInt32, _ dark: UInt32) -> Token { Token(light: hex(light), dark: hex(dark)) }

    public static let benchBase = pair(0xEDEDF0, 0x141416)
    public static let benchLift = pair(0xF7F7F9, 0x202024)
    public static let benchGrid = Token(light: .black, dark: .white, lightAlpha: 0.04, darkAlpha: 0.045, lightAlphaHC: 0, darkAlphaHC: 0)
    public static let capTop = pair(0xFFFFFF, 0x3A3A3F)
    public static let capBottom = pair(0xF4F4F6, 0x303035)
    public static let capEdge = Token(light: .black, dark: .white, lightAlpha: 0.13, darkAlpha: 0.10, lightAlphaHC: 0.30, darkAlphaHC: 0.28)
    public static let capHighlight = Token(light: .white, dark: .white, lightAlpha: 0.90, darkAlpha: 0.08)
    public static let capLegend = pair(0x1D1D1F, 0xF2F2F4)
    public static let capLegend2 = pair(0x5E5E63, 0xAEAEB4)
    public static let ghostStroke = Token(
        light: .black, dark: .white, lightAlpha: 0.22, darkAlpha: 0.18, lightAlphaHC: 0.40, darkAlphaHC: 0.40)
    public static let ghostFill = Token(light: .black, dark: .white, lightAlpha: 0.02, darkAlpha: 0.025)
    public static let capUnlit = pair(0xE6E6EA, 0x121214)
    /// Base-layer chip (no colour).
    public static let neutralChip = pair(0x8E8E93, 0x98989D)

    /// Kind colour (bar, band hairline, band fill at 12% / 18%) and band ink.
    public static func kind(_ kind: KeyKind) -> (tint: Token, ink: Token)? {
        switch kind {
        case .modifier: (pair(0x4F4CCF, 0xA9A7FF), pair(0x4F4CCF, 0xF2F2F4))
        case .layer: layerKind
        case .lighting: (pair(0x7D5A00, 0xFFD43B), pair(0x7D5A00, 0xFFD43B))
        case .label: (pair(0x0A6C94, 0x80D5F6), pair(0x0A6C94, 0x80D5F6))
        case .macro: (pair(0x7A35C4, 0xD6B8FF), pair(0x7A35C4, 0xD6B8FF))
        case .tapDance: (pair(0xA3275F, 0xFF9CC8), pair(0xA3275F, 0xF2F2F4))
        case .disabled: (pair(0x6E6E73, 0xA8A8AE), pair(0x6E6E73, 0xF2F2F4))
        case .regular, .dualFunction, .transparent: nil
        }
    }

    /// Layer keys whose target has no colour.
    public static let layerKind = (tint: pair(0x0A6E67, 0x5FE3D3), ink: pair(0x0A6E67, 0x5FE3D3))
    /// The band colour for a hold that is a plain key (= / Esc).
    public static let holdKey = (tint: pair(0x9E4700, 0xFFB870), ink: pair(0x9E4700, 0xFFB870))
    public static let danger = Token(light: hex(0xFF3B30), dark: hex(0xFF453A))
    /// `status.warning` and `status.success` (system orange and green), for issue rings and live presses.
    public static let warning = Token(light: hex(0xFF9500), dark: hex(0xFF9F0A))
    public static let success = Token(light: hex(0x34C759), dark: hex(0x30D158))
    /// Opaque stand-in for app glass under Reduce Transparency, Increase Contrast and in snapshots (§10.4).
    public static let surface = Token(light: hex(0xFBFBFD), dark: hex(0x26262B), lightAlpha: 0.96, darkAlpha: 0.96)
}

/// Display variants of a user's layer colour (spec §4.5), computed once per colour.
public struct LayerTones: Sendable, Equatable {
    /// Rings, chips and glows.
    public var display: Token
    /// Text on chips and bands.
    public var ink: Token

    public init(_ color: HexColor) {
        let bandDark = hex(0x2A2A2E)
        display = Token(light: color.darkened(toContrast: 3, against: .white), dark: color)
        ink = Token(light: color.darkened(toContrast: 4.5, against: .white), dark: color.lightened(toContrast: 4.5, against: bandDark))
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.display.light == b.display.light && a.display.dark == b.display.dark
    }
}
