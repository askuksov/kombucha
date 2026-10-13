import KombuchaCore
import Testing
@testable import Kombucha

/// On the adapter at `level`, range 75–80, the cable readable.
private func dischargeHarness(level: Double = 94, adapterSwitch: Bool = true) -> EngineHarness {
    EngineHarness(level: level, adapterPresent: true, adapterSwitch: adapterSwitch)
}

/// The adapter switched off: the power source says battery, the cable is in.
private func switchedOff(_ harness: EngineHarness, _ level: Double) -> PowerReading {
    harness.reading(level, onAC: false, adapterPresent: true)
}

/// Started, holding at 80 (the start pass at 94 inhibits), discharging.
private func discharging(_ harness: EngineHarness) async {
    _ = await harness.engine.start()
    #expect(await harness.answer { .setDischarge(true, $0) } == .succeeded)
}

// MARK: start and run

@Test func aDischargeSwitchesTheAdapterOffAndShowsIt() async {
    let harness = dischargeHarness()
    _ = await harness.engine.start()
    #expect(await harness.snapshots(1).last?.adapterSwitchAvailable == true)
    #expect(await harness.answer { .setDischarge(true, $0) } == .succeeded)
    #expect(harness.helper.adapterCalls == [.off])
    #expect(harness.helper.commands == [false])
    let shown = await harness.snapshots(2).last
    #expect(shown?.dischargeActive == true)
    #expect(shown?.mode == .discharging)
}

@Test func everyPassRenewsTheLeaseWhileTheAdapterIsOff() async {
    let harness = dischargeHarness()
    await discharging(harness)
    harness.power.set(switchedOff(harness, 93))
    _ = await harness.engine.handle(.tick)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.adapterCalls == [.off, .off, .off])
    #expect(harness.observer.snapshots.last?.onAC == true)
    #expect(harness.observer.snapshots.last?.mode == .discharging)
}

// MARK: endings

@Test func reachingStopSwitchesTheAdapterBackOnAndRestsProtected() async {
    let harness = dischargeHarness()
    await discharging(harness)
    harness.power.set(switchedOff(harness, 80))
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.adapterCalls == [.off, .on])
    #expect(harness.helper.commands == [false])
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
    #expect(harness.observer.snapshots.last?.mode == .protected)
}

@Test func pullingTheCableEndsTheDischargeAdapterFirst() async {
    let harness = dischargeHarness()
    await discharging(harness)
    let before = harness.journal.entries.count
    harness.power.set(harness.reading(85, onAC: false, adapterPresent: false))
    _ = await harness.engine.handle(.tick)
    #expect(Array(harness.journal.entries.dropFirst(before)) == ["adapter on", "allow"])
    #expect(harness.observer.snapshots.last?.mode == .onBattery)
}

@Test func switchingProtectionOffEndsTheDischargeAdapterFirst() async {
    let harness = dischargeHarness()
    await discharging(harness)
    let before = harness.journal.entries.count
    harness.settings.setBatteryProtection(false)
    _ = await harness.engine.handle(.settingsChanged)
    #expect(Array(harness.journal.entries.dropFirst(before)) == ["adapter on", "allow"])
}

@Test func aFullChargeEndsTheDischargeAndStartsAtOnce() async {
    let harness = dischargeHarness()
    await discharging(harness)
    harness.power.set(switchedOff(harness, 90))
    let before = harness.journal.entries.count
    #expect(await harness.answer { .setFullCharge(true, $0) } == .succeeded)
    #expect(Array(harness.journal.entries.dropFirst(before)) == ["adapter on", "allow"])
    #expect(harness.observer.snapshots.last?.fullChargeActive == true)
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
}

@Test func stoppingSwitchesTheAdapterOnAndKeepsTheInhibit() async {
    let harness = dischargeHarness()
    await discharging(harness)
    #expect(await harness.answer { .setDischarge(false, $0) } == .succeeded)
    #expect(harness.helper.adapterCalls == [.off, .on])
    #expect(harness.helper.commands == [false])
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
}

