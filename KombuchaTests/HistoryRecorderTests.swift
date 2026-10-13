import Foundation
import KombuchaCore
import Synchronization
import Testing
@testable import Kombucha

/// The base moment: 2027-01-15 08:00 UTC.
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func snapshot(level: Double = 78, charging: Bool = false, writePath: WritePath = .ready) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: true, charging: charging, thresholds: .standard, protection: true,
                   fullChargeActive: false, writePath: writePath)
}

@MainActor
private struct Rig {
    let store: FakeHistoryStore
    let poster = FakeAlertPoster()
    let health: FakeHealth
    let clock: TestClock
    let ui: FakeUISettings
    let recorder: HistoryRecorder

    init(store: FakeHistoryStore = FakeHistoryStore(),
         health: FakeHealth = FakeHealth(),
         ui: FakeUISettings = FakeUISettings(),
         clock: TestClock = TestClock(start)) {
        self.store = store
        self.health = health
        self.clock = clock
        self.ui = ui
        recorder = HistoryRecorder(store: store, ui: ui, alerts: poster,
                                   readHealth: { [health] in health.read() },
                                   now: { [clock] in clock.now },
                                   calendar: Calendar(identifier: .gregorian))
    }

    /// One engine pass after `seconds` have gone by.
    func pass(after seconds: TimeInterval = 0, _ snapshot: ChargeSnapshot = snapshot()) async {
        clock.advance(seconds)
        recorder.observe(snapshot, fullChargeEnded: nil)
        await recorder.settled()
    }
}

@MainActor
@Test func theFirstSampleWritesAPointTheDayAndTheBaseline() async {
    let rig = Rig()
    await rig.pass()
    let log = rig.store.log
    #expect(log.points.count == 1)
    #expect(log.points.first?.level == 78)
    #expect(log.points.first?.resting == true)
    #expect(log.points.first?.temperatureCelsius == 30)
    #expect(log.healthPoints.count == 1)
    #expect(log.healthPoints.first?.maximumCapacityPercent == 92)
    #expect(log.baseline == 92)
}

@MainActor
@Test func passesInsideTheSpacingReadNothing() async {
    let rig = Rig()
    await rig.pass()
    let reads = rig.health.reads
    await rig.pass(after: 10, snapshot(level: 79))
    await rig.pass(after: 10, snapshot(level: 80))
    #expect(rig.health.reads == reads)
    #expect(rig.store.log.points.count == 1)
}

@MainActor
@Test func anUnchangedBatteryWritesOnlyTheHeartbeat() async {
    let rig = Rig()
    await rig.pass()
    for _ in 0..<9 { await rig.pass(after: 60) }
    #expect(rig.store.log.points.count == 1)
    await rig.pass(after: 60)
    #expect(rig.store.log.points.count == 2)
}

@MainActor
@Test func aChangedLevelWritesAPoint() async {
    let rig = Rig()
    await rig.pass()
    await rig.pass(after: 60, snapshot(level: 79))
    #expect(rig.store.log.points.map(\.level) == [78, 79])
}

@MainActor
@Test func aMissingReadingStillRecordsThePointWithoutATemperature() async {
    let rig = Rig(health: FakeHealth(temperature: nil))
    await rig.pass()
    let log = rig.store.log
    #expect(log.points.count == 1)
    #expect(log.points.first?.temperatureCelsius == nil)
    #expect(log.healthPoints.isEmpty)
    #expect(log.baseline == nil)
}

@MainActor
@Test func aHotBatteryIsAnnouncedOnceAfterFiveMinutes() async {
    let rig = Rig(health: FakeHealth(temperature: 45))
    await rig.pass()
    for _ in 0..<4 { await rig.pass(after: 60) }
    #expect(rig.poster.alerts.isEmpty)
    await rig.pass(after: 60)
    #expect(rig.poster.alerts == [.overheating(limitCelsius: 40)])
    for _ in 0..<5 { await rig.pass(after: 60) }
    #expect(rig.poster.alerts.count == 1)
}

@MainActor
@Test func aSwitchThatIsOffKeepsTheAlertAwayAndNothingReplaysIt() async {
    let rig = Rig(health: FakeHealth(temperature: 45), ui: FakeUISettings(batteryAttention: false))
    await rig.pass()
    for _ in 0..<6 { await rig.pass(after: 60) }
    rig.ui.setNotifyBatteryAttention(true)
    for _ in 0..<6 { await rig.pass(after: 60) }
    #expect(rig.poster.alerts.isEmpty)
}

