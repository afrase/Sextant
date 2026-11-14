/*
 * Portions of this file are derived from Apple's IOHIDFamily: IOHIDEventSystemPlugIns/IOHIDAccelerationAlgorithm.cpp
 * (IOHIDParametricAcceleration::CreateWithParameters and ::multiplier, the user-space algorithm macOS runs today),
 * IOHIDSystem/IOHIPointing.cpp (PACurvesFillParamsFromDict) and IOHIDSystem/IOFixed64.cpp (IOQuarticFunction).
 *
 * Copyright (c) 1999-2009 Apple Computer, Inc.  All Rights Reserved.
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * Modifications (Sextant, 2026-11-14, ADR 0068): re-expressed in Swift; curves are values rather than IORegistry
 * dictionaries; a tracking speed that isn't a number picks the Mac's default; the standard trackpad curve set is
 * included as a fallback.
 * This file stays under the APSL 2.0; the rest of Sextant is MIT.
 */

import Foundation

/// One of macOS's parametric acceleration curves (`HIDAccelCurves`): an output speed for each input speed, both in
/// inches per second. A curve set holds one per tracking-speed setting (`index`); `PointerCurveSet.curve(at:)` blends
/// the two either side of the user's setting, as macOS does.
public struct PointerCurveParameters: Hashable, Sendable {
    /// The tracking speed this curve belongs to (System Settings' slider, 0...3).
    public let index: Double
    /// Linear, parabolic, cubic and quartic gains: f(x) = g1·x + (g2·x)² + (g3·x)³ + (g4·x)⁴. Always four.
    public let gains: [Double]
    /// Where the polynomial gives way to a straight line, then to a square root (inches per second; 0 is none).
    public let tangentLinear: Double
    public let tangentParabolicRoot: Double

    public init(index: Double, gains: [Double], tangentLinear: Double, tangentParabolicRoot: Double) {
        self.index = index
        self.gains = (gains + [0, 0, 0, 0]).prefix(4).map { $0.isFinite ? max($0, 0) : 0 }
        self.tangentLinear = tangentLinear.isFinite ? max(tangentLinear, 0) : 0
        self.tangentParabolicRoot = tangentParabolicRoot.isFinite ? max(tangentParabolicRoot, 0) : 0
    }

    /// Reads one `HIDAccelCurves` entry, whose numbers are 16.16 fixed point; nil when it has no gain at all.
    public init?(registryEntry entry: [String: Int]) {
        func value(_ key: String) -> Double { Double(entry[key] ?? 0) / 65536 }
        self.init(
            index: value("HIDAccelIndex"),
            gains: [
                value("HIDAccelGainLinear"), value("HIDAccelGainParabolic"), value("HIDAccelGainCubic"), value("HIDAccelGainQuartic"),
            ],
            tangentLinear: value("HIDAccelTangentSpeedLinear"), tangentParabolicRoot: value("HIDAccelTangentSpeedParabolicRoot"))
        guard gains.contains(where: { $0 != 0 }) else { return nil }
    }
}

/// A trackpad's curve set, sorted by tracking speed.
public struct PointerCurveSet: Hashable, Sendable {
    public let curves: [PointerCurveParameters]

    /// Nil when no curve has a gain.
    public init?(_ curves: [PointerCurveParameters]) {
        let usable = curves.filter { $0.gains.contains { $0 != 0 } }.sorted { $0.index < $1.index }
        guard !usable.isEmpty else { return nil }
        self.curves = usable
    }

    /// The curve for `trackingSpeed` as macOS picks it: the last curve at or below the setting, blended toward the next
    /// one when the setting falls between them; below the first curve, the first; past the last, the last.
    public func curve(at trackingSpeed: Double) -> PointerCurve {
        let speed = trackingSpeed.isNaN ? 0.6875 : max(trackingSpeed, 0)
        var current = 0
        for (i, curve) in curves.enumerated() where speed >= curve.index { current = i }
        guard current < curves.count else { return .linear }
        let low = curves[current]
        guard low.index < speed, current + 1 < curves.count else { return PointerCurve(low) }
        let high = curves[current + 1]
        let ratio = (speed - low.index) / (high.index - low.index)
        func blend(_ a: Double, _ b: Double) -> Double { a + ratio * (b - a) }
        return PointerCurve(
            PointerCurveParameters(
                index: speed, gains: zip(low.gains, high.gains).map(blend), tangentLinear: blend(low.tangentLinear, high.tangentLinear),
                tangentParabolicRoot: blend(low.tangentParabolicRoot, high.tangentParabolicRoot)))
    }

    /// The built-in trackpad's set on macOS 26 (an Apple Silicon MacBook Pro, 2026-11-14): used when the Mac has no
    /// trackpad to read it from. Ten literal curves with gains, so the init can't fail (PointerCurveTests checks it).
    public static let standardTrackpad =
        Self(standardTrackpadEntries.compactMap(PointerCurveParameters.init(registryEntry:))) ?? Self(unchecked: [])

