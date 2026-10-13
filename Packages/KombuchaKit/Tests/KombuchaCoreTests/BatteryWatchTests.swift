import Foundation
import KombuchaCore
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

/// Standard thresholds (75–80), so "over the limit" means a level above 82.
private func snapshot(level: Double = 85, onAC: Bool = true, charging: Bool = true, protection: Bool = true,
                      fullCharge: Bool = false, writePath: WritePath = .ready, heatHold: Bool = false,
                      dischargeActive: Bool = false) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: onAC, charging: charging, thresholds: .standard, protection: protection,
                   fullChargeActive: fullCharge, writePath: writePath, heatHold: heatHold, dischargeActive: dischargeActive)
}

/// Feeds one sample a minute from `from` to `through` (seconds, inclusive) and returns every alert raised.
private func feed(_ watch: inout BatteryWatch,
                  from: Double = 0,
                  through: Double,
                  snapshot: ChargeSnapshot = snapshot(charging: false),
                  temperature: Double? = nil,
                  enabled: Bool = true) -> [BatteryAlert] {
    var alerts: [BatteryAlert] = []
    for seconds in stride(from: from, through: through, by: 60) {
        alerts += watch.observe(snapshot: snapshot, temperatureCelsius: temperature, dailyCapacityPercent: nil,
                                now: at(seconds), enabled: enabled)
    }
    return alerts
}

private let overheating = BatteryAlert.overheating(limitCelsius: 40)

// MARK: heat

@Test func heatIsAnnouncedOnceAfterFiveMinutes() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 240, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 300, through: 300, temperature: 41) == [overheating])
    #expect(feed(&watch, from: 360, through: 1200, temperature: 41).isEmpty)
}

@Test func aDipBelowTheLimitStartsTheCountOver() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 120, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 180, through: 180, temperature: 39).isEmpty)
    #expect(feed(&watch, from: 240, through: 480, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 540, through: 540, temperature: 41) == [overheating])
}

@Test func heatIsArmedAgainOnlyBelowThirtySevenDegrees() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 300, temperature: 41) == [overheating])
    // 38.5 is below the limit but not below the re-arm mark: still the same episode.
    #expect(feed(&watch, from: 360, through: 420, temperature: 38.5).isEmpty)
    #expect(feed(&watch, from: 480, through: 1200, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 1260, through: 1260, temperature: 36).isEmpty)
    #expect(feed(&watch, from: 1320, through: 1560, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 1620, through: 1620, temperature: 41) == [overheating])
}

@Test func aGapBetweenSamplesStartsAnEpisodeOver() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 120, temperature: 41).isEmpty)
    // The Mac slept for eight minutes: that time does not count.
    #expect(feed(&watch, from: 600, through: 840, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 900, through: 900, temperature: 41) == [overheating])
}

@Test func aClockThatWentBackwardsStartsAnEpisodeOver() {
    var watch = BatteryWatch()
    #expect(feed(&watch, from: 6000, through: 6240, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 0, through: 240, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 300, through: 300, temperature: 41) == [overheating])
}

@Test func aMissingTemperatureNeitherStartsNorEndsAnEpisode() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 60, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 120, through: 180, temperature: nil).isEmpty)
    #expect(feed(&watch, from: 240, through: 240, temperature: 41).isEmpty)
    #expect(feed(&watch, from: 300, through: 300, temperature: 41) == [overheating])
}

@Test func aSwitchThatIsOffConsumesTheEventAndNothingReplaysIt() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 300, temperature: 41, enabled: false).isEmpty)
    #expect(feed(&watch, from: 360, through: 900, temperature: 41, enabled: true).isEmpty)
}

// MARK: limit not held

private let hold = snapshot(level: 83)

@Test func aLimitThatIsNotHeldIsAnnouncedAfterFiveMinutes() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 240, snapshot: hold).isEmpty)
    #expect(feed(&watch, from: 300, through: 300, snapshot: hold) == [.limitNotHeld(.standard)])
    #expect(feed(&watch, from: 360, through: 1200, snapshot: hold).isEmpty)
}

@Test func twoPointsOverTheStopLevelIsStillInsideTheSlack() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 900, snapshot: snapshot(level: 82)).isEmpty)
}

