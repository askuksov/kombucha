import Foundation

/// A battery event worth a notification. The app turns it into words; the rules never touch text.
public enum BatteryAlert: Equatable, Sendable {
    case healthDropped(from: Int, to: Int)
    case overheating(limitCelsius: Double)
    case limitNotHeld(Thresholds)
}

/// The rules of FR-NOT-5..7. The recorder calls `observe` on every sample. Each alert fires once per event; an
/// event that happens while the switch is off is consumed silently, so switching on later replays nothing.
public struct BatteryWatch: Sendable {
    public static let heatLimit = HeatPolicy.pauseCelsius
    public static let heatRearm = HeatPolicy.resumeCelsius
    public static let heatDuration: TimeInterval = 300
    /// The charger can overshoot Stop by a reading; this many points above Stop is a failure.
    public static let limitSlack = 2.0
    public static let limitDuration: TimeInterval = 300
    /// Samples further apart than this (sleep, a stalled engine) do not count as one stretch of time.
    public static let sampleGap: TimeInterval = 180

    private struct Episode: Sendable {
        var began: Date?
        var fired = false

        /// True once, when `duration` has passed since the episode began.
        mutating func advance(now: Date, duration: TimeInterval) -> Bool {
            let start = began ?? now
            began = start
            guard !fired, now.timeIntervalSince(start) >= duration else { return false }
            fired = true
            return true
        }
    }

    /// The capacity the next drop is measured against. It starts at the first value seen and only moves down, so
    /// a reading that wobbles by one point does not announce itself twice.
    public private(set) var healthBaseline: Int?
    private var heat = Episode()
    private var limit = Episode()
    private var lastSample: Date?

    public init(healthBaseline: Int? = nil) {
        self.healthBaseline = healthBaseline
    }

    /// `dailyCapacityPercent` is non-nil only on the first sample of a local day.
    public mutating func observe(snapshot: ChargeSnapshot,
                                 temperatureCelsius: Double?,
                                 dailyCapacityPercent: Int?,
                                 now: Date,
                                 enabled: Bool) -> [BatteryAlert] {
        if let last = lastSample, now < last || now.timeIntervalSince(last) > Self.sampleGap {
            heat = Episode()
            limit = Episode()
        }
        lastSample = now
        let alerts = [capacityDrop(dailyCapacityPercent),
                      heatAlert(temperatureCelsius, now: now),
                      limitAlert(snapshot, now: now)].compactMap { $0 }
        return enabled ? alerts : []
    }

    private mutating func capacityDrop(_ capacity: Int?) -> BatteryAlert? {
        guard let capacity else { return nil }
        guard let baseline = healthBaseline else {
            healthBaseline = capacity
            return nil
        }
        guard capacity < baseline else { return nil }
        healthBaseline = capacity
        return .healthDropped(from: baseline, to: capacity)
    }

    private mutating func heatAlert(_ temperature: Double?, now: Date) -> BatteryAlert? {
        guard let temperature else { return nil }
        if temperature >= Self.heatLimit {
            return heat.advance(now: now, duration: Self.heatDuration) ? .overheating(limitCelsius: Self.heatLimit) : nil
        }
        if !heat.fired { heat.began = nil }
        if temperature < Self.heatRearm { heat = Episode() }
        return nil
    }

    /// Reads `mode`, `charging` and `mayManage`, the same state that gates the protection claim (G-3). A full charge
    /// is `Mode.fullCharge`, so charging past Stop on purpose never counts. A heat pause counts only while the
    /// charger really charges: `.heatPaused` comes from the machine's memory (`heatHold`), not from the charger, so
    /// a pause that charges on past Stop + slack for the whole duration is the same failure as a limit that is not
    /// held. After a real inhibit `IsCharging` lags by about 70 s, far less than the duration, so a working pause
    /// never raises a false alert.
    private mutating func limitAlert(_ snapshot: ChargeSnapshot, now: Date) -> BatteryAlert? {
        let shouldBeHeld = snapshot.mayManage
            && (snapshot.mode == .charging || (snapshot.mode == .heatPaused && snapshot.charging))
        let upper = Double(snapshot.thresholds.upper)
        if shouldBeHeld, snapshot.level > upper + Self.limitSlack {
            return limit.advance(now: now, duration: Self.limitDuration) ? .limitNotHeld(snapshot.thresholds) : nil
        }
        if !limit.fired { limit.began = nil }
        if !shouldBeHeld || snapshot.level <= upper { limit = Episode() }
        return nil
    }
}
