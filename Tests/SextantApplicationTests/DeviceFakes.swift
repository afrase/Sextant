import Foundation
import SextantApplication
import SextantDomain
import Synchronization

/// Presence as the real watcher reports it: devices already present arrive first, then changes, to every subscriber.
final class FakeDeviceWatcher: DeviceWatcher {
    private struct State {
        var present: [ConnectedDevice] = []
        var subscribers: [UUID: AsyncStream<DeviceEvent>.Continuation] = [:]
    }
    private let state = Mutex(State())

    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: DeviceEvent.self)
        let id = UUID()
        state.withLock { s in
            s.present.forEach { continuation.yield(.attached($0)) }
            s.subscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) } }
        return stream
    }

    var subscriberCount: Int { state.withLock { $0.subscribers.count } }

    func attach(_ device: ConnectedDevice) {
        state.withLock { s in
            s.present.append(device)
            s.subscribers.values.forEach { $0.yield(.attached(device)) }
        }
    }

    func detach(_ id: UInt64) {
        state.withLock { s in
            s.present.removeAll { $0.id == id }
            s.subscribers.values.forEach { $0.yield(.detached(id: id)) }
        }
    }
}

/// A live link whose sessions the test drives; it records every command each session receives, and answers each layout
/// read as the keyboard's firmware would (``storeLayoutRecord(_:)``).
final class FakeKeyboardLink: KeyboardLink {
    private let sessions = Mutex<[AsyncStream<LiveEvent>.Continuation]>([])
    private let received = Mutex<[[KeyboardCommand]]>([])
    private let closed = Mutex<Set<Int>>([])
    /// The layout record the firmware stores; nil for firmware that stores none.
    private let record = Mutex<[UInt8]?>(nil)
    /// Layout reads still to go unanswered.
    private let unanswered = Mutex(0)

    func session(
        with device: KeyboardDevice, board: BoardDefinition, commands: AsyncStream<KeyboardCommand>
    ) -> AsyncStream<LiveEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveEvent.self)
        let n = sessions.withLock {
            $0.append(continuation)
            return $0.count - 1
        }
        received.withLock { $0.append([]) }
        Task {
            for await command in commands {
                received.withLock { $0[n].append(command) }
                if case let .readLayoutRecord(offset) = command, let answer = reply(toReadAt: offset) { continuation.yield(answer) }
            }
        }
        continuation.onTermination = { [self] _ in closed.withLock { _ = $0.insert(n) } }
        return stream
    }

    /// From now on, each layout read a session receives is answered as a Sextant build storing `bytes` answers it: up to
    /// 24 bytes from the offset, none at or past the end. Nil, the default, answers `FF FF` as stock Oryx firmware does.
    func storeLayoutRecord(_ bytes: [UInt8]?) { record.withLock { $0 = bytes } }

    /// The next `count` layout reads go unanswered, as if their replies were lost.
    func dropLayoutReads(_ count: Int) { unanswered.withLock { $0 = count } }

    private func reply(toReadAt offset: Int) -> LiveEvent? {
        let dropped = unanswered.withLock { left in
            guard left > 0 else { return false }
            left -= 1
            return true
        }
        guard !dropped else { return nil }
        guard let bytes = record.withLock({ $0 }) else { return .error(0xFF) }
        let part = bytes.indices.contains(offset) ? Array(bytes[offset..<min(offset + 24, bytes.count)]) : []
        return .layoutRecord(LayoutRecordChunk(offset: offset, size: bytes.count, bytes: part))
    }

    var sessionCount: Int { sessions.withLock { $0.count } }

    /// Session `n` (oldest first) is still open: neither ended nor let go by its consumer.
    func isOpen(_ n: Int) -> Bool { n < sessionCount && !closed.withLock { $0.contains(n) } }

    /// The commands each session received, oldest session first.
    var commands: [[KeyboardCommand]] { received.withLock { $0 } }

    /// Sends events on the newest session; `.ended` also ends it.
    func send(_ events: LiveEvent...) {
        guard let session = sessions.withLock({ $0.last }) else { return }
        for event in events {
            session.yield(event)
            if case .ended = event { session.finish() }
        }
    }
}

/// Records flashes; reports an erase step, optionally holds until released, then a write step.
final class FakeFlasher: Flasher {
    struct Call: Sendable {
        var image: FirmwareImage
        var md5: String
        var device: BootloaderDevice
    }
    private let error: FlashError?
    private let holds: Bool
    let isEnabled: Bool
    private let gate: AsyncStream<Void>
    private let opener: AsyncStream<Void>.Continuation
    private let recorded = Mutex<[Call]>([])

    init(error: FlashError? = nil, holds: Bool = false, isEnabled: Bool = true) {
        self.error = error
        self.holds = holds
        self.isEnabled = isEnabled
        (gate, opener) = AsyncStream.makeStream(of: Void.self)
    }

    var calls: [Call] { recorded.withLock { $0 } }

    func release() { opener.yield() }

    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) {
        recorded.withLock { $0.append(Call(image: image, md5: md5, device: device)) }
        progress(FlashProgress(phase: .erasing, done: 1, total: 2))
        if holds {
            for await _ in gate { break }
        }
        progress(FlashProgress(phase: .writing, done: 10, total: 10))
        if let error { throw error }
    }
}

extension KeyboardDevice {
    static func voyager(id: UInt64 = 1, serial: String?) -> Self { Self(id: id, productID: 0x1977, serial: serial) }
}

extension BootloaderDevice {
    static func stm32(id: UInt64 = 9) -> Self { Self(id: id, productID: 0x0791, kind: .stm32, version: 0x0200) }
    static func gd32(id: UInt64 = 9) -> Self { Self(id: id, productID: 0x1791, kind: .gd32, version: 0x0200) }
}

/// Polls `condition`, letting other tasks run, for up to about a second.
@MainActor
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}
