import Foundation
import SextantApplication
import SextantDomain

// Skeletons; the device slice replaces this file with IOKitDeviceWatcher, RawHIDLink and DFUFlasher.

/// Read-only USB presence (IOKit matching notifications).
public struct IOKitDeviceWatcher: DeviceWatcher {
    public init() {}
    public func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> { AsyncStream { $0.finish() } }
}
