import Foundation
import KombuchaCore
import Testing

/// 2027-01-15 08:00:00 UTC. Divisible by 900 and by 3600, so bucket edges are easy to read.
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let minute: TimeInterval = 60
private let week: TimeInterval = 7 * 86_400
private let standardLimit = Thresholds.normalized(lower: 70, upper: 80)

private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * minute) }

private func point(_ minutes: Double,
                   level: Int = 80,
                   onAC: Bool = true,
                   charging: Bool = false,
                   resting: Bool = false,
                   temperature: Double? = 30) -> HistoryPoint {
    HistoryPoint(time: at(minutes), level: level, onAC: onAC, charging: charging, resting: resting,
                 temperatureCelsius: temperature)
}

private func chart(_ points: [HistoryPoint], at minutes: Double, range: HistoryRange = .week,
                   limit: Thresholds? = standardLimit) -> HistoryChart {
    let now = at(minutes)
    let log = HistoryLog(records: points.map(HistoryRecord.point))
    return HistoryChart(buckets: log.buckets(range, now: now), range: range, now: now, limit: limit)
}

@Test func consecutiveChargingBucketsFormOneRun() {
    let made = chart([point(0, charging: true), point(20, charging: true), point(35, charging: true), point(50)], at: 70)
    #expect(made.runs(for: .charging) == [HistoryRun(start: at(0), end: at(45))])
}

@Test func aMissingBucketSplitsARun() {
    let made = chart([point(0, charging: true), point(50, charging: true)], at: 70)
    #expect(made.runs(for: .charging) == [HistoryRun(start: at(0), end: at(15)), HistoryRun(start: at(45), end: at(60))])
}

@Test func aBucketBothChargingAndRestingIsInBothLanes() {
    let made = chart([point(0, charging: true, resting: true)], at: 20)
    let run = HistoryRun(start: at(0), end: at(15))
    #expect(made.runs(for: .charging) == [run])
    #expect(made.runs(for: .resting) == [run])
    #expect(made.runs(for: .onBattery).isEmpty)
}

@Test func theOnBatteryLaneIsTheBucketsOffTheAdapter() {
    let made = chart([point(0, onAC: false), point(20, onAC: true), point(35, onAC: false)], at: 50)
    #expect(made.runs(for: .onBattery) == [HistoryRun(start: at(0), end: at(15)), HistoryRun(start: at(30), end: at(45))])
}

@Test func aDischargeDipHasNoLaneMark() {
    // A discharge keeps the cable in, so the point is on the adapter, not charging and not resting.
    let made = chart([point(0, level: 70, onAC: true, charging: false, resting: false)], at: 20)
    for lane in HistoryLane.allCases { #expect(made.runs(for: lane).isEmpty) }
    #expect(made.detail(at: at(5))?.lanes == [])
}

@Test func gapRunsCoverEverySlotWithNothingRecorded() {
    let made = chart([point(0), point(45)], at: 70)
    #expect(made.gaps == [
        HistoryRun(start: at(70).addingTimeInterval(-week), end: at(0)),
        HistoryRun(start: at(15), end: at(45)),
        HistoryRun(start: at(60), end: at(70)),
    ])
}

@Test func aGapThatWouldHaveNoLengthIsDropped() {
    let made = chart([point(0), point(45)], at: 60)
    #expect(made.gaps.last == HistoryRun(start: at(15), end: at(45)))
}

