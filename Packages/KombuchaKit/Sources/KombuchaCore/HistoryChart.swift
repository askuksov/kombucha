import Foundation

/// A state the chart's lane can show, in the order the lane and the detail row list them.
public enum HistoryLane: CaseIterable, Hashable, Sendable {
    case charging, resting, onBattery

    func holds(_ bucket: HistoryBucket) -> Bool {
        switch self {
        case .charging: bucket.charging
        case .resting: bucket.resting
        case .onBattery: !bucket.onAC
        }
    }
}

/// A stretch of time: from the start of its first slot to the end of its last.
public struct HistoryRun: Equatable, Sendable, Identifiable {
    public let start: Date
    public let end: Date
    public var id: Date { start }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// What the pointer reports for one slot of the chart.
public struct HistoryDetail: Equatable, Sendable {
    public let start: Date
    /// Nil for a slot with nothing recorded.
    public let level: Int?
    public let lanes: [HistoryLane]
    public let peakTemperatureCelsius: Double?

    public init(start: Date, level: Int?, lanes: [HistoryLane], peakTemperatureCelsius: Double?) {
        self.start = start
        self.level = level
        self.lanes = lanes
        self.peakTemperatureCelsius = peakTemperatureCelsius
    }
}

/// The Battery Rest share of what was recorded, and how much that was.
public struct HistorySummary: Equatable, Sendable {
    public let restedPercent: Int
    public let recorded: TimeInterval

    public init(restedPercent: Int, recorded: TimeInterval) {
        self.restedPercent = restedPercent
        self.recorded = recorded
    }
}

/// Everything the History chart draws, computed once from the buckets. No view code, no clock.
public struct HistoryChart: Equatable, Sendable {
    /// A segment shorter than this many buckets gets dots, so it stays visible.
    public static let shortSegment = 8

    public let range: HistoryRange
    public let periodStart: Date
    public let periodEnd: Date
    public let buckets: [HistoryBucket]
    /// The current Stop and Resume; nil while Battery Protection is off or not yet known.
    public let limit: Thresholds?
    /// Every stretch of the period with nothing recorded, the start and the end of the period included.
    public let gaps: [HistoryRun]
    public let shortSegmentBuckets: [HistoryBucket]
    /// The bottom of the level axis; the top is always 100.
    public let yFloor: Int
    public let yTicks: [Int]
    /// Nil when nothing was recorded.
    public let summary: HistorySummary?
    private let laneRuns: [HistoryLane: [HistoryRun]]

    public init(buckets: [HistoryBucket], range: HistoryRange, now: Date, limit: Thresholds?) {
        let size = range.bucket
        let from = now.addingTimeInterval(-range.span)
        self.range = range
        self.periodStart = from
        self.periodEnd = now
        self.buckets = buckets
        self.limit = limit
        var runs: [HistoryLane: [HistoryRun]] = [:]
        for lane in HistoryLane.allCases {
            runs[lane] = Self.runs(in: buckets, size: size) { lane.holds($0) }
        }
        self.laneRuns = runs
        self.gaps = Self.gaps(in: buckets, size: size, from: from, to: now)
        let sizes = Dictionary(grouping: buckets, by: \.segment).mapValues(\.count)
        self.shortSegmentBuckets = buckets.filter { sizes[$0.segment, default: 0] < Self.shortSegment }
        let floor = Self.floor(lowest: buckets.map(\.level).min(), limit: limit)
        self.yFloor = floor
        self.yTicks = Self.ticks(floor: floor, limit: limit)
        let rested = buckets.filter(\.resting).count
        self.summary = buckets.isEmpty ? nil : HistorySummary(
            restedPercent: Int((Double(rested) / Double(buckets.count) * 100).rounded()),
            recorded: Double(buckets.count) * size)
    }

    public func runs(for lane: HistoryLane) -> [HistoryRun] { laneRuns[lane] ?? [] }

    /// The slot that contains `date`: its bucket, or "nothing recorded"; nil outside the period.
    public func detail(at date: Date) -> HistoryDetail? {
        guard date >= periodStart, date <= periodEnd else { return nil }
        let size = range.bucket
        let index = Int((date.timeIntervalSince1970 / size).rounded(.down))
        if let bucket = buckets.first(where: { $0.index == index }) {
            return HistoryDetail(start: bucket.start, level: bucket.level,
                                 lanes: HistoryLane.allCases.filter { $0.holds(bucket) },
                                 peakTemperatureCelsius: bucket.peakTemperatureCelsius)
        }
        return HistoryDetail(start: Date(timeIntervalSince1970: Double(index) * size), level: nil, lanes: [],
                             peakTemperatureCelsius: nil)
    }

    /// The largest multiple of 10 at least 3 below the lowest level and, with a limit, at most Resume minus 10.
    /// An empty period counts as a lowest level of 63. Never below 0.
    private static func floor(lowest: Int?, limit: Thresholds?) -> Int {
        var ceiling = (lowest ?? 63) - 3
        if let limit { ceiling = min(ceiling, limit.lower - 10) }
        return max(0, ceiling / 10 * 10)
    }

    /// The floor, every 20 above it while that stays clear of Resume, then Resume, Stop and 100.
    private static func ticks(floor: Int, limit: Thresholds?) -> [Int] {
        var result: Set<Int> = [floor, 100]
        var value = floor + 20
        if let limit {
            while value <= limit.lower - 15 {
                result.insert(value)
                value += 20
            }
            result.insert(limit.lower)
            result.insert(limit.upper)
        } else {
            while value < 100 {
                result.insert(value)
                value += 20
            }
        }
        return result.sorted()
    }

    /// Maximal runs of consecutive buckets that hold one flag.
    private static func runs(in buckets: [HistoryBucket], size: TimeInterval,
                             where holds: (HistoryBucket) -> Bool) -> [HistoryRun] {
        var result: [HistoryRun] = []
        var first: HistoryBucket?
        var last: HistoryBucket?
        func close() {
            if let first, let last {
                result.append(HistoryRun(start: first.start, end: last.start.addingTimeInterval(size)))
            }
            first = nil
            last = nil
        }
        for bucket in buckets {
            guard holds(bucket) else {
                close()
                continue
            }
            if let previous = last, bucket.index == previous.index + 1 {
                last = bucket
            } else {
                close()
                first = bucket
                last = bucket
            }
        }
        close()
        return result
    }

    /// Maximal runs of grid slots with no bucket, clipped to the period; a run with no length is dropped.
    private static func gaps(in buckets: [HistoryBucket], size: TimeInterval,
                             from periodStart: Date, to periodEnd: Date) -> [HistoryRun] {
        let firstIndex = Int((periodStart.timeIntervalSince1970 / size).rounded(.down))
        let lastIndex = Int((periodEnd.timeIntervalSince1970 / size).rounded(.down))
        let present = Set(buckets.map(\.index))
        var result: [HistoryRun] = []
        var open: Int?
        func close(before index: Int) {
            guard let from = open else { return }
            open = nil
            let start = max(Date(timeIntervalSince1970: Double(from) * size), periodStart)
            let end = min(Date(timeIntervalSince1970: Double(index) * size), periodEnd)
            if end > start { result.append(HistoryRun(start: start, end: end)) }
        }
        for index in firstIndex...lastIndex {
            if present.contains(index) {
                close(before: index)
            } else if open == nil {
                open = index
            }
        }
        close(before: lastIndex + 1)
        return result
    }
}
