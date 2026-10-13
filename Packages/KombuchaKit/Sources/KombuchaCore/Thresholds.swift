/// The charge range: a stop threshold and a resume threshold, at least five points apart.
public struct Thresholds: Equatable, Sendable {
    public static let lowerRange = 40...85
    public static let upperRange = 55...95
    public static let minimumGap = 5
    public static let standard = Thresholds(lower: 75, upper: 80)

    public private(set) var lower: Int
    public private(set) var upper: Int

    private init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = upper
    }

    /// Total over any pair. The stop threshold is clamped first: clamping the resume
    /// threshold first can produce an inverted range.
    public static func normalized(lower: Int, upper: Int) -> Thresholds {
        let upper = clamped(upper, low: upperRange.lowerBound, high: upperRange.upperBound)
        return Thresholds(lower: clamped(lower, low: lowerRange.lowerBound, high: lowerCap(upper: upper)), upper: upper)
    }

    public func movingLower(to value: Int) -> Thresholds {
        Thresholds(lower: Self.clamped(value, low: Self.lowerRange.lowerBound, high: Self.lowerCap(upper: upper)), upper: upper)
    }

    public func movingUpper(to value: Int) -> Thresholds {
        Thresholds(lower: lower, upper: Self.clamped(value, low: Self.upperFloor(lower: lower), high: Self.upperRange.upperBound))
    }

    private static func lowerCap(upper: Int) -> Int { min(lowerRange.upperBound, upper - minimumGap) }

    private static func upperFloor(lower: Int) -> Int { max(upperRange.lowerBound, lower + minimumGap) }

    private static func clamped(_ value: Int, low: Int, high: Int) -> Int { min(max(value, low), high) }
}
