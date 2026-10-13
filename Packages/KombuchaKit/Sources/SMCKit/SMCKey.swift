public enum SMCKey {
    public static let chargeInhibit = code("CHTE")
    /// Switches the adapter off while the cable stays in. Kombucha's alone: macOS does not write it.
    public static let adapterInhibit = code("CHIE")

    public static func code(_ name: String) -> UInt32 {
        let bytes = Array(name.utf8)
        precondition(bytes.count == 4, "an SMC key is four ASCII characters")
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