@Test(arguments: [
    snapshot(level: 90, fullCharge: true),
    snapshot(level: 90, writePath: .unknown),
    snapshot(level: 90, protection: false),
    snapshot(level: 90, onAC: false),
    snapshot(level: 90, charging: false),
])
func chargingPastStopIsExpectedInTheseStates(state: ChargeSnapshot) {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 900, snapshot: state).isEmpty)
}

@Test func aHeatPauseThatKeepsChargingRaisesTheLimitAlert() {
    // The pause is the machine's memory; a charger that ignores the inhibit is the same failure as a limit not held.
    let paused = snapshot(level: 90, heatHold: true)
    #expect(paused.mode == .heatPaused)
    #expect(paused.charging)
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 240, snapshot: paused).isEmpty)
    #expect(feed(&watch, from: 300, through: 300, snapshot: paused) == [.limitNotHeld(.standard)])
    #expect(feed(&watch, from: 360, through: 1200, snapshot: paused).isEmpty)
}

@Test func aHeatPauseThatReallyStoppedTheChargerRaisesNoLimitAlert() {
    let paused = snapshot(level: 90, charging: false, heatHold: true)
    #expect(paused.mode == .heatPaused)
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 900, snapshot: paused).isEmpty)
}

@Test func theLimitIsArmedAgainWhenTheBatteryStopsCharging() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 300, snapshot: hold) == [.limitNotHeld(.standard)])
    #expect(feed(&watch, from: 360, through: 360, snapshot: snapshot(level: 83, charging: false)).isEmpty)
    #expect(feed(&watch, from: 420, through: 660, snapshot: hold).isEmpty)
    #expect(feed(&watch, from: 720, through: 720, snapshot: hold) == [.limitNotHeld(.standard)])
}

@Test func aDipInsideTheSlackDoesNotArmTheLimitAgain() {
    var watch = BatteryWatch()
    #expect(feed(&watch, through: 300, snapshot: hold) == [.limitNotHeld(.standard)])
    #expect(feed(&watch, from: 360, through: 360, snapshot: snapshot(level: 81)).isEmpty)
    #expect(feed(&watch, from: 420, through: 1200, snapshot: hold).isEmpty)
}

// MARK: health

private func capacity(_ watch: inout BatteryWatch, _ percent: Int?, enabled: Bool = true) -> [BatteryAlert] {
    watch.observe(snapshot: snapshot(charging: false), temperatureCelsius: nil, dailyCapacityPercent: percent,
                  now: at(0), enabled: enabled)
}

@Test func theFirstCapacityIsTheBaselineAndSaysNothing() {
    var watch = BatteryWatch()
    #expect(capacity(&watch, 92).isEmpty)
    #expect(watch.healthBaseline == 92)
}

@Test func aDropIsAnnouncedOnceAndTheBaselineFollowsIt() {
    var watch = BatteryWatch(healthBaseline: 92)
    #expect(capacity(&watch, 92).isEmpty)
    #expect(capacity(&watch, 91) == [.healthDropped(from: 92, to: 91)])
    #expect(watch.healthBaseline == 91)
    #expect(capacity(&watch, 91).isEmpty)
    #expect(capacity(&watch, 89) == [.healthDropped(from: 91, to: 89)])
}

@Test func aHigherReadingNeverRaisesTheBaseline() {
    var watch = BatteryWatch(healthBaseline: 91)
    #expect(capacity(&watch, 93).isEmpty)
    #expect(watch.healthBaseline == 91)
    #expect(capacity(&watch, 91).isEmpty)
}

@Test func aDropWhileTheSwitchIsOffMovesTheBaselineSilently() {
    var watch = BatteryWatch(healthBaseline: 92)
    #expect(capacity(&watch, 91, enabled: false).isEmpty)
    #expect(watch.healthBaseline == 91)
    #expect(capacity(&watch, 91, enabled: true).isEmpty)
}

@Test func aMissingCapacityChangesNothing() {
    var watch = BatteryWatch(healthBaseline: 92)
    #expect(capacity(&watch, nil).isEmpty)
    #expect(watch.healthBaseline == 92)
    var fresh = BatteryWatch()
    #expect(capacity(&fresh, nil).isEmpty)
    #expect(fresh.healthBaseline == nil)
}

@Test func aDischargeNeverRaisesTheLimitAlert() {
    var watch = BatteryWatch()
    let discharging = snapshot(level: 90, charging: true, dischargeActive: true)
    #expect(feed(&watch, through: 900, snapshot: discharging).isEmpty)
}
