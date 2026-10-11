import Foundation
import SextantApplication
import SextantDomain

/// Reads `qmk compile` output line by line: strips colour, reports progress, collects compiler diagnostics (mapping
/// `keymap.c` lines to keys) and the image size.
struct BuildLog {
    /// About how many units a Voyager build compiles (164–180 in Oryx's build logs); a guess until the build ends.
    static let expectedUnits = 170

    let sourceMap: [Int: KeyRef]
    private(set) var lines: [String] = []
    private(set) var diagnostics: [Diagnostic] = []
    /// Image bytes from the "Size after" report.
    private(set) var usedBytes: Int?
    /// Bytes the linker said the image overflows flash by.
    private(set) var overflow: Int?
    private var compiled = 0
    private var inSizeReport = false

    init(sourceMap: [Int: KeyRef]) { self.sourceMap = sourceMap }

    /// Takes one raw output line and returns the events it produces.
    mutating func consume(_ raw: String) -> [BuildEvent] {
        let line = raw.replacing(/\x1B\[[0-9;]*[A-Za-z]/, with: "")
        lines.append(line)
        var events: [BuildEvent] = [.output(line)]
        if let m = line.firstMatch(of: /^Compiling: (\S+)/) {
            compiled += 1
            let file = String(m.1.split(separator: "/").last ?? m.1)
            events.append(.compiling(file: file, done: compiled, total: max(compiled, Self.expectedUnits)))
        } else if line.hasPrefix("Linking:") {
            events.append(.linking)
        }
        if let d = Self.diagnostic(line, sourceMap: sourceMap) { diagnostics.append(d) }
        if let m = line.firstMatch(of: /region .flash0. overflowed by (\d+) bytes/) { overflow = Int(m.1) }  // not RAM
        if line.hasPrefix("Size after") { inSizeReport = true }
        // `arm-none-eabi-size` columns: text, data, bss, dec, hex, filename.
        if inSizeReport, let m = line.wholeMatch(of: /\s*\d+\s+\d+\s+\d+\s+(\d+)\s+[0-9a-f]+\s+\S+/) {
            usedBytes = Int(m.1)
            inSizeReport = false
        }
        return events
    }

    /// Parses `file:line:col: error|warning|note: message`.
    static func diagnostic(_ line: String, sourceMap: [Int: KeyRef]) -> Diagnostic? {
        guard let m = line.wholeMatch(of: /(.+?):(\d+):(\d+): (fatal error|error|warning|note): (.*)/),
            let lineNumber = Int(m.2), let column = Int(m.3)
        else { return nil }
        let file = String(m.1)
        let severity: Diagnostic.Severity = m.4 == "warning" ? .warning : m.4 == "note" ? .note : .error
        let key = file.hasSuffix("keymap.c") ? sourceMap[lineNumber] : nil
        return Diagnostic(file: file, line: lineNumber, column: column, severity: severity, message: String(m.5), key: key)
    }
}
