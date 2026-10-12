import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// Golden tests: the generator against the sources Oryx generated for real layouts
/// (`docs/research/oryx-examples/sources/*.zip`, unzipped at test time, never copied into the repo): the user's, and
/// four public ones from `$SEXTANT_REFERENCE` when it is set.
///
/// Files are compared after normalising what doesn't reach the firmware: whitespace, `//` comments and the
/// dual-function placeholder keycodes (Oryx picks them at random). Colours compare within Oryx's HSV rounding.
/// Every other difference must be an explicit allowance below, with its reason.
struct QMKGeneratorGoldenTests {
    struct Sample: Sendable, CustomTestStringConvertible {
        var json: String
        var zip: String
        /// Rewrites of Oryx's normalised file (name → pattern → replacement) for intended differences.
        var allowances: [String: [(pattern: String, replacement: String)]] = [:]
        var testDescription: String { zip }
    }

    static let samples: [Sample] = [
        // The 40xJ7M export comes from a narrower query without `navigators`; -full is the same revision with them.
        Sample(json: "my-layout-KlgM7-full.json", zip: "KlgM7-40xJ7M-source.zip"),
        Sample(
            json: "voyager-JRGQm.json", zip: "JRGQm-source.zip",
            allowances: [
                // Oryx enables Repeat Key with no repeat key in the layout (trigger unknown); Sextant only when one is used.
                "rules.mk": [(#"REPEAT_KEY_ENABLE=yes "#, "")]
            ]),
        Sample(
            json: "voyager-e5Rrr.json", zip: "e5Rrr-source.zip",
            allowances: [
                // Oryx built this trackball for an older firmware. The pinned one (ADR 0035) drives the trackball with
                // the `zsa/navigator_trackball` module, which sets its own driver and handles the Navigator keycodes
                // that `zsa/defaults` declares: declaring or handling them again fails the build or doubles a CPI step.
                "rules.mk": [(#" POINTING_DEVICE_DRIVER=navigator_trackball"#, "")],
                "keymap.json": [(#""zsa/oryx","#, #""zsa/oryx","zsa/navigator_trackball","#)],
                "keymap.c": [
                    (#"DRAG_SCROLL,NAVIGATOR_INC_CPI,NAVIGATOR_DEC_CPI,NAVIGATOR_TURBO,NAVIGATOR_AIM\}"#, "}"),
                    (#"case DRAG_SCROLL:.*?pointing_device_set_cpi\(0\);\}return false;"#, ""),
                ],
            ]),
        Sample(json: "voyager-m9dpx.json", zip: "m9dpx-source.zip"),
        Sample(
            json: "voyager-XlrR4.json", zip: "XlrR4-source.zip",
            allowances: [
                // This older Oryx build dropped the step delays (100 ms in the JSON) inside Alt-code macros; Oryx's
                // current output (JRGQm) and Sextant keep them.
                "keymap.c": [(#"\)SS_TAP\(X_KP_"#, ")SS_DELAY(100)SS_TAP(X_KP_")]
            ]),
    ]

    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/research/oryx-examples")

    /// Other people's Oryx samples are kept out of the repo, at the same path under `$SEXTANT_REFERENCE`; nil (unset,
    /// or no such folder) skips the tests that need them.
    static let reference = ProcessInfo.processInfo.environment["SEXTANT_REFERENCE"]
        .map { URL(fileURLWithPath: $0).appending(path: "docs/research/oryx-examples") }
        .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }

    /// The repo's copy if there is one, else the reference folder's.
    static func example(_ name: String) -> URL {
        let own = examples.appending(path: name)
        return FileManager.default.fileExists(atPath: own.path) ? own : (reference ?? examples).appending(path: name)
    }

    @Test(arguments: samples.filter { reference != nil || $0.zip.hasPrefix("KlgM7") })
    func matchesOryx(sample: Sample) throws {
        let layout = try KeyboardLayout(oryxJSON: Data(contentsOf: Self.example(sample.json)))
        let oryx = try Self.unzipSources(Self.example("sources/\(sample.zip)"))
        let serial = try #require(layout.oryx?.serial)
        let generated = try QMKGenerator().generate(layout, identity: FirmwareIdentity(serial: serial))

        // JRGQm's zip has an i18n.h that its keymap.c never includes (it defines a code the layout doesn't use).
        let oryxFiles = Set(oryx.keys).filter { $0 != "i18n.h" || oryx["keymap.c"]?.contains("#include \"i18n.h\"") == true }
        #expect(Set(generated.files.keys) == oryxFiles)
        for name in oryxFiles.sorted() {
            var expected = Self.normalise(oryx[name] ?? "")
            for allowance in sample.allowances[name] ?? [] {
                expected = expected.replacingOccurrences(of: allowance.pattern, with: allowance.replacement, options: .regularExpression)
            }
            Self.expectSame(Self.normalise(generated.files[name] ?? ""), expected, "\(sample.zip) \(name)")
        }
    }

    // MARK: Helpers

    /// The generated sources in an Oryx source zip, by file name.
    static func unzipSources(_ zip: URL) throws -> [String: String] {
        try unzipped(zip) { dir in
            let source = try #require(
                try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first {
                    $0.lastPathComponent.hasSuffix("_source")
                })
            var files: [String: String] = [:]
            for url in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                files[url.lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
            }
            return files
        }
    }

    /// Unzips into a temporary folder (with /usr/bin/unzip), hands it to `body`, then deletes it.
    static func unzipped<T>(_ zip: URL, _ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sextant-golden-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zip.path, "-d", dir.path]
        try unzip.run()
        unzip.waitUntilExit()
        return try body(dir)
    }

    /// Drops comments and whitespace that doesn't separate two identifiers, and the dual-function placeholders.
    static func normalise(_ text: String) -> String {
        let flat = Array(text.replacing(/\/\/[^\n]*/, with: "").replacing(/\s+/, with: " "))
        var out = ""
        for (i, ch) in flat.enumerated() {
            if ch == " " {
                guard i > 0, i < flat.count - 1, isWord(flat[i - 1]), isWord(flat[i + 1]) else { continue }
            }
            out.append(ch)
        }
        return out.replacing(/#define DUAL_FUNC_(\d+) LT\(\d+,\w+\)/) { "#define DUAL_FUNC_\($0.1) LT(_)" } + " "
    }

    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    /// Compares two normalised files, letting HSV colours differ within Oryx's rounding (research 02 §4.6).
    static func expectSame(_ actual: String, _ expected: String, _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let (a, aColors) = extractColors(actual)
        let (e, eColors) = extractColors(expected)
        if a != e {
            let common = zip(a, e).prefix { $0 == $1 }.count
            let from = max(0, common - 120)
            let sextant = a.dropFirst(from).prefix(320), oryx = e.dropFirst(from).prefix(320)
            Issue.record("\(label) differs at \(common):\n  sextant: …\(sextant)\n  oryx:    …\(oryx)", sourceLocation: sourceLocation)
            return
        }
        #expect(aColors.count == eColors.count, "\(label) color count", sourceLocation: sourceLocation)
        for (x, y) in zip(aColors, eColors) {
            let hue = min((x[0] - y[0] + 256) % 256, (y[0] - x[0] + 256) % 256)
            #expect(hue <= 2 && abs(x[1] - y[1]) <= 1 && x[2] == y[2], "\(label) color \(x) vs Oryx \(y)", sourceLocation: sourceLocation)
        }
    }

    /// Replaces every HSV triple (`HSV_h_s_v`, `{h,s,v}`, `sethsv(h,s,v)`) with a marker and returns them in order.
    private static func extractColors(_ text: String) -> (String, [[Int]]) {
        var colors: [[Int]] = []
        let marked = text.replacing(/(HSV_|\{|sethsv\()(\d+)[_,](\d+)[_,](\d+)/) { m in
            colors.append([m.2, m.3, m.4].compactMap { Int($0) })
            return "\(m.1)#"
        }
        return (marked, colors)
    }
}
