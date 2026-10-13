public enum ChargeFlag {
    public static let byteCount = 4

    // CHTE is ui32 with the flag in byte 0; 0x01 stops charging.
    static let allowByte: UInt8 = 0x00
    static let inhibitByte: UInt8 = 0x01

    public static func payload(allow: Bool) -> [UInt8] {
        [allow ? allowByte : inhibitByte, 0, 0, 0]
    }

    /// `true` allowed, `false` inhibited, `nil` for any value this app never writes.
    public static func isAllowed(_ bytes: [UInt8]) -> Bool? {
        guard bytes.count == byteCount, bytes.dropFirst().allSatisfy({ $0 == 0 }) else { return nil }
        switch bytes[0] {
        case allowByte: return true
        case inhibitByte: return false
        default: return nil
        }
    }
}
