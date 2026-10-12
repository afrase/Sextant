import Foundation
import SextantDomain

/// Files under `docs/research/oryx-examples/` (real Oryx JSON; never copied into the test bundle).
enum Fixtures {
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/research/oryx-examples")

    /// Other people's Oryx samples are kept out of the repo, at the same path under `$SEXTANT_REFERENCE`; nil (unset,
    /// or no such folder) skips the tests that need them.
    static let reference = ProcessInfo.processInfo.environment["SEXTANT_REFERENCE"]
        .map { URL(fileURLWithPath: $0).appending(path: "docs/research/oryx-examples") }
        .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }

    static let userLayoutFile = "my-layout-KlgM7-40xJ7M.json"
    static let allLayoutFiles =
        ["my-layout-KlgM7-40xJ7M.json", "my-layout-KlgM7-full.json"]
        + (reference == nil
            ? []
            : ["voyager-default.json", "voyager-e5Rrr.json", "voyager-JRGQm.json", "voyager-m9dpx.json", "voyager-XlrR4.json"])

    /// The repo's copy if there is one, else the reference folder's.
    static func url(_ name: String) -> URL {
        let own = examples.appending(path: name)
        return FileManager.default.fileExists(atPath: own.path) ? own : (reference ?? examples).appending(path: name)
    }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }
    static func layout(_ name: String = userLayoutFile) throws -> KeyboardLayout { try KeyboardLayout(oryxJSON: data(name)) }
}
