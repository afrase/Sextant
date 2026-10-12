import Foundation
import SextantApplication
import Testing

@MainActor
struct RawHIDTraceTests {
    func entry(_ n: Int) -> HIDTraceEntry {
        HIDTraceEntry(date: Date(timeIntervalSince1970: Double(n)), direction: .received, bytes: [0x05, UInt8(n % 256), 0xFE])
    }

    @Test func keepsTheNewestEntriesUpToItsCapacityInOrder() async {
        let trace = RawHIDTrace { false }
        trace.isOn = true
        let total = RawHIDTrace.capacity + 100
        for n in 0..<total { trace.record(entry(n)) }
        #expect(await eventually { trace.entries.last == entry(total - 1) })
        #expect(trace.entries == (100..<total).map(entry))
    }

    @Test func keepsNothingWhileSecureInputIsOn() async {
        let secureInput = Flag()
        secureInput.isOn = true
        let trace = RawHIDTrace { secureInput.isOn }
        trace.isOn = true
        trace.record(entry(1))
        #expect(await eventually { secureInput.reads == 1 }, "asked for the report as it reached the log")
        secureInput.isOn = false
        trace.record(entry(2))
        #expect(await eventually { !trace.entries.isEmpty })
        #expect(trace.entries == [entry(2)], "the report typed into the password field is gone")
    }

    /// A report that arrives during secure input stays out even when the field loses focus before the log appends it.
    @Test func aReportFromAPasswordFieldNeverWaitsInTheQueue() async {
        let secureInput = Flag()
        let trace = RawHIDTrace { secureInput.isOn }
        trace.isOn = true
        secureInput.isOn = true
        trace.record(entry(1))
        secureInput.isOn = false
        trace.record(entry(2))
        #expect(await eventually { !trace.entries.isEmpty })
        #expect(trace.entries == [entry(2)])
    }

    @Test func keepsNothingWhileOffAndTurningItOffClearsIt() async throws {
        let trace = RawHIDTrace { false }
        trace.record(entry(1))
        trace.isOn = true
        trace.record(entry(2))
        #expect(await eventually { trace.entries == [entry(2)] }, "only what arrived while on")

        trace.isOn = false
        #expect(trace.entries.isEmpty, "turning it off clears it")
        trace.record(entry(3))
        try await Task.sleep(for: .milliseconds(20))
        #expect(trace.entries.isEmpty, "nothing is kept while off")

        trace.isOn = true
        trace.record(entry(4))
        #expect(await eventually { trace.entries == [entry(4)] }, "a new log starts empty")
    }
}
