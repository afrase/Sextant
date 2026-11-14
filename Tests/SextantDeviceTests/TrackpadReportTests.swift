import SextantApplication
import SextantDomain
import Testing

@testable import SextantDevice

/// Reports exactly as the user's Navigator sent them (research 06, spike 2).
struct TrackpadReportTests {
    private func bytes(_ hex: String) -> [UInt8] { hex.split(separator: " ").compactMap { UInt8($0, radix: 16) } }

    @Test func oneFinger() throws {
        let report = try #require(TrackpadReport.parse(bytes("01 03 00 e4 04 fd 00 00 00 00 00 00 00 7c 85 01")))
        #expect(report.contacts == [TrackpadContact(id: 0, x: 1252, y: 253)])
        #expect(report.scanTime == 34172)
    }

    @Test func twoFingersKeepTheirIDs() throws {
        let report = try #require(TrackpadReport.parse(bytes("01 03 00 1a 05 52 02 03 01 e1 01 ad 02 c6 29 02")))
        #expect(report.contacts == [TrackpadContact(id: 0, x: 1306, y: 594), TrackpadContact(id: 1, x: 481, y: 685)])
    }

    @Test func aLiftingFingerIsLeftOut() throws {
        // Finger 0 lifting (tip off), finger 1 still down.
        let report = try #require(TrackpadReport.parse(bytes("01 01 00 1a 05 52 02 03 01 e1 01 ad 02 c6 29 01")))
        #expect(report.contacts.map(\.id) == [1])
        let lift = try #require(TrackpadReport.parse(bytes("01 00 00 1a 05 52 02 00 00 00 00 00 00 c6 29 00")))
        #expect(lift.contacts.isEmpty)
    }

    @Test func otherReportsAreIgnored() {
        #expect(TrackpadReport.parse(bytes("06 00 ff 01")) == nil)  // the fallback mouse
        #expect(TrackpadReport.parse(bytes("01 03 00 e4")) == nil)  // short
    }

    @Test func theInputModeReport() {
        #expect(TrackpadReport.inputMode(.touchpad) == [4, 3])
        #expect(TrackpadReport.inputMode(.mouse) == [4, 0])
    }
}
