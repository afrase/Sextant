import Testing

@testable import SextantUI

/// The number field beside Settings › Navigator's sliders (ADR 0069).
struct NumberFieldTests {
    @Test func typedNumbersAreHeldToTheRangeAndTheDigitsShown() {
        #expect(NumberField.parse("45", range: -180...180, digits: 0) == 45)
        #expect(NumberField.parse("500", range: -180...180, digits: 0) == 180)
        #expect(NumberField.parse("-200", range: -180...180, digits: 0) == -180)
        #expect(NumberField.parse("45.6", range: -180...180, digits: 0) == 46)
        #expect(NumberField.parse("1.234", range: 0...3, digits: 2) == 1.23)
        #expect(NumberField.parse(" 2 ", range: 0...3, digits: 2) == 2)
    }

    @Test func aTypographicMinusReads() {
        #expect(NumberField.parse("−90", range: -180...180, digits: 0) == -90)
    }

    @Test func textThatIsntANumberIsRefused() {
        #expect(NumberField.parse("", range: 0...3, digits: 2) == nil)
        #expect(NumberField.parse("fast", range: 0...3, digits: 2) == nil)
        #expect(NumberField.parse("-", range: -180...180, digits: 0) == nil)
    }

    @Test func whatIsShownReadsBackAsItself() {
        for value in [0.0, 1, 0.6875, 230, -135, 4.5] {
            for digits in 0...2 {
                let shown = NumberField.text(value, digits: digits)
                #expect(NumberField.text(NumberField.parse(shown, range: -1000...1000, digits: digits) ?? .nan, digits: digits) == shown)
            }
        }
    }
}
