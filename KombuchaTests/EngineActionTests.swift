import KombuchaCore
import Testing
@testable import Kombucha

@Test func shutdownReleasesAHeldInhibitAndEndsTheLoop() async {
    let harness = EngineHarness(level: 80)
    _ = await harness.engine.start()
    let answer = Answer()
    #expect(await harness.engine.handle(.shutdown(answer)) == false)
    #expect(await answer.value(waitingAtMost: .zero) == .succeeded)
    #expect(Array(harness.journal.entries.suffix(3)) == ["stop power", "stop wake", "allow"])
}

@Test func shutdownSendsNothingWhenNothingIsHeld() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    #expect(await harness.answer { .shutdown($0) } == .succeeded)
    #expect(harness.helper.commands == [true])
}

@Test func aProtectionChangeThatLandsSucceeds() async {
    let harness = EngineHarness(level: 80)
    _ = await harness.engine.start()
    #expect(await harness.answer { .setProtection(false, $0) } == .succeeded)
    #expect(harness.settings.chargeSettings.protection == false)
    #expect(harness.helper.commands == [false, true])
}

@Test func aFailedProtectionChangeRestoresTheSettingAndRepublishes() async {
    let harness = EngineHarness(level: 80)
    _ = await harness.engine.start()
    harness.helper.scriptCommands(.success(.refused))
    #expect(await harness.answer { .setProtection(false, $0) } == .failed(.chargerNotReached))
    #expect(harness.settings.chargeSettings.protection == true)
    #expect(await harness.snapshots(3).map(\.protection) == [true, false, true])
}

@Test func aFailedIdempotentProtectionChangeRestoresTheValueInForce() async {
    // The startup command never lands, so reassert stays set and the next pass sends again.
    let harness = EngineHarness(level: 78)
    harness.helper.scriptCommands(.success(.refused), .success(.refused))
    _ = await harness.engine.start()
    #expect(await harness.answer { .setProtection(true, $0) } == .failed(.chargerNotReached))
    #expect(harness.settings.chargeSettings.protection == true)
}

@Test func aFullChargeNeedsTheAdapter() async {
    let harness = EngineHarness(level: 78, onAC: false, protection: false)
    _ = await harness.engine.start()
    #expect(await harness.answer { .setFullCharge(true, $0) } == .failed(.adapterRequired))
    #expect(harness.settings.chargeSettings.protection == false)
    #expect(harness.helper.commands.isEmpty)
}

@Test func aFullChargeTurnsProtectionOn() async {
    let harness = EngineHarness(level: 78, protection: false)
    _ = await harness.engine.start()
    #expect(await harness.answer { .setFullCharge(true, $0) } == .succeeded)
    #expect(harness.settings.chargeSettings.protection == true)
    #expect(await harness.snapshots(2).last?.fullChargeActive == true)
}

@Test func aFailedFullChargeStaysArmed() async {
    let harness = EngineHarness(level: 80)
    _ = await harness.engine.start()
    harness.helper.scriptCommands(.success(.refused))
    #expect(await harness.answer { .setFullCharge(true, $0) } == .failed(.chargerNotReached))
    #expect(await harness.snapshots(2).last?.fullChargeActive == true)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [false, true, true])
}

@Test func endingAFullChargeGoesBackToTheRange() async {
    let harness = EngineHarness(level: 90)
    _ = await harness.engine.start()
    _ = await harness.answer { .setFullCharge(true, $0) }
    #expect(await harness.answer { .setFullCharge(false, $0) } == .succeeded)
    #expect(harness.helper.commands.last == false)
}

@Test func aFullChargeThatReachesFullIsObserved() async {
    let harness = EngineHarness(level: 90)
    _ = await harness.engine.start()
    _ = await harness.answer { .setFullCharge(true, $0) }
    _ = await harness.engine.handle(.powerChanged(harness.reading(100)))
    #expect(harness.observer.fullChargeEndings == [.reachedFull])
}

@Test func installingSucceedsWhenMacOSAsksForApproval() async {
    let harness = EngineHarness(registration: .notFound)
    _ = await harness.engine.start()
    harness.registrar.whenRegistered(becomes: .requiresApproval)
    #expect(await harness.answer { .installHelper($0) } == .succeeded)
}

@Test func installingFailsWhenNothingIsRegistered() async {
    let harness = EngineHarness(registration: .notFound)
    _ = await harness.engine.start()
    #expect(await harness.answer { .installHelper($0) } == .failed(.helperNotInstalled))
}

@Test func removingTheHelperReleasesBeforeItUnregisters() async {
    let harness = EngineHarness(level: 80)
    _ = await harness.engine.start()
    let before = harness.journal.entries.count
    #expect(await harness.answer { .removeHelper($0) } == .succeeded)
    #expect(Array(harness.journal.entries.dropFirst(before).prefix(2)) == ["allow", "unregister"])
}

@Test func removingTheHelperSendsNothingAfterItUnregisters() async {
    let harness = EngineHarness(level: 80)
    _ = await harness.engine.start()
    #expect(await harness.answer { .removeHelper($0) } == .succeeded)
    #expect(harness.helper.commands == [false, true])
}

@Test func removingFailsWhenMacOSKeepsTheHelper() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    harness.registrar.whenUnregistered(becomes: .enabled)
    #expect(await harness.answer { .removeHelper($0) } == .failed(.helperNotRemoved))
}

@Test func installingAnswersOnlyOnceTheNewWritePathIsPublished() async {
    let harness = EngineHarness(registration: .notFound)
    _ = await harness.engine.start()
    harness.registrar.whenRegistered(becomes: .enabled)
    harness.helper.delayPings(by: .milliseconds(100))
    let answer = Answer()
    Task { [engine = harness.engine] in _ = await engine.handle(.installHelper(answer)) }
    #expect(await answer.value(waitingAtMost: .seconds(2)) == .succeeded)
    #expect(harness.observer.snapshots.last?.writePath == .ready)
}

@Test func installingAnswersWithTheRegistrationWhenTheProbeIsSlow() async {
    let harness = EngineHarness(registration: .notFound,
                                timing: Engine.Timing(tick: .seconds(60), callerWait: .seconds(2), settleWait: .milliseconds(50)))
    _ = await harness.engine.start()
    harness.registrar.whenRegistered(becomes: .enabled)
    harness.helper.delayPings(by: .milliseconds(500))
    let answer = Answer()
    Task { [engine = harness.engine] in _ = await engine.handle(.installHelper(answer)) }
    let started = ContinuousClock.now
    #expect(await answer.value(waitingAtMost: .seconds(2)) == .succeeded)
    #expect(ContinuousClock.now - started < .milliseconds(400))
}

@Test func removingAnswersOnlyOnceTheNewWritePathIsPublished() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    let answer = Answer()
    Task { [engine = harness.engine] in _ = await engine.handle(.removeHelper(answer)) }
    #expect(await answer.value(waitingAtMost: .seconds(2)) == .succeeded)
    #expect(harness.observer.snapshots.last?.writePath == .notRegistered)
}
