import Foundation
import SextantApplication
import Testing

@MainActor
struct RawHIDTraceTests {
    func entry(_ n: Int) -> HIDTraceEntry {
        HIDTraceEntry(date: Date(timeIntervalSince1970: Double(n)), direction: .received, bytes: [0x05, UInt8(n % 256), 0xFE])
    }

    @Test func keepsTheNewestEntriesUpToItsCapacityInOrder() async {
        let trace = RawHIDTrace()
        trace.isOn = true
        let total = RawHIDTrace.capacity + 100
        for n in 0..<total { trace.record(entry(n)) }
        #expect(await eventually { trace.entries.last == entry(total - 1) })
        #expect(trace.entries == (100..<total).map(entry))
    }

    @Test func keepsNothingWhileOffAndTurningItOffClearsIt() async throws {
        let trace = RawHIDTrace()
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
