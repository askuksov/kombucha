import Foundation
import Security

/// Whether the executable on disk is still the one this process started from.
public struct CodeIdentity: Sendable {
    private let executablePath: String
    private let startupHash: Data?

    /// Call first thing at startup, while the file on disk is the code that runs.
    public init(executablePath: String) {
        self.executablePath = executablePath
        startupHash = Self.diskHash(at: executablePath)
    }

    /// False when the startup read failed; `matchesDisk()` is then always false.
    public var knowsStartupCode: Bool { startupHash != nil }

    /// False as well when anything cannot be read: a helper that cannot tell should make way.
    public func matchesDisk() -> Bool {
        guard let startupHash, Self.runningCodeIsValid(), let current = Self.diskHash(at: executablePath) else {
            return false
        }
        return current == startupHash
    }

    // The same validity the app's per-message check needs from this process.
    static func runningCodeIsValid() -> Bool {
        var running: SecCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running else { return false }
        return SecCodeCheckValidity(running, [], nil) == errSecSuccess
    }

    static func diskHash(at path: String) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }
        return information[kSecCodeInfoUnique as String] as? Data
    }
}
