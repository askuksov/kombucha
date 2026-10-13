import Foundation

public final class ChargeSwitch: @unchecked Sendable {
    private let connection: SMCConnection
    private let lock = NSLock()

    private init(connection: SMCConnection) {
        self.connection = connection
    }

    /// Opens AppleSMC and confirms CHTE exists and is four bytes wide. Reads only.
    public static func arm() throws -> ChargeSwitch {
        let connection = try SMCConnection()
        let size = try connection.keySize(SMCKey.chargeInhibit)
        guard size == ChargeFlag.byteCount else {
            throw SMCError.unexpectedSize(expected: ChargeFlag.byteCount, actual: size)
        }
        return ChargeSwitch(connection: connection)
    }

    public func currentBytes() throws -> [UInt8] {
        try lock.withLock { try connection.read(SMCKey.chargeInhibit) }
    }

    /// Needs root. Succeeds only when the read-back equals what was written.
    public func setCharging(allow: Bool) throws {
        try lock.withLock {
            let wrote = ChargeFlag.payload(allow: allow)
            try connection.write(SMCKey.chargeInhibit, bytes: wrote)
            let read = try connection.read(SMCKey.chargeInhibit)
            guard read == wrote else { throw SMCError.writeNotApplied(wrote: wrote, read: read) }
        }
    }
}
