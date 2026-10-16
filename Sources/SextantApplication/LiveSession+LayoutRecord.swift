import Foundation

extension LiveSession {
    /// Reads the layout record a Sextant build stores (ADR 0061), 24 bytes per report, over the paired Live View session.
    /// Changes nothing on the keyboard. `progress` gets the fraction read after each part.
    ///
    /// It asks for offset 0, takes the record's size from the reply, then asks for each next offset in turn. Replies are
    /// matched by offset, so a stale one or another host's is ignored. A part that hasn't come half a second after its
    /// request was likely written is asked for once more. Cancelling the read ends it as ``LayoutReadError/disconnected``.
    /// The record's bytes never reach ``activity()``, the raw-HID log or `os_log`: they hold macro text (ADR 0042).
    public func readLayoutRecord(
        progress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws(LayoutReadError) -> [UInt8] {
        guard canSend else { throw .notLive }
        guard layoutRead == nil else { throw .busy }
        let (inputs, feed) = AsyncStream.makeStream(of: LayoutReadInput.self)
        layoutRead = feed
        var deadline = LayoutReadDeadline()
        defer {
            deadline.cancel()
            layoutRead = nil
            feed.finish()
        }
        var record = LayoutRecordAssembly()
        var asked = 1
        try ask(at: record.offset, deadline: &deadline, feed: feed)
        for await input in inputs {
            switch input {
            case .ended: throw .disconnected
            // ORYX_ERR_UNKNOWN_COMMAND: firmware without the read. Other codes answer other commands.
            case .refused(0xFF): throw .noRecord
            case .refused: continue
            case let .deadline(id):
                guard id == deadline.id else { continue }
                guard asked == 1 else { throw .timedOut }
                asked = 2
                try ask(at: record.offset, deadline: &deadline, feed: feed)
            case let .chunk(chunk):
                guard try record.add(chunk) else { continue }
                progress(record.fraction)
                if let bytes = record.complete { return bytes }
                asked = 1
                try ask(at: record.offset, deadline: &deadline, feed: feed)
            }
        }
        throw .disconnected  // cancelled
    }

    /// Asks for the part at `offset`, due half a second after the link has likely written the request.
    private func ask(
        at offset: Int, deadline: inout LayoutReadDeadline, feed: AsyncStream<LayoutReadInput>.Continuation
    ) throws(LayoutReadError) {
        do throws(DeviceError) {
            try send(.readLayoutRecord(offset: offset))
        } catch {
            throw LayoutReadError.disconnected
        }
        deadline.arm(layoutRecordReplyWait + queuedWritesLeft, clock: clock, feed: feed)
    }
}

/// What a running ``LiveSession/readLayoutRecord(progress:)`` waits for.
enum LayoutReadInput: Sendable {
    /// Part of the record, for whichever offset.
    case chunk(LayoutRecordChunk)
    /// The firmware refused a command, with its Oryx error code.
    case refused(UInt8)
    /// A part's time ran out; only the newest deadline's id counts.
    case deadline(Int)
    /// The paired session ended: the keyboard went away, or Live View ended.
    case ended
}

/// A layout read's one pending timeout: arming another cancels it, and only the newest id counts.
private struct LayoutReadDeadline {
    private(set) var id = 0
    private var task: Task<Void, Never>?

    mutating func arm(_ duration: Duration, clock: any Clock<Duration>, feed: AsyncStream<LayoutReadInput>.Continuation) {
        task?.cancel()
        id += 1
        let id = id
        task = Task { if (try? await clock.sleep(for: duration)) != nil { feed.yield(.deadline(id)) } }
    }

    func cancel() { task?.cancel() }
}

/// A layout record arriving part by part: its size from the first reply, then each next offset in turn.
private struct LayoutRecordAssembly {
    /// The most a record can hold: its size is two bytes on the wire.
    static let maximumSize = 65_535

    private var bytes: [UInt8] = []
    private var size: Int?

    /// The offset to ask for next.
    var offset: Int { bytes.count }
    /// How much has arrived, 0–1.
    var fraction: Double { size.map { Double(bytes.count) / Double($0) } ?? 0 }
    /// The whole record, once every part has arrived.
    var complete: [UInt8]? { bytes.count == size ? bytes : nil }

    /// Adds the part for ``offset``. False for a reply to another offset (a stale one, or another host's), which changes
    /// nothing; throws when the parts don't add up: a size that is 0, over 64 KiB or changed, or a part that is empty
    /// or runs past the size.
    mutating func add(_ chunk: LayoutRecordChunk) throws(LayoutReadError) -> Bool {
        guard chunk.offset == offset else { return false }
        let size = self.size ?? chunk.size
        let fits = !chunk.bytes.isEmpty && offset + chunk.bytes.count <= size
        guard (1...Self.maximumSize).contains(size), chunk.size == size, fits else { throw .malformed }
        self.size = size
        bytes += chunk.bytes
        return true
    }
}