@Test func anEmptyPeriodIsOneGapAndHasNoRuns() {
    let made = chart([], at: 70)
    #expect(made.gaps == [HistoryRun(start: at(70).addingTimeInterval(-week), end: at(70))])
    for lane in HistoryLane.allCases { #expect(made.runs(for: lane).isEmpty) }
}

@Test func aMonthGapIsMeasuredInHours() {
    let made = chart([point(0), point(90)], at: 150, range: .month)
    #expect(made.gaps.last == HistoryRun(start: at(120), end: at(150)))
}

@Test func segmentsUnderEightBucketsAreShortAndLongOnesAreNot() {
    let short = chart([point(0), point(50)], at: 70)
    #expect(short.shortSegmentBuckets.count == 2)
    let long = chart((0..<8).map { point(Double($0) * 15) }, at: 130)
    #expect(long.shortSegmentBuckets.isEmpty)
}

@Test func aPointerOverABucketReportsIt() {
    let made = chart([point(0, level: 83, charging: true, temperature: 31.5)], at: 20)
    #expect(made.detail(at: at(7)) == HistoryDetail(start: at(0), level: 83, lanes: [.charging], peakTemperatureCelsius: 31.5))
}

@Test func theDetailListsLanesInTheOrderChargingRestingOnBattery() {
    let made = chart([point(0, onAC: false, charging: true, resting: true)], at: 20)
    #expect(made.detail(at: at(1))?.lanes == [.charging, .resting, .onBattery])
}

@Test func aPointerOverAGapReportsNoData() {
    let made = chart([point(0)], at: 70)
    #expect(made.detail(at: at(40)) == HistoryDetail(start: at(30), level: nil, lanes: [], peakTemperatureCelsius: nil))
}

@Test func aPointerOutsideThePeriodReportsNothing() {
    let made = chart([point(0)], at: 70)
    #expect(made.detail(at: at(80)) == nil)
    #expect(made.detail(at: made.periodStart.addingTimeInterval(-1)) == nil)
}

@Test func theFloorIsTheMultipleOfTenThreeBelowTheLowestLevel() {
    // The design scenario: down to 35 %, limit 70–80.
    let made = chart([point(0, level: 100), point(20, level: 35)], at: 40)
    #expect(made.yFloor == 30)
    #expect(made.yTicks == [30, 50, 70, 80, 100])
}

@Test func theFloorNeverRisesAboveResumeMinusTen() {
    let made = chart([point(0, level: 95), point(20, level: 90)], at: 40)
    #expect(made.yFloor == 60)
    #expect(made.yTicks == [60, 70, 80, 100])
}

@Test func aLowLimitLowersTheFloor() {
    let made = chart([point(0, level: 85)], at: 20, limit: Thresholds.normalized(lower: 40, upper: 60))
    #expect(made.yFloor == 30)
    #expect(made.yTicks == [30, 40, 60, 100])
}

@Test func anEmptyPeriodHasTheFloorAtSixty() {
    #expect(chart([], at: 70).yFloor == 60)
}

@Test func aLowestLevelNearZeroPutsTheFloorAtZero() {
    let made = chart([point(0, level: 2)], at: 20)
    #expect(made.yFloor == 0)
    #expect(made.yTicks.first == 0)
}

@Test func withoutALimitTheFloorIsNotCappedAndNoLimitTicksAppear() {
    let made = chart([point(0, level: 95), point(20, level: 90)], at: 40, limit: nil)
    #expect(made.limit == nil)
    #expect(made.yFloor == 80)
    #expect(made.yTicks == [80, 100])
    let low = chart([point(0, level: 35)], at: 20, limit: nil)
    #expect(low.yTicks == [30, 50, 70, 90, 100])
}

@Test func theSummaryIsTheRestingShareOfTheRecordedBuckets() {
    let made = chart([point(0, resting: true), point(20), point(35, resting: true), point(50, resting: true)], at: 70)
    #expect(made.summary == HistorySummary(restedPercent: 75, recorded: 3_600))
}

@Test func theSummaryRoundsToAWholePercent() {
    let oneOfThree = chart([point(0, resting: true), point(20), point(35)], at: 70)
    #expect(oneOfThree.summary?.restedPercent == 33)
    let twoOfThree = chart([point(0, resting: true), point(20, resting: true), point(35)], at: 70)
    #expect(twoOfThree.summary?.restedPercent == 67)
}

@Test func aMonthRecordsHoursAndAnEmptyPeriodHasNoSummary() {
    let month = chart([point(0, resting: true), point(70)], at: 150, range: .month)
    #expect(month.summary == HistorySummary(restedPercent: 50, recorded: 7_200))
    #expect(chart([], at: 70).summary == nil)
}
