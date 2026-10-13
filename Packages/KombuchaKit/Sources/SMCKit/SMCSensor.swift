/// Read-only access to the SMC's power sensors. Nothing here writes; the charge key stays the helper's alone.
public enum SMCSensor {
    /// Total system power in watts.
    public static let systemPower = SMCKey.code("PSTR")
    /// Power drawn from the adapter in watts.
    public static let adapterPower = SMCKey.code("PDTR")

    /// Reads each key as a four-byte float. A key that is absent, of another size or unreadable is left out of
    /// the result; only an SMC service that will not open throws.
    public static func readFloats(_ keys: [UInt32]) throws -> [UInt32: Float] {
        let connection = try SMCConnection()
        var values: [UInt32: Float] = [:]
        for key in keys {
            guard let bytes = try? connection.read(key), let value = decodeFloat(bytes) else { continue }
            values[key] = value
        }
        return values
    }

    /// The SMC's `flt ` type on Apple silicon: four bytes, little-endian.
    public static func decodeFloat(_ bytes: [UInt8]) -> Float? {
        guard bytes.count == 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return Float(bitPattern: bits)
    }
}
