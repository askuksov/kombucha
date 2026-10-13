import Foundation

/// What the recorder writes and when. Small on purpose: the app keeps this in memory, never the whole log.
public struct HistoryCursor: Equatable, Sendable {
    /// A sample is due this long after the last one, so a pass that lands a little early is not lost to the 60 s tick.
    public static let spacing: TimeInterval = 50
    /// An unchanged battery still writes a point this often, so a held level draws a line and not a gap.
    public static let heartbeat: TimeInterval = 600

    private var lastAttempt: Date?
    private var lastPoint: HistoryPoint?
    private var lastHealthDay: Date?

    public init() {}

    /// Continues from what the file already holds; `lastAttempt` stays, it belongs to this run.
    public mutating func resume(from log: HistoryLog) {
        lastPoint = log.points.last
        lastHealthDay = log.healthPoints.last?.day
    }

    /// True, and remembered, when a sample should be taken now. A clock that went backwards counts as due.
    public mutating func isDue(at now: Date) -> Bool {
        if let lastAttempt {
            let gap = now.timeIntervalSince(lastAttempt)
            if gap >= 0, gap < Self.spacing { return false }
        }
        lastAttempt = now
        return true
    }

    /// True, and remembered, when the point should be written.
    public mutating func accept(_ point: HistoryPoint) -> Bool {
        if let last = lastPoint {
            let age = point.time.timeIntervalSince(last.time)
            if point.sameState(as: last), age >= 0, age < Self.heartbeat { return false }
        }
        lastPoint = point
        return true
    }

    /// One health point per local day; a day different from the last one is accepted, so a clock that was wrong and got corrected cannot block recording.
    public mutating func acceptHealth(day: Date) -> Bool {
        if let lastHealthDay, day == lastHealthDay { return false }
        lastHealthDay = day
        return true
    }
}
