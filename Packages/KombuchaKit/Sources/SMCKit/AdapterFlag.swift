public enum AdapterFlag {
    public static let byteCount = 1

    // CHIE is hex_ with one byte; 0x08 switches the adapter off, 0x00 back on.
    static let enabledByte: UInt8 = 0x00
    static let disabledByte: UInt8 = 0x08

    public static func payload(enabled: Bool) -> [UInt8] {
        [enabled ? enabledByte : disabledByte]
    }

    /// `true` on, `false` off, `nil` for any value this app never writes.
    public static func isEnabled(_ bytes: [UInt8]) -> Bool? {
        guard bytes.count == byteCount else { return nil }
        switch bytes[0] {
        case enabledByte: return true
        case disabledByte: return false
        default: return nil
        }
    }
}
