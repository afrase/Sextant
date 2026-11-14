import Foundation
import IOKit
import SextantApplication
import SextantDomain

/// Reads the Mac's own pointer settings: the trackpad's acceleration curves from its IOHIDEventService
/// (`HIDAccelCurves`, from the built-in trackpad or a Magic Trackpad), and System Settings' tracking speed, natural
/// scrolling and double-click speed. Read-only, and no permission needed.
public struct SystemPointerReader: SystemPointerSettings {
    private let defaults: @Sendable () -> UserDefaults

    public init(defaults: @escaping @Sendable () -> UserDefaults = { .standard }) { self.defaults = defaults }

    public func current() async -> SystemPointerPreferences {
        let defaults = defaults()
        let standard = SystemPointerPreferences.standard
        return SystemPointerPreferences(
            curves: Self.trackpadCurves() ?? standard.curves,
            trackingSpeed: defaults.object(forKey: "com.apple.trackpad.scaling") as? Double ?? standard.trackingSpeed,
            naturalScrolling: defaults.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? standard.naturalScrolling,
            doubleClickInterval: defaults.object(forKey: "com.apple.mouse.doubleClickThreshold") as? Double
                ?? standard.doubleClickInterval)
    }

    /// The first event service whose pointer acceleration is the trackpad kind and that publishes its curves.
    static func trackpadCurves() -> PointerCurveSet? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let type =
                IORegistryEntryCreateCFProperty(service, "HIDPointerAccelerationType" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            guard type == "HIDTrackpadAcceleration",
                let entries = IORegistryEntryCreateCFProperty(service, "HIDAccelCurves" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [[String: Any]]
            else { continue }
            if let set = curves(from: entries) { return set }
        }
        return nil
    }

    /// The registry's dictionaries of 16.16 fixed-point numbers; nil when none has a gain.
    static func curves(from entries: [[String: Any]]) -> PointerCurveSet? {
        PointerCurveSet(
            entries.compactMap { entry in
                PointerCurveParameters(registryEntry: entry.compactMapValues { $0 as? Int })
            })
    }
}
