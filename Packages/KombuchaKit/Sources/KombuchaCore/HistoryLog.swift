import Foundation

public enum HistoryRange: CaseIterable, Sendable {
    case week, month

    public var span: TimeInterval { self == .week ? 7 * 86_400 : 30 * 86_400 }
    /// 15 minutes for a week, one hour for a month: about 700 buckets either way.
    public var bucket: TimeInterval { self == .week ? 900 : 3_600 }
}

/// One slot of the chart.
public struct HistoryBucket: Equatable, Sendable {
    /// The slot's number since the epoch; two slots are neighbours when their indexes differ by one.
    public let index: Int
    public let start: Date
    /// The last level in the slot.
    public let level: Int
    public let charging: Bool
    public let resting: Bool
    /// True only when every point of the slot was on the adapter; the chart's "On battery" lane is its opposite.
    public let onAC: Bool
    public let peakTemperatureCelsius: Double?
    /// Grows across a missing slot, so the chart draws a gap instead of a line over time Kombucha was not running.
    public let segment: Int

    public init(index: Int, start: Date, level: Int, charging: Bool, resting: Bool, onAC: Bool,
                peakTemperatureCelsius: Double?, segment: Int) {
        self.index = index
        self.start = start
        self.level = level
        self.charging = charging
        self.resting = resting
        self.onAC = onAC
        self.peakTemperatureCelsius = peakTemperatureCelsius
        self.segment = segment
    }
}

/// The records of the history file, loaded. Value type: the app builds one to draw the chart and to prune.
public struct HistoryLog: Equatable, Sendable {
    public static let retention: TimeInterval = 30 * 86_400

    public let points: [HistoryPoint]
    public let healthPoints: [HealthPoint]
    public let baseline: Int?

    public init(records: [HistoryRecord] = []) {
        var points: [HistoryPoint] = []
        var health: [HealthPoint] = []
        var baseline: Int?
        for record in records {
            switch record {
            case .point(let point): points.append(point)
            case .health(let value): health.append(value)
            case .baseline(let value): baseline = value
            }
        }
        self.points = points.sorted { $0.time < $1.time }
        self.healthPoints = health.sorted { $0.day < $1.day }
        self.baseline = baseline
    }

    /// The baseline first: records appended later override it when the file is read back, in order.
    public var records: [HistoryRecord] {
        (baseline.map { [HistoryRecord.baseline($0)] } ?? [])
            + healthPoints.map(HistoryRecord.health)
            + points.map(HistoryRecord.point)
    }

    public func pruned(now: Date) -> HistoryLog {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var records = points.filter { $0.time >= cutoff }.map(HistoryRecord.point)
        records += healthPoints.filter { $0.day >= cutoff }.map(HistoryRecord.health)
        if let baseline { records.insert(.baseline(baseline), at: 0) }
        return HistoryLog(records: records)
    }

    public func buckets(_ range: HistoryRange, now: Date) -> [HistoryBucket] {
        let size = range.bucket
        let from = now.addingTimeInterval(-range.span)
        let inWindow = points.filter { $0.time >= from && $0.time <= now }
        let groups = Dictionary(grouping: inWindow) { Int(($0.time.timeIntervalSince1970 / size).rounded(.down)) }
        var segment = 0
        var previous: Int?
        return groups.sorted { $0.key < $1.key }.compactMap { index, items in
            guard let last = items.last else { return nil }
            if let previous, index != previous + 1 { segment += 1 }
            previous = index
            return HistoryBucket(index: index,
                                 start: Date(timeIntervalSince1970: Double(index) * size),
                                 level: last.level,
                                 charging: items.contains { $0.charging },
                                 resting: items.contains { $0.resting },
                                 onAC: items.allSatisfy(\.onAC),
                                 peakTemperatureCelsius: items.compactMap(\.temperatureCelsius).max(),
                                 segment: segment)
        }
    }
}
