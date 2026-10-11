import Foundation
import SextantDomain

/// Files under `docs/research/oryx-examples/` (real Oryx JSON; never copied into the test bundle).
enum Fixtures {
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/research/oryx-examples")

    static let userLayoutFile = "my-layout-KlgM7-40xJ7M.json"
    static let allLayoutFiles = [
        "my-layout-KlgM7-40xJ7M.json", "my-layout-KlgM7-full.json", "voyager-default.json",
        "voyager-e5Rrr.json", "voyager-JRGQm.json", "voyager-m9dpx.json", "voyager-XlrR4.json",
    ]

    static func data(_ name: String) throws -> Data { try Data(contentsOf: examples.appending(path: name)) }
    static func layout(_ name: String = userLayoutFile) throws -> KeyboardLayout { try KeyboardLayout(oryxJSON: data(name)) }
}
