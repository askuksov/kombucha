import Foundation

public final class AdapterSwitch: @unchecked Sendable {
    private let connection: SMCConnection
    private let lock = NSLock()

    private init(connection: SMCConnection) {
        self.connection = connection
    }

    /// Opens AppleSMC and confirms CHIE exists and is one byte wide. Reads only; without the key it throws
    /// `keyNotFound`.
    public static func arm() throws -> AdapterSwitch {
        let connection = try SMCConnection()
        let size = try connection.keySize(SMCKey.adapterInhibit)
        guard size == AdapterFlag.byteCount else {
            throw SMCError.unexpectedSize(expected: AdapterFlag.byteCount, actual: size)
        }
        return AdapterSwitch(connection: connection)
    }

    /// `true` on, `false` off, `nil` for a value this app never writes.
    public func currentlyEnabled() throws -> Bool? {
        try lock.withLock { AdapterFlag.isEnabled(try connection.read(SMCKey.adapterInhibit)) }
    }

    /// Needs root. Succeeds only when the read-back equals what was written.
    public func setAdapter(enabled: Bool) throws {
        try lock.withLock {
            let wrote = AdapterFlag.payload(enabled: enabled)
            try connection.write(SMCKey.adapterInhibit, bytes: wrote)
            let read = try connection.read(SMCKey.adapterInhibit)
            guard read == wrote else { throw SMCError.writeNotApplied(wrote: wrote, read: read) }
        }
    }
}
