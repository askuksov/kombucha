import Foundation
import Security

public struct CallerVerdict: Equatable, Sendable {
    public let accepted: Bool
    public let path: String
    public let status: OSStatus
}

public enum CallerVerifier {
    public static func compile(_ text: String) -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// Looks the caller up by pid, which can be reused: good for logging, not a security boundary.
    public static func check(pid: pid_t, against requirement: SecRequirement) -> CallerVerdict {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        var status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let code else {
            return CallerVerdict(accepted: false, path: "pid \(pid)", status: status)
        }
        status = SecCodeCheckValidity(code, [], requirement)
        return CallerVerdict(accepted: status == errSecSuccess, path: path(of: code) ?? "pid \(pid)", status: status)
    }

    static func path(of code: SecCode) -> String? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var url: CFURL?
        guard SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url else { return nil }
        return (url as URL).path
    }
}
