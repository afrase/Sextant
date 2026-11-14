import Foundation
import Testing

@testable import SextantDomain

struct PointerCurveTests {
    private let set = PointerCurveSet.standardTrackpad

    @Test func theStandardSetHasTenCurvesInOrder() {
        #expect(set.curves.count == 10)
        #expect(set.curves.map(\.index) == set.curves.map(\.index).sorted())
        #expect(set.curves.first?.index == 0)
        #expect(set.curves.last?.index == 3)
    }

    @Test func aSettingOnACurvePicksThatCurve() {
        let curve = set.curve(at: 0.6875)
        #expect(curve.parameters.gains[0] == 62915.0 / 65536)
        #expect(curve.parameters.gains[1] == 54395.0 / 65536)
        #expect(curve.parameters.tangentLinear == 465306.0 / 65536)
    }

    @Test func aSettingBetweenCurvesBlendsThem() {
        let low = set.curve(at: 0.6875).parameters
        let high = set.curve(at: 0.875).parameters
        let mid = set.curve(at: (0.6875 + 0.875) / 2).parameters
        for i in 0..<4 { #expect(abs(mid.gains[i] - (low.gains[i] + high.gains[i]) / 2) < 1e-12) }
        #expect(abs(mid.tangentParabolicRoot - (low.tangentParabolicRoot + high.tangentParabolicRoot) / 2) < 1e-12)
    }

    @Test func settingsPastEitherEndUseTheEndCurve() {
        #expect(set.curve(at: -1).parameters.gains == set.curves[0].gains)
        #expect(set.curve(at: 9).parameters.gains == set.curves[9].gains)
    }

    /// Golden values from an independent port of IOHIDAccelerationAlgorithm.cpp (Python, 2026-11-14) for the Mac's
    /// default tracking speed: the polynomial is g1·x + (g2·x)² + (g3·x)³, then a line from 7.1 in/s, then a root from 18.
    @Test func theDefaultCurveMatchesApple() {
        let curve = set.curve(at: 0.6875)
        let golden: [(Double, Double)] = [
            (1, 1.6506375424924045), (5, 22.238583192074657), (10, 74.07286820540514),
            (20, 182.7901362748157), (30, 262.8439346264519),
        ]
        for (speed, output) in golden {
            #expect(abs(curve.output(inchesPerSecond: speed) - output) < 1e-9, "\(speed) in/s")
        }
    }

    @Test func aCurveWithOnlyALinearTangentStaysLinear() {
        let curve = PointerCurve(PointerCurveParameters(index: 0, gains: [1, 0.5], tangentLinear: 5, tangentParabolicRoot: 0))
        #expect(abs(curve.output(inchesPerSecond: 5) - 11.25) < 1e-9)
        #expect(abs(curve.output(inchesPerSecond: 5.01) - 11.285) < 1e-9)
        #expect(abs(curve.output(inchesPerSecond: 20) - 63.75) < 1e-9)
    }

    @Test func aCurveWithoutTangentsIsThePolynomialThroughout() {
        let curve = PointerCurve(PointerCurveParameters(index: 0, gains: [1, 0.5], tangentLinear: 0, tangentParabolicRoot: 0))
        #expect(abs(curve.output(inchesPerSecond: 5) - 11.25) < 1e-9)
        #expect(abs(curve.output(inchesPerSecond: 20) - 120) < 1e-9)
    }

    @Test func aCurveWithOnlyARootTangentGoesStraightToTheRoot() {
        let curve = PointerCurve(PointerCurveParameters(index: 0, gains: [1, 0.5], tangentLinear: 0, tangentParabolicRoot: 4))
        #expect(abs(curve.output(inchesPerSecond: 3) - 5.25) < 1e-9)
        #expect(abs(curve.output(inchesPerSecond: 4) - 8) < 1e-9)
        #expect(abs(curve.output(inchesPerSecond: 10) - 9.055385138137417) < 1e-9)
    }

    @Test func aTrackingSpeedThatIsntANumberUsesTheMacsDefault() {
        #expect(set.curve(at: .nan).parameters.index == 0.6875)
        #expect(set.curve(at: -2).parameters.index == 0)
    }

    @Test func anEmptySetMovesOneForOne() {
        #expect(PointerCurve.linear.output(inchesPerSecond: 3) == 3)
        #expect(PointerCurve.linear.multiplier(inchesPerSecond: 3) == 1)
    }

    @Test func theCurveIsContinuousAtItsTangents() {
        for speed in [0.6875, 0.78125, 1, 1.2, 3] {
            let curve = set.curve(at: speed)
            for tangent in [curve.parameters.tangentLinear, curve.parameters.tangentParabolicRoot] where tangent > 0 {
                let below = curve.output(inchesPerSecond: tangent - 1e-6)
                let above = curve.output(inchesPerSecond: tangent + 1e-6)
                #expect(abs(above - below) < 1e-3, "tracking \(speed), tangent \(tangent)")
            }
        }
    }

    @Test func outputKeepsRisingWithSpeed() {
        let curve = set.curve(at: 1)
        var last = 0.0
        for step in 1...600 {
            let output = curve.output(inchesPerSecond: Double(step) * 0.1)  // through the root region (from 16 in/s)
            #expect(output > last)
            last = output
        }
    }

    @Test func theMultiplierAtRestIsTheLinearGain() {
        let curve = set.curve(at: 1)
        #expect(curve.multiplier(inchesPerSecond: 0) == curve.parameters.gains[0])
    }

    @Test func registryEntriesAreSixteenSixteenFixedPoint() {
        let entry = PointerCurveParameters(registryEntry: ["HIDAccelIndex": 32768, "HIDAccelGainLinear": 65536, "HIDAccelGainCubic": 6554])
        #expect(entry?.index == 0.5)
        #expect(entry?.gains == [1, 0, 6554.0 / 65536, 0])
        #expect(PointerCurveParameters(registryEntry: ["HIDAccelIndex": 0]) == nil)
        #expect(PointerCurveSet([]) == nil)
    }
}
