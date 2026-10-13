/// The fixed marks of Heat Protection (FR-HEAT-1). The heat alert of `BatteryWatch` uses the same numbers.
public enum HeatPolicy {
    /// At or above this the charge is held off.
    public static let pauseCelsius = 40.0
    /// At or below this the charge is allowed again.
    public static let resumeCelsius = 37.0
    /// A reading outside this range is not a battery temperature and is ignored.
    static let plausible: ClosedRange<Double> = -40...150
}
