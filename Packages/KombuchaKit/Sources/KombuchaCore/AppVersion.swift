import Foundation

/// A release number, `major.minor.patch`. The build number is not part of it.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// `0.2.0` or `v0.2.0`. Anything else is nil: a pre-release suffix, a word, spaces, a sign, non-ASCII digits.
    public init?(_ text: String) {
        var digits = Substring(text)
        if digits.hasPrefix("v") { digits = digits.dropFirst() }
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.map { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
            return Int(part)
        }
        guard let major = numbers[0], let minor = numbers[1], let patch = numbers[2] else { return nil }
        self.init(major, minor, patch)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// The page of this release on GitHub. Built here, never taken from a response.
    public var releasePage: URL {
        URL(string: "https://github.com/askuksov/kombucha/releases/tag/v\(description)")!
    }
}