@Test func sleepEndsTheDischargeBeforeItIsAnswered() async {
    let harness = dischargeHarness()
    await discharging(harness)
    #expect(await harness.answer { .willSleep($0) } == .succeeded)
    #expect(harness.helper.adapterCalls == [.off, .on])
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
}

@Test func sleepWithoutADischargeSendsNothing() async {
    let harness = dischargeHarness()
    _ = await harness.engine.start()
    let journal = harness.journal.entries
    #expect(await harness.answer { .willSleep($0) } == .succeeded)
    #expect(harness.journal.entries == journal)
}

@Test func quittingSwitchesTheAdapterOnBeforeItReleasesTheCharge() async {
    let harness = dischargeHarness()
    await discharging(harness)
    #expect(await harness.answer { .shutdown($0) } == .succeeded)
    #expect(Array(harness.journal.entries.suffix(4)) == ["stop power", "stop wake", "adapter on", "allow"])
}

@Test func removingTheHelperSwitchesTheAdapterOnFirst() async {
    let harness = dischargeHarness()
    await discharging(harness)
    let before = harness.journal.entries.count
    #expect(await harness.answer { .removeHelper($0) } == .succeeded)
    #expect(Array(harness.journal.entries.dropFirst(before).prefix(3)) == ["adapter on", "allow", "unregister"])
}

// MARK: no discharge offered

@Test func aHelperThatSpeaksProtocolOneOffersNoDischarge() async {
    let harness = dischargeHarness()
    harness.helper.answerPings(with: 1)
    _ = await harness.engine.start()
    #expect(await harness.snapshots(1).last?.adapterSwitchAvailable == false)
    #expect(await harness.answer { .setDischarge(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.helper.adapterCalls.isEmpty)
}

@Test func aMacWithoutTheAdapterKeyOffersNoDischarge() async {
    let harness = dischargeHarness(adapterSwitch: false)
    _ = await harness.engine.start()
    #expect(await harness.snapshots(1).last?.adapterSwitchAvailable == false)
    #expect(await harness.answer { .setDischarge(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.helper.adapterCalls.isEmpty)
}

@Test func anAdapterThatCannotBeReadOffersNoDischarge() async {
    let harness = EngineHarness(level: 94)
    _ = await harness.engine.start()
    #expect(await harness.snapshots(1).last?.adapterSwitchAvailable == false)
    #expect(await harness.answer { .setDischarge(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.helper.adapterCalls.isEmpty)
}

@Test func anAdapterReadAsAbsentOnACOffersNoDischarge() async {
    let harness = EngineHarness(level: 94, onAC: true, adapterPresent: false)
    _ = await harness.engine.start()
    #expect(await harness.snapshots(1).last?.adapterSwitchAvailable == false)
    #expect(await harness.answer { .setDischarge(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.helper.adapterCalls.isEmpty)
}

@Test func aDischargeIsRefusedAtStop() async {
    let harness = dischargeHarness(level: 80)
    _ = await harness.engine.start()
    #expect(await harness.answer { .setDischarge(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.helper.adapterCalls.isEmpty)
}

@Test func aLevelThatFellToStopAfterThePanelShowedItEndsBeforeAnythingIsSwitched() async {
    let harness = dischargeHarness(level: 81)
    _ = await harness.engine.start()
    harness.power.set(harness.reading(80, adapterPresent: true))
    #expect(await harness.answer { .setDischarge(true, $0) } == .succeeded)
    #expect(harness.helper.adapterCalls.isEmpty)
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
}

// MARK: commands that do not land

@Test func aRefusedDisableEndsTheDischargeAndOwesAnEnable() async {
    let harness = dischargeHarness()
    _ = await harness.engine.start()
    harness.helper.scriptAdapter(.success(.refused))
    #expect(await harness.answer { .setDischarge(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.adapterCalls == [.off, .on])
}

@Test func anUnansweredDisableShowsTheHelperUnreachable() async {
    let harness = dischargeHarness()
    _ = await harness.engine.start()
    harness.helper.scriptAdapter(.failure(.timedOut))
    #expect(await harness.answer { .setDischarge(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.helper.drops == 1)
    #expect(harness.observer.snapshots.last?.writePath == .unreachable)
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
}

