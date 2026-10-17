import Foundation

/// A Sextant version, as release tags (`v0.2.0`, `v1.0.0-beta.1`) and the bundle's short version name it (ADR 0063).
/// Ordered by semantic-versioning precedence: numbers first, then a pre-release ranks below its release, its
/// identifiers compared one by one, numeric ones as numbers and below text. Build metadata (`+…`) is ignored.
public struct AppVersion: Comparable, Hashable, Sendable, Codable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    /// The pre-release identifiers, `["beta", "1"]` for `-beta.1`; empty for a release.
    public var prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Reads `1.2.3`, `v1.2.3`, `1.2.3-beta.1` and `1.2.3+build`; a missing minor or patch is 0 (`1.2`). Pre-release
    /// identifiers are ASCII letters, digits and hyphens, and a numeric one has no leading zero (semver 2.0.0). Nil for
    /// anything else.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = rest[..<plus] }
        var pre: [String] = []
        if let dash = rest.firstIndex(of: "-") {
            pre = rest[rest.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !pre.isEmpty, pre.allSatisfy(Self.isIdentifier) else { return nil }
            rest = rest[..<dash]
        }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease: pre)
    }

    /// A pre-release identifier: ASCII alphanumerics and hyphens, a number without a leading zero.
    private static func isIdentifier(_ part: String) -> Bool {
        guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return false }
        return !(part.allSatisfy(\.isNumber) && part.count > 1 && part.hasPrefix("0"))
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// Kept as its text, `"1.0.0-beta.1"`.
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let version = Self(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a version: \(text)"))
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func < (a: Self, b: Self) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        // A release ranks above its pre-releases.
        switch (a.prerelease.isEmpty, b.prerelease.isEmpty) {
        case (true, true), (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (m?, n?): return m < n
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return x < y
            }
        }
        return a.prerelease.count < b.prerelease.count
    }
}
