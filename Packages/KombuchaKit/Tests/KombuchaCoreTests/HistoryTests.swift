import Foundation
import KombuchaCore
import Testing

/// 2027-01-15 08:00:00 UTC. Divisible by 900 and by 3600, so bucket edges are easy to read.
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60
private let day: TimeInterval = 86_400

private func point(_ minutes: Double,
                   level: Int = 80,
                   onAC: Bool = true,
                   charging: Bool = false,
                   resting: Bool = false,
                   temperature: Double? = 30) -> HistoryPoint {
    HistoryPoint(time: start.addingTimeInterval(minutes * minute), level: level, onAC: onAC, charging: charging,
                 resting: resting, temperatureCelsius: temperature)
}

private func snapshot(level: Double = 80, onAC: Bool = true, charging: Bool = false, protection: Bool = true,
                      fullCharge: Bool = false, writePath: WritePath = .ready) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: onAC, charging: charging, thresholds: .standard, protection: protection,
                   fullChargeActive: fullCharge, writePath: writePath)
}

// MARK: records

@Test func everyRecordKindSurvivesJSON() throws {
    let records: [HistoryRecord] = [
        .point(point(0)),
        .point(point(1, temperature: nil)),
        .health(HealthPoint(day: start, maximumCapacityPercent: 92, cycleCount: 297)),
        .baseline(92),
    ]
    for record in records {
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(HistoryRecord.self, from: data) == record)
    }
}

