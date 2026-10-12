import Foundation
import Observation
import os

/// The Developer raw-HID log (Settings › Advanced, ADR 0045): the last reports the live link wrote and read, newest
/// last. It lives in memory only and is never written to disk or os_log. It is off at launch, keeps nothing while off
/// or while secure input is on, and turning it off clears it.
@MainActor
@Observable
public final class RawHIDTrace {
    public static let capacity = 500

    public private(set) var entries: [HIDTraceEntry] = []
    public var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            reading?.cancel()
            reading = nil
            feed.withLock {
                $0?.finish()
                $0 = nil
            }
            entries = []
            guard isOn else { return }
            let (stream, continuation) = AsyncStream.makeStream(of: HIDTraceEntry.self, bufferingPolicy: .bufferingNewest(Self.capacity))
            feed.withLock { $0 = continuation }
            // A cancelled reader drops what its stream still holds: those reports belong to the log that was cleared.
            reading = Task { [weak self] in for await entry in stream where !Task.isCancelled { self?.append(entry) } }
        }
    }

    /// Open only while on, so the link's reports go nowhere while off.
    private let feed = OSAllocatedUnfairLock<AsyncStream<HIDTraceEntry>.Continuation?>(initialState: nil)
    @ObservationIgnored private var reading: Task<Void, Never>?

    private let secureInputProbe: @Sendable () -> Bool

    /// - Parameter secureInputProbe: `IsSecureEventInputEnabled`, asked for each report, as ``LiveSession`` asks for each
    ///   event it delivers.
    public init(secureInputProbe: @escaping @Sendable () -> Bool) { self.secureInputProbe = secureInputProbe }

    /// The link's sink: called from any thread, in the order the link saw the reports. Secure input is asked here, as a
    /// report arrives, and again when it's appended, so a report typed into a password field never waits in the queue
    /// for the field to lose focus.
    nonisolated public func record(_ entry: HIDTraceEntry) {
        guard !secureInputProbe() else { return }
        feed.withLock { _ = $0?.yield(entry) }
    }

    private func append(_ entry: HIDTraceEntry) {
        // Paused while a password field has focus (spec §1.4): positions read against the layout give back the keys.
        guard !secureInputProbe() else { return }
        entries.append(entry)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }
}
