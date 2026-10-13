/// System and adapter watts as the SMC reports them. A missing, negative, non-finite or implausible value is
/// nil, never a zero, the rule `BatteryHealth.derive` follows.
public struct PowerReadings: Equatable, Sendable {
    public let systemWatts: Double?
    public let adapterWatts: Double?

    public init(systemWatts: Double?, adapterWatts: Double?) {
        self.systemWatts = systemWatts
        self.adapterWatts = adapterWatts
    }

    /// No Mac laptop adapter delivers more than this; a larger reading is a misread key.
    private static let ceilingWatts: Float = 400

    public static func derive(system: Float?, adapter: Float?) -> PowerReadings {
        PowerReadings(systemWatts: watts(system), adapterWatts: watts(adapter))
    }

    private static func watts(_ raw: Float?) -> Double? {
        guard let raw, raw.isFinite, raw >= 0, raw <= ceilingWatts else { return nil }
        // A sign-bit zero would print as "-0.0 W".
        return raw == 0 ? 0 : Double(raw)
    }

    /// The mean of each value over the readings that have it; a value no reading has stays nil.
    public static func average(_ readings: [PowerReadings]) -> PowerReadings {
        PowerReadings(systemWatts: mean(readings.compactMap(\.systemWatts)),
                      adapterWatts: mean(readings.compactMap(\.adapterWatts)))
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
