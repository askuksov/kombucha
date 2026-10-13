import Testing
@testable import KombuchaCore

private func reading(_ level: Double, onAC: Bool = true, charging: Bool = false) -> PowerReading {
    PowerReading(level: level, onAC: onAC, charging: charging)
}

private func settings(protection: Bool = true, lower: Int = 75, upper: Int = 80) -> ChargeSettings {
    ChargeSettings(thresholds: .normalized(lower: lower, upper: upper), protection: protection)
}

private func holding(at threshold: Int, fullCharge: Bool = false) -> MachineState {
    MachineState(inhibitedAt: threshold, fullChargeActive: fullCharge)
}

@Test func withoutAReassertThePlanCarriesTheMachineCommand() {
    let plan = Planner.plan(state: MachineState(), reading: reading(80), settings: settings(), reassert: false, externalBatteryManager: nil)
    #expect(plan.command == .inhibit)
    #expect(plan.step.command == .inhibit)

    let quiet = Planner.plan(state: MachineState(), reading: reading(78), settings: settings(), reassert: false, externalBatteryManager: nil)
    #expect(quiet.command == nil)
    #expect(quiet.step.command == nil)
}

@Test func aReassertFollowsWhatTheMachineHoldsAfterTheStep() {
    let idle = Planner.plan(state: MachineState(), reading: reading(78), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(idle.command == .allow)
    #expect(idle.step.command == nil)

    let held = Planner.plan(state: holding(at: 80), reading: reading(81), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(held.command == .inhibit)
    #expect(held.step.command == nil)

    let taken = Planner.plan(state: MachineState(), reading: reading(80), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(taken.command == .inhibit)
    #expect(taken.step.state.inhibitedAt == 80)
}

@Test func aReassertNeedsTheAdapter() {
    let plan = Planner.plan(state: MachineState(), reading: reading(78, onAC: false), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(plan.command == nil)
}

@Test func aReassertNeedsProtection() {
    let plan = Planner.plan(state: MachineState(), reading: reading(78), settings: settings(protection: false), reassert: true, externalBatteryManager: nil)
    #expect(plan.command == nil)
}

@Test func anExternalBatteryManagerSilencesTheReassert() {
    let plan = Planner.plan(state: MachineState(), reading: reading(78), settings: settings(), reassert: true, externalBatteryManager: .alDente)
    #expect(plan.command == nil)
    #expect(plan.snapshot.externalBatteryManager == .alDente)
    #expect(!plan.snapshot.mayManage)
}

@Test func aReassertNeverSwallowsTheReleaseOfAHeldInhibit() {
    let plan = Planner.plan(state: holding(at: 80), reading: reading(83, onAC: false), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(plan.step.command == .allow)
    #expect(plan.command == .allow)
}

@Test func aReassertReleasesAnInhibitTheWiderRangeNoLongerNeeds() {
    let plan = Planner.plan(state: holding(at: 75), reading: reading(82), settings: settings(lower: 70, upper: 85),
                            reassert: true, externalBatteryManager: nil)
    #expect(plan.step.command == .allow)
    #expect(plan.command == .allow)
}

@Test func theSnapshotCarriesTheReadingTheSettingsAndAnUnknownWritePath() {
    let plan = Planner.plan(state: MachineState(),
                            reading: reading(63.4, onAC: true, charging: true),
                            settings: settings(lower: 70, upper: 90),
                            reassert: false,
                            externalBatteryManager: nil)
    #expect(plan.snapshot.level == 63.4)
    #expect(plan.snapshot.charging)
    #expect(plan.snapshot.thresholds == Thresholds.normalized(lower: 70, upper: 90))
    #expect(plan.snapshot.protection)
    #expect(plan.snapshot.writePath == .unknown)
    #expect(!plan.snapshot.mayManage)
    #expect(plan.snapshot.mode == .charging)
}

@Test func theSnapshotFollowsTheFullChargeFlagAfterTheStep() {
    let armed = Planner.plan(state: MachineState().withFullCharge(true),
                             reading: reading(90),
                             settings: settings(),
                             reassert: false,
                             externalBatteryManager: nil)
    #expect(armed.snapshot.fullChargeActive)
    #expect(armed.snapshot.mode == .fullCharge)

    let ended = Planner.plan(state: MachineState().withFullCharge(true),
                             reading: reading(100),
                             settings: settings(),
                             reassert: false,
                             externalBatteryManager: nil)
    #expect(!ended.snapshot.fullChargeActive)
    #expect(ended.step.fullChargeEnded == .reachedFull)
    #expect(ended.command == .inhibit)
}

@Test func aNonFiniteReadingStillProducesACleanSnapshot() {
    let plan = Planner.plan(state: MachineState(), reading: reading(.nan), settings: settings(), reassert: false, externalBatteryManager: nil)
    #expect(plan.command == nil)
    #expect(plan.snapshot.level == 0)
    #expect(plan.snapshot.displayLevel == 0)
}

@Test func aCommandFromTheReassertAloneIsNamedReassert() {
    let plan = Planner.plan(state: MachineState(), reading: reading(78), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(plan.step.command == nil)
    #expect(plan.command == .allow)
    #expect(plan.reason == .reassert)

    let held = Planner.plan(state: holding(at: 80), reading: reading(81), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(held.command == .inhibit)
    #expect(held.reason == .reassert)
}

@Test func theMachinesReasonWinsOverTheReassert() {
    let crossed = Planner.plan(state: MachineState(), reading: reading(83), settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(crossed.command == .inhibit)
    #expect(crossed.reason == .stopThresholdReached)

    let widened = Planner.plan(state: holding(at: 75), reading: reading(82), settings: settings(lower: 70, upper: 85),
                               reassert: true, externalBatteryManager: nil)
    #expect(widened.command == .allow)
    #expect(widened.reason == .rangeWidened)
}

@Test func noCommandMeansNoReason() {
    let quiet = Planner.plan(state: MachineState(), reading: reading(78), settings: settings(), reassert: false, externalBatteryManager: nil)
    #expect(quiet.command == nil)
    #expect(quiet.reason == nil)

    let silenced = Planner.plan(state: MachineState(), reading: reading(78), settings: settings(), reassert: true, externalBatteryManager: .alDente)
    #expect(silenced.command == nil)
    #expect(silenced.reason == nil)
}

@Test func theTemperatureReachesTheMachineAndTheSnapshot() {
    let hot = PowerReading(level: 70, onAC: true, charging: true, temperatureCelsius: 41)
    let plan = Planner.plan(state: MachineState(), reading: hot, settings: settings(), reassert: false, externalBatteryManager: nil)
    #expect(plan.command == .inhibit)
    #expect(plan.reason == .heatReached)
    #expect(plan.snapshot.heatHold)
    #expect(plan.snapshot.mode == .heatPaused)

    let cool = PowerReading(level: 70, onAC: true, charging: true, temperatureCelsius: 30)
    let quiet = Planner.plan(state: MachineState(), reading: cool, settings: settings(), reassert: false, externalBatteryManager: nil)
    #expect(quiet.command == nil)
    #expect(!quiet.snapshot.heatHold)
}

@Test func aReassertDuringAHeatPauseSendsTheInhibit() {
    let hot = PowerReading(level: 70, onAC: true, charging: false, temperatureCelsius: 42)
    let held = MachineState(inhibitedAt: nil, fullChargeActive: false, heatHold: true, heatInhibited: true)
    let plan = Planner.plan(state: held, reading: hot, settings: settings(), reassert: true, externalBatteryManager: nil)
    #expect(plan.command == .inhibit)
    #expect(plan.step.command == nil)
}

@Test func aDischargeReadsOnACFromTheAdapterAndCarriesItsCommands() {
    let on = PowerReading(level: 94, onAC: true, charging: false, adapterPresent: true)
    let first = Planner.plan(state: MachineState().withDischarge(true), reading: on, settings: settings(),
                             reassert: false, externalBatteryManager: nil)
    #expect(first.step.adapterCommand == .disable(leaseSeconds: DischargePolicy.leaseSeconds))
    #expect(first.snapshot.dischargeActive)
    #expect(first.snapshot.mode == .discharging)

    let off = PowerReading(level: 93, onAC: false, charging: false, adapterPresent: true)
    let later = Planner.plan(state: first.step.state, reading: off, settings: settings(),
                             reassert: true, externalBatteryManager: nil)
    #expect(later.snapshot.onAC)
    #expect(later.snapshot.mode == .discharging)
    // The reassert still applies: the adapter is there, only switched off.
    #expect(later.command == .inhibit)
    #expect(later.reason == .reassert)
}

@Test func theSwitchReadinessReachesTheMachine() {
    let on = PowerReading(level: 94, onAC: true, charging: false, adapterPresent: true)
    let running = Planner.plan(state: MachineState().withDischarge(true), reading: on, settings: settings(),
                               reassert: false, externalBatteryManager: nil).step.state
    let off = PowerReading(level: 93, onAC: false, charging: false, adapterPresent: true)
    let blocked = Planner.plan(state: running, reading: off, settings: settings(), reassert: false,
                               externalBatteryManager: nil, adapterSwitchReady: false)
    #expect(blocked.step.dischargeEnded == .blocked)
    #expect(blocked.step.adapterCommand == .enable)
    #expect(!blocked.snapshot.dischargeActive)
    #expect(blocked.snapshot.onAC)
}

@Test func withoutADischargeOnACIsThePowerSources() {
    let reading = PowerReading(level: 78, onAC: false, charging: false, adapterPresent: true)
    let plan = Planner.plan(state: MachineState(), reading: reading, settings: settings(), reassert: true,
                            externalBatteryManager: nil)
    #expect(!plan.snapshot.onAC)
    #expect(plan.command == nil)
}