@Test func anUnknownKindDoesNotDecode() {
    let data = Data(#"{"k":"x","v":1}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(HistoryRecord.self, from: data) }
}

@Test func aPointLineStaysShort() throws {
    #expect(try JSONEncoder().encode(HistoryRecord.point(point(0))).count < 120)
}

@Test func restingMeansProtectedWithAWorkingWritePath() {
    func resting(_ snapshot: ChargeSnapshot) -> Bool {
        HistoryPoint(snapshot: snapshot, temperatureCelsius: 30, at: start).resting
    }
    #expect(resting(snapshot()))
    #expect(!resting(snapshot(writePath: .unknown)))
    #expect(!resting(snapshot(charging: true)))
    #expect(!resting(snapshot(fullCharge: true)))
    #expect(!resting(snapshot(onAC: false)))
    #expect(!resting(snapshot(protection: false)))
}

@Test func theLevelIsAWholePercentAndTheTemperatureAHalfDegree() {
    let made = HistoryPoint(snapshot: snapshot(level: 79.6), temperatureCelsius: 30.26, at: start)
    #expect(made.level == 80)
    #expect(made.temperatureCelsius == 30.5)
}

@Test func anImplausibleTemperatureIsDropped() {
    for bad in [Double.nan, .infinity, -80, 400] { #expect(HistoryPoint.rounded(bad) == nil) }
}

// MARK: cursor

@Test func aSampleIsDueFiftySecondsAfterTheLastOne() {
    var cursor = HistoryCursor()
    let r1 = cursor.isDue(at: start)
    let r2 = cursor.isDue(at: start.addingTimeInterval(49))
    let r3 = cursor.isDue(at: start.addingTimeInterval(50))
    #expect(r1 == true)
    #expect(r2 == false)
    #expect(r3 == true)
}

@Test func aClockThatWentBackwardsMakesASampleDue() {
    var cursor = HistoryCursor()
    let r1 = cursor.isDue(at: start)
    let r2 = cursor.isDue(at: start.addingTimeInterval(-3600))
    #expect(r1 == true)
    #expect(r2 == true)
}

@Test func anUnchangedPointIsRefusedUntilTheHeartbeat() {
    var cursor = HistoryCursor()
    let r1 = cursor.accept(point(0))
    let r2 = cursor.accept(point(1))
    let r3 = cursor.accept(point(9.9))
    let r4 = cursor.accept(point(10))
    #expect(r1 == true)
    #expect(r2 == false)
    #expect(r3 == false)
    #expect(r4 == true)
}

@Test func anyChangedFieldIsAccepted() {
    var cursor = HistoryCursor()
    let r1 = cursor.accept(point(0))
    let r2 = cursor.accept(point(1, level: 81))
    let r3 = cursor.accept(point(2, level: 81, onAC: false))
    let r4 = cursor.accept(point(3, level: 81, onAC: false, charging: true))
    let r5 = cursor.accept(point(4, level: 81, onAC: false, charging: true, resting: true))
    let r6 = cursor.accept(point(5, level: 81, onAC: false, charging: true, resting: true, temperature: 30.5))
    let r7 = cursor.accept(point(6, level: 81, onAC: false, charging: true, resting: true, temperature: nil))
    #expect(r1 == true)
    #expect(r2 == true)
    #expect(r3 == true)
    #expect(r4 == true)
    #expect(r5 == true)
    #expect(r6 == true)
    #expect(r7 == true)
}

@Test func aPointOlderThanTheLastIsAcceptedWhenTheClockWentBackwards() {
    var cursor = HistoryCursor()
    let r1 = cursor.accept(point(60))
    let r2 = cursor.accept(point(0))
    #expect(r1 == true)
    #expect(r2 == true)
}

@Test func aHealthPointIsAcceptedOncePerDay() {
    // Swift Testing's #expect cannot take a call to a mutating method on a var, so extract results to locals.
    var cursor = HistoryCursor()
    let r1 = cursor.acceptHealth(day: start)
    let r2 = cursor.acceptHealth(day: start)
    let r3 = cursor.acceptHealth(day: start.addingTimeInterval(-day))
    let r4 = cursor.acceptHealth(day: start.addingTimeInterval(day))
    #expect(r1 == true)
    #expect(r2 == false)
    #expect(r3 == true)
    #expect(r4 == true)
}

@Test func aRelaunchResumesFromTheLoadedLog() {
    let log = HistoryLog(records: [.point(point(0)), .health(HealthPoint(day: start, maximumCapacityPercent: 92, cycleCount: 1))])
    var cursor = HistoryCursor()
    cursor.resume(from: log)
    let r1 = cursor.accept(point(1))
    let r2 = cursor.acceptHealth(day: start)
    #expect(r1 == false)
    #expect(r2 == false)
}

// MARK: log

@Test func theLogSortsAndTheLastBaselineWins() {
    let log = HistoryLog(records: [.point(point(5)), .baseline(93), .point(point(0)), .baseline(92)])
    #expect(log.points.map(\.time) == [point(0).time, point(5).time])
    #expect(log.baseline == 92)
}

@Test func recordsRebuildTheSameLog() {
    let log = HistoryLog(records: [
        .point(point(0)), .point(point(5, level: 81)),
        .health(HealthPoint(day: start, maximumCapacityPercent: 92, cycleCount: 297)),
        .baseline(92),
    ])
    #expect(HistoryLog(records: log.records) == log)
    #expect(log.records.first == .baseline(92))
}

@Test func pruningKeepsThirtyDays() {
    let now = start.addingTimeInterval(31 * day)
    let log = HistoryLog(records: [
        .point(point(0)),
        .point(point(2 * 1440)),
        .health(HealthPoint(day: start, maximumCapacityPercent: 92, cycleCount: 1)),
        .health(HealthPoint(day: start.addingTimeInterval(2 * day), maximumCapacityPercent: 91, cycleCount: 2)),
        .baseline(92),
    ]).pruned(now: now)
    #expect(log.points.map(\.time) == [point(2 * 1440).time])
    #expect(log.healthPoints.map(\.maximumCapacityPercent) == [91])
    #expect(log.baseline == 92)
}

@Test func aWeekIsBucketedByFifteenMinutes() {
    let log = HistoryLog(records: [
        .point(point(0, level: 80, charging: true, temperature: 31)),
        .point(point(5, level: 81, charging: false, resting: true, temperature: 33)),
        .point(point(20, level: 82)),
    ])
    let buckets = log.buckets(.week, now: start.addingTimeInterval(30 * minute))
    #expect(buckets.count == 2)
    #expect(buckets[0].start == start)
    #expect(buckets[0].level == 81)
    #expect(buckets[0].charging)
    #expect(buckets[0].resting)
    #expect(buckets[0].peakTemperatureCelsius == 33)
    #expect(buckets[1].start == start.addingTimeInterval(900))
    #expect(buckets[1].level == 82)
    #expect(buckets[0].segment == buckets[1].segment)
}

@Test func aMissingBucketStartsANewSegment() {
    let log = HistoryLog(records: [.point(point(0)), .point(point(50))])
    let buckets = log.buckets(.week, now: start.addingTimeInterval(60 * minute))
    #expect(buckets.count == 2)
    #expect(buckets[0].segment != buckets[1].segment)
}

@Test func aHeldBatteryWithHeartbeatsLeavesNoGap() {
    // One point every 10 minutes for two hours: every 15-minute bucket has one.
    let records = (0...12).map { HistoryRecord.point(point(Double($0) * 10)) }
    let buckets = HistoryLog(records: records).buckets(.week, now: start.addingTimeInterval(121 * minute))
    #expect(Set(buckets.map(\.segment)).count == 1)
}

@Test func pointsOutsideTheWindowAreLeftOut() {
    let now = start.addingTimeInterval(8 * day)
    let log = HistoryLog(records: [
        .point(point(0)),
        .point(point(8 * 1440 - 10)),
        .point(point(8 * 1440 + 10)),
    ])
    #expect(log.buckets(.week, now: now).count == 1)
    #expect(log.buckets(.month, now: now).count == 2)
}

@Test func aMonthIsBucketedByTheHour() {
    let log = HistoryLog(records: [.point(point(0, level: 80)), .point(point(30, level: 79)), .point(point(61, level: 78))])
    let buckets = log.buckets(.month, now: start.addingTimeInterval(2 * 3600))
    #expect(buckets.map(\.level) == [79, 78])
    #expect(buckets[1].start == start.addingTimeInterval(3600))
}

@Test func aDischargeIsNeitherChargingNorResting() {
    // The battery's own flag can lag behind the adapter being switched off.
    let discharging = ChargeSnapshot(level: 90, onAC: true, charging: true, thresholds: .standard, protection: true,
                                     fullChargeActive: false, writePath: .ready, dischargeActive: true)
    let point = HistoryPoint(snapshot: discharging, temperatureCelsius: 30, at: start)
    #expect(!point.charging)
    #expect(!point.resting)
    #expect(point.onAC)
}

@Test func aBucketIsOnTheAdapterOnlyWhenEveryPointWas() {
    let log = HistoryLog(records: [
        .point(point(0, onAC: true)),
        .point(point(5, onAC: false)),
        .point(point(20, onAC: true)),
        .point(point(25, onAC: true)),
    ])
    let buckets = log.buckets(.week, now: start.addingTimeInterval(30 * minute))
    #expect(buckets.map(\.onAC) == [false, true])
}