@Test func aRefusedRenewEndsTheDischarge() async {
    let harness = dischargeHarness()
    await discharging(harness)
    harness.helper.scriptAdapter(.success(.refused))
    harness.power.set(switchedOff(harness, 90))
    _ = await harness.engine.handle(.tick)
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.adapterCalls == [.off, .off, .on])
}

// MARK: review focus

@Test func aCableReplugBetweenTwoPassesKeepsTheDischarge() async {
    let harness = dischargeHarness()
    await discharging(harness)
    // Pulled and put back between two passes; the power source may even say AC for a moment.
    harness.power.set(harness.reading(90, onAC: true, adapterPresent: true))
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.adapterCalls == [.off, .off])
    #expect(!harness.helper.commands.contains(true))
    #expect(harness.observer.snapshots.last?.mode == .discharging)
}

@Test func sleepWhileTheDisableIsInFlightSwitchesTheAdapterBackOn() async {
    let harness = dischargeHarness()
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    harness.helper.delayAdapter(by: .milliseconds(300))
    let discharge = Task { [engine = harness.engine] in await engine.setDischarge(true) }
    try? await Task.sleep(for: .milliseconds(50))
    let sleep = Answer()
    harness.inbox.post(.willSleep(sleep))
    #expect(await discharge.value == .succeeded)
    #expect(await sleep.value(waitingAtMost: .seconds(2)) == .succeeded)
    #expect(harness.helper.adapterCalls == [.off, .on])
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

// MARK: on the way out

@Test func quittingWaitsLessThanTheApp() {
    let timing = Engine.Timing()
    #expect(timing.adapterOnWait == .seconds(2))
    #expect(timing.shutdownBudget == .milliseconds(2300))
    // AppDelegate waits 2.5 s for the shutdown answer.
    #expect(timing.shutdownBudget < .milliseconds(2500))
}

@Test func anUnansweredEnableOnTheWayOutSkipsTheAllowAndAnswersInTime() async {
    let harness = EngineHarness(level: 94, adapterPresent: true,
                                timing: Engine.Timing(adapterOnWait: .milliseconds(200),
                                                      shutdownBudget: .milliseconds(300)))
    await discharging(harness)
    harness.helper.delayAdapter(by: .seconds(3))
    let started = ContinuousClock.now
    #expect(await harness.answer { .shutdown($0) } == .succeeded)
    #expect(ContinuousClock.now - started < .milliseconds(1000))
    #expect(harness.helper.arrivedCommands == [false])
}

@Test func aSlowEnableAndASlowAllowStillAnswerInTime() async {
    let harness = EngineHarness(level: 94, adapterPresent: true,
                                timing: Engine.Timing(adapterOnWait: .seconds(1),
                                                      shutdownBudget: .milliseconds(1500)))
    await discharging(harness)
    harness.helper.delayAdapter(by: .milliseconds(200))
    harness.helper.delayCommands(by: .seconds(5))
    let started = ContinuousClock.now
    #expect(await harness.answer { .shutdown($0) } == .succeeded)
    // The allow's answer is cut off at the budget, long before its 5 s.
    #expect(ContinuousClock.now - started < .seconds(3))
    #expect(harness.helper.adapterCalls == [.off, .on])
    #expect(harness.helper.arrivedCommands.contains(true))
}

@Test func anEnableThatFailsFastOnTheWayOutStillSendsTheAllow() async {
    let harness = dischargeHarness()
    await discharging(harness)
    harness.helper.scriptAdapter(.failure(.transport("the connection broke")))
    #expect(await harness.answer { .shutdown($0) } == .succeeded)
    #expect(harness.helper.commands == [false, true])
}

@Test func quittingBehindABlockedRegistrationSendsNoAdapterCommand() async {
    let harness = dischargeHarness()
    await discharging(harness)
    harness.registrar.set(.requiresApproval)
    // The renew cannot be sent: the discharge ends and an enable is owed, which cannot be sent either.
    _ = await harness.engine.handle(.tick)
    #expect(harness.observer.snapshots.last?.dischargeActive == false)
    #expect(await harness.answer { .shutdown($0) } == .succeeded)
    #expect(harness.helper.adapterCalls == [.off])
}
