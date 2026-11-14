// Read-only Navigator probe. Never writes, sets or gets reports on the device:
// it only enumerates, reads the cached report descriptor, and listens to input reports.
// Usage: swift probe.swift [listen-seconds]
import Foundation
import IOKit.hid

let zsaVendor = 0x3297
let listenSeconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 0 : 0
// The only write this probe can make: feature report 4 (input mode) = 3 (PTP), on the digitizer interface only.
let setPTP = CommandLine.arguments.contains("--set-ptp")

func prop(_ d: IOHIDDevice, _ k: String) -> Any? { IOHIDDeviceGetProperty(d, k as CFString) }
func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

// Minimal HID report descriptor pretty-printer.
func describe(_ d: [UInt8]) {
    let mainTags: [UInt8: String] = [0x8: "Input", 0x9: "Output", 0xB: "Feature", 0xA: "Collection", 0xC: "End Collection"]
    let globalTags: [UInt8: String] = [0x0: "Usage Page", 0x1: "Logical Min", 0x2: "Logical Max", 0x3: "Physical Min", 0x4: "Physical Max",
                                       0x5: "Unit Exponent", 0x6: "Unit", 0x7: "Report Size", 0x8: "Report ID", 0x9: "Report Count"]
    let localTags: [UInt8: String] = [0x0: "Usage", 0x1: "Usage Min", 0x2: "Usage Max"]
    var i = 0, depth = 0
    while i < d.count {
        let b = d[i]
        var size = Int(b & 0x3); if size == 3 { size = 4 }
        let type = (b >> 2) & 0x3, tag = b >> 4
        var v: UInt32 = 0
        for j in 0..<size where i + 1 + j < d.count { v |= UInt32(d[i + 1 + j]) << (8 * j) }
        let name: String
        switch type {
        case 0: name = mainTags[tag] ?? "Main?\(tag)"
        case 1: name = globalTags[tag] ?? "Global?\(tag)"
        case 2: name = localTags[tag] ?? "Local?\(tag)"
        default: name = "Reserved"
        }
        if name == "End Collection" { depth -= 1 }
        print(String(repeating: "  ", count: max(depth, 0) + 2) + name + (size > 0 ? String(format: " 0x%X", v) : ""))
        if name == "Collection" { depth += 1 }
        i += 1 + size
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: zsaVendor] as CFDictionary)
let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
if devices.isEmpty { print("No ZSA HID devices found."); exit(1) }

var listenTargets: [IOHIDDevice] = []
for d in devices.sorted(by: { (prop($0, kIOHIDPrimaryUsagePageKey) as? Int ?? 0) < (prop($1, kIOHIDPrimaryUsagePageKey) as? Int ?? 0) }) {
    let page = prop(d, kIOHIDPrimaryUsagePageKey) as? Int ?? -1
    let usage = prop(d, kIOHIDPrimaryUsageKey) as? Int ?? -1
    print("== \(prop(d, kIOHIDProductKey) ?? "?") PID=\(String(format: "0x%04X", prop(d, kIOHIDProductIDKey) as? Int ?? 0)) primary=\(String(format: "0x%02X/0x%02X", page, usage))")
    print("   usages: \((prop(d, kIOHIDDeviceUsagePairsKey) as? [[String: Int]] ?? []).map { String(format: "0x%02X/0x%02X", $0[kIOHIDDeviceUsagePageKey] ?? 0, $0[kIOHIDDeviceUsageKey] ?? 0) }.joined(separator: ", "))")
    print("   max input=\(prop(d, kIOHIDMaxInputReportSizeKey) ?? "?") feature=\(prop(d, kIOHIDMaxFeatureReportSizeKey) ?? "?") output=\(prop(d, kIOHIDMaxOutputReportSizeKey) ?? "?")")
    if let desc = prop(d, kIOHIDReportDescriptorKey) as? Data {
        print("   descriptor (\(desc.count) bytes):")
        describe([UInt8](desc))
    }
    let pairs = prop(d, kIOHIDDeviceUsagePairsKey) as? [[String: Int]] ?? []
    // Listen only on digitizer (0x0D) or mouse/pointer interfaces; never on the keyboard or raw-HID ones.
    let isPointer = pairs.contains { ($0[kIOHIDDeviceUsagePageKey] == 0x0D) || ($0[kIOHIDDeviceUsagePageKey] == 0x01 && [0x01, 0x02].contains($0[kIOHIDDeviceUsageKey])) }
    let isKeyboard = pairs.contains { $0[kIOHIDDeviceUsagePageKey] == 0x01 && $0[kIOHIDDeviceUsageKey] == 0x06 }
    if isPointer && !isKeyboard { listenTargets.append(d) }
}

guard listenSeconds > 0 else { exit(0) }
print("\nListening on \(listenTargets.count) pointer/digitizer interface(s) for \(listenSeconds)s. Touch the pad: one finger, two fingers, taps, scrolls.")

let start = Date()
final class Box { var buffer: UnsafeMutablePointer<UInt8>; init(_ n: Int) { buffer = .allocate(capacity: n) } }
var boxes: [Box] = []
for d in listenTargets {
    let r = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
    if r != kIOReturnSuccess { print(String(format: "open failed 0x%08X (Input Monitoring permission?)", r)); continue }
    let n = prop(d, kIOHIDMaxInputReportSizeKey) as? Int ?? 64
    let box = Box(n); boxes.append(box)
    let page = prop(d, kIOHIDPrimaryUsagePageKey) as? Int ?? -1
    if setPTP && page == 0x0D && (prop(d, kIOHIDPrimaryUsageKey) as? Int) == 0x05 {
        let bytes: [UInt8] = [0x04, 0x03]  // report ID 4, input mode 3 (PTP)
        let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 4, bytes, bytes.count)
        print(String(format: "SET_REPORT feature 4 = 3 -> 0x%08X", r))
    }
    let ctx = UnsafeMutableRawPointer(bitPattern: page + 1)
    IOHIDDeviceRegisterInputReportWithTimeStampCallback(d, box.buffer, n, { ctx, _, _, _, reportID, report, length, ts in
        let page = Int(bitPattern: ctx) - 1
        let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
        var line = String(format: "%.3f page=0x%02X id=%d len=%d  ", Date().timeIntervalSince(start), page, reportID, length) + hex(bytes)
        // Decode ZSA's PTP layout (navigator_trackpad_ptp.c): id 0x01, fingers at offsets 1 and 7.
        if reportID == 1 && length >= 13 {
            for (f, o) in [1, 7].enumerated() {
                let tip = bytes[o] & 0x02 != 0, conf = bytes[o] & 0x01 != 0
                let cid = bytes[o + 1] & 0x07
                let x = Int(bytes[o + 2]) | Int(bytes[o + 3]) << 8, y = Int(bytes[o + 4]) | Int(bytes[o + 5]) << 8
                line += "  | f\(f) id=\(cid) tip=\(tip ? 1 : 0) conf=\(conf ? 1 : 0) x=\(x) y=\(y)"
            }
            if length >= 16 {
                let scan = Int(bytes[13]) | Int(bytes[14]) << 8
                line += "  | scan=\(scan) count=\(bytes[15] & 0x0F) buttons=\((bytes[15] >> 4) & 0x07)"
            }
        }
        print(line)
    }, ctx)
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
}
CFRunLoopRunInMode(.defaultMode, listenSeconds, false)
for d in listenTargets { IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone)) }