@MainActor
@Test func aLimitThatIsNotHeldIsAnnounced() async {
    let rig = Rig()
    let over = snapshot(level: 84, charging: true)
    await rig.pass(over)
    for _ in 0..<5 { await rig.pass(after: 60, over) }
    #expect(rig.poster.alerts == [.limitNotHeld(.standard)])
}

@MainActor
@Test func aFailingDiskDoesNotStopTheAlerts() async {
    let store = FakeHistoryStore()
    store.failWrites(true)
    let rig = Rig(store: store, health: FakeHealth(temperature: 45))
    await rig.pass()
    for _ in 0..<5 { await rig.pass(after: 60) }
    #expect(store.records.isEmpty)
    #expect(rig.poster.alerts == [.overheating(limitCelsius: 40)])
}

@MainActor
@Test func theLaunchDropsOldRecordsAndRewritesTheFile() async {
    let old = HistoryPoint(time: start.addingTimeInterval(-40 * 86_400), level: 50, onAC: true, charging: false,
                           resting: false, temperatureCelsius: 25)
    let recent = HistoryPoint(time: start.addingTimeInterval(-3_600), level: 60, onAC: true, charging: false,
                              resting: false, temperatureCelsius: 25)
    let rig = Rig(store: FakeHistoryStore(records: [.point(old), .point(recent), .baseline(92)]))
    await rig.pass()
    #expect(rig.store.log.points.map(\.level) == [60, 78])
    #expect(rig.store.replaceCalls >= 1)
}

@MainActor
@Test func aRelaunchDoesNotDuplicateTheLastPointOrTheDay() async {
    let day = Calendar(identifier: .gregorian).startOfDay(for: start)
    let seeded = FakeHistoryStore(records: [
        .point(HistoryPoint(time: start.addingTimeInterval(-20), level: 78, onAC: true, charging: false,
                            resting: true, temperatureCelsius: 30)),
        .health(HealthPoint(day: day, maximumCapacityPercent: 92, cycleCount: 100)),
        .baseline(92),
    ])
    let rig = Rig(store: seeded)
    await rig.pass()
    #expect(rig.store.log.points.count == 1)
    #expect(rig.store.log.healthPoints.count == 1)
}

@MainActor
@Test func theStoredBaselineSurvivesARelaunchAndAnnouncesTheNextDrop() async {
    let day = Calendar(identifier: .gregorian).startOfDay(for: start)
    let seeded = FakeHistoryStore(records: [
        .health(HealthPoint(day: day.addingTimeInterval(-86_400), maximumCapacityPercent: 92, cycleCount: 99)),
        .baseline(92),
    ])
    let rig = Rig(store: seeded, health: FakeHealth(capacity: 91))
    await rig.pass()
    #expect(rig.poster.alerts == [.healthDropped(from: 92, to: 91)])
    #expect(rig.store.log.baseline == 91)
}

@MainActor
@Test func aFailedReadNeverRewritesTheFile() async {
    let day = Calendar(identifier: .gregorian).startOfDay(for: start)
    let store = FakeHistoryStore(records: [
        .point(HistoryPoint(time: start.addingTimeInterval(-3_600), level: 60, onAC: true, charging: false,
                            resting: false, temperatureCelsius: 25)),
        .health(HealthPoint(day: day.addingTimeInterval(-86_400), maximumCapacityPercent: 95, cycleCount: 99)),
        .baseline(95),
    ])
    store.failLoads(true)
    let rig = Rig(store: store)
    await rig.pass()
    #expect(store.replaceCalls == 0)
    let log = store.log
    #expect(log.points.map(\.level) == [60, 78])
    #expect(log.healthPoints.count == 2)
    #expect(log.baseline == 92)
}

@Test func theCompositeObserverFeedsEveryObserver() {
    final class Count: ChargeObserving, Sendable {
        private let count = Mutex(0)
        var seen: Int { count.withLock { $0 } }
        func observe(_ snapshot: ChargeSnapshot, fullChargeEnded: FullChargeEnding?) { count.withLock { $0 += 1 } }
    }
    let first = Count(), second = Count()
    CompositeObserver([first, second]).observe(snapshot(), fullChargeEnded: nil)
    #expect(first.seen == 1)
    #expect(second.seen == 1)
}