    private static let standardTrackpadEntries: [[String: Int]] = [
        [
            "HIDAccelIndex": 0, "HIDAccelGainLinear": 65536, "HIDAccelTangentSpeedLinear": 484966,
            "HIDAccelTangentSpeedParabolicRoot": 1376256,
        ],
        [
            "HIDAccelIndex": 8192, "HIDAccelGainLinear": 64881, "HIDAccelGainParabolic": 32768, "HIDAccelGainCubic": 5243,
            "HIDAccelTangentSpeedLinear": 478413, "HIDAccelTangentSpeedParabolicRoot": 1310720,
        ],
        [
            "HIDAccelIndex": 32768, "HIDAccelGainLinear": 64225, "HIDAccelGainParabolic": 43254, "HIDAccelGainCubic": 6554,
            "HIDAccelTangentSpeedLinear": 471859, "HIDAccelTangentSpeedParabolicRoot": 1245184,
        ],
        [
            "HIDAccelIndex": 45056, "HIDAccelGainLinear": 62915, "HIDAccelGainParabolic": 54395, "HIDAccelGainCubic": 7864,
            "HIDAccelTangentSpeedLinear": 465306, "HIDAccelTangentSpeedParabolicRoot": 1179648,
        ],
        [
            "HIDAccelIndex": 57344, "HIDAccelGainLinear": 61604, "HIDAccelGainParabolic": 65536, "HIDAccelGainCubic": 9830,
            "HIDAccelTangentSpeedLinear": 458752, "HIDAccelTangentSpeedParabolicRoot": 1114112,
        ],
        [
            "HIDAccelIndex": 65536, "HIDAccelGainLinear": 60293, "HIDAccelGainParabolic": 75366, "HIDAccelGainCubic": 11796,
            "HIDAccelTangentSpeedLinear": 458752, "HIDAccelTangentSpeedParabolicRoot": 1048576,
        ],
        [
            "HIDAccelIndex": 98304, "HIDAccelGainLinear": 58327, "HIDAccelGainParabolic": 85197, "HIDAccelGainCubic": 13763,
            "HIDAccelTangentSpeedLinear": 458752, "HIDAccelTangentSpeedParabolicRoot": 983040,
        ],
        [
            "HIDAccelIndex": 131072, "HIDAccelGainLinear": 56361, "HIDAccelGainParabolic": 95027, "HIDAccelGainCubic": 15729,
            "HIDAccelTangentSpeedLinear": 458752, "HIDAccelTangentSpeedParabolicRoot": 917504,
        ],
        [
            "HIDAccelIndex": 163840, "HIDAccelGainLinear": 54395, "HIDAccelGainParabolic": 108790, "HIDAccelGainCubic": 18350,
            "HIDAccelTangentSpeedLinear": 458752, "HIDAccelTangentSpeedParabolicRoot": 851968,
        ],
        [
            "HIDAccelIndex": 196608, "HIDAccelGainLinear": 65536, "HIDAccelGainParabolic": 123208, "HIDAccelGainCubic": 23593,
            "HIDAccelTangentSpeedLinear": 458752, "HIDAccelTangentSpeedParabolicRoot": 786432,
        ],
    ]

    private init(unchecked curves: [PointerCurveParameters]) { self.curves = curves }
}

/// One curve, ready to evaluate: the polynomial up to its first tangent, then a straight line up to the second, then a
/// square root, so speed keeps growing ever more slowly. A curve with only one tangent skips the missing segment; one with
/// none is the polynomial throughout.
public struct PointerCurve: Hashable, Sendable {
    public let parameters: PointerCurveParameters
    private let tangent0: Double
    private let tangent1: Double
    private let hasLinear: Bool
    private let mLinear: Double
    private let bLinear: Double
    private let mRoot: Double
    private let bRoot: Double

    /// Output equals input: no acceleration.
    public static let linear = Self(PointerCurveParameters(index: 0, gains: [1], tangentLinear: 0, tangentParabolicRoot: 0))

    public init(_ parameters: PointerCurveParameters) {
        self.parameters = parameters
        let gains = parameters.gains
        let linear = parameters.tangentLinear
        let root = parameters.tangentParabolicRoot
        var t0 = Double.greatestFiniteMagnitude
        var t1 = Double.greatestFiniteMagnitude
        var mLinear = 0.0
        var bLinear = 0.0
        var mRoot = 0.0
        var bRoot = 0.0
        if linear != 0 {
            mLinear = Self.derivative(linear, gains)
            bLinear = Self.quartic(linear, gains) - mLinear * linear
            t0 = linear
            if root != 0 {
                let y1 = mLinear * root + bLinear
                mRoot = 2 * y1 * mLinear
                bRoot = y1 * y1 - mRoot * root
                t1 = root
            }
        } else if root != 0 {
            let y0 = Self.quartic(root, gains)
            mRoot = Self.derivative(root, gains)
            bRoot = y0 * y0 - mRoot * root
            t0 = root
        }
        tangent0 = t0
        tangent1 = t1
        hasLinear = linear != 0
        self.mLinear = mLinear
        self.bLinear = bLinear
        self.mRoot = mRoot
        self.bRoot = bRoot
    }

    /// Output speed for an input speed, both in inches per second.
    public func output(inchesPerSecond speed: Double) -> Double {
        guard speed > 0 else { return 0 }
        if speed <= tangent0 { return Self.quartic(speed, parameters.gains) }
        if speed <= tangent1 && hasLinear { return mLinear * speed + bLinear }
        return max(mRoot * speed + bRoot, 0).squareRoot()
    }

    /// Output over input at `speed`: what a movement at that speed is multiplied by. Its limit at rest is the linear gain.
    public func multiplier(inchesPerSecond speed: Double) -> Double {
        speed > 0 ? output(inchesPerSecond: speed) / speed : parameters.gains[0]
    }

    static func quartic(_ x: Double, _ g: [Double]) -> Double {
        g[0] * x + pow(g[1] * x, 2) + pow(g[2] * x, 3) + pow(g[3] * x, 4)
    }

    static func derivative(_ x: Double, _ g: [Double]) -> Double {
        g[0] + 2 * x * pow(g[1], 2) + 3 * pow(x, 2) * pow(g[2], 3) + 4 * pow(x, 3) * pow(g[3], 4)
    }
}
