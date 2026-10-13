import SMCKit

public protocol AdapterWriting: Sendable {
    func setAdapter(enabled: Bool) throws
    /// `true` on, `false` off, `nil` for a value Kombucha never writes.
    func currentlyEnabled() throws -> Bool?
}

extension AdapterSwitch: AdapterWriting {}
