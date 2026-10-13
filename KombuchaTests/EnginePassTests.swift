import KombuchaCore
import Testing
@testable import Kombucha

@Test func aThresholdCrossingInhibitsOnce() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    _ = await harness.engine.handle(.powerChanged(harness.reading(80)))
    _ = await harness.engine.handle(.powerChanged(harness.reading(81)))
    #expect(harness.helper.commands == [true, false])
}

@Test func aFailedCommandKeepsWhatTheChargerHoldsAndIsRepeated() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    harness.helper.scriptCommands(.success(.refused))
    _ = await harness.engine.handle(.powerChanged(harness.reading(80)))
    #expect(await harness.snapshots(2).last?.level == 80)
    harness.power.set(harness.reading(80))
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [true, false, false])
}

@Test func theReassertDebtIsClearedOnlyByALandedWrite() async {
    let harness = EngineHarness(level: 78)
    harness.helper.scriptCommands(.success(.refused))
    _ = await harness.engine.start()
    _ = await harness.engine.handle(.tick)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [true, true])
}

@Test func aWakeWritesWhatTheChargerShouldHoldAgain() async {
    // FR-LIM-6: holding at 83% with range 70–80.
    let harness = EngineHarness(level: 83, thresholds: .normalized(lower: 70, upper: 80))
    _ = await harness.engine.start()
    _ = await harness.engine.handle(.systemWoke)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [false, false])
}

@Test func aWakeOnBatteryOwesTheWriteUntilTheAdapterReturns() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    harness.power.set(harness.reading(78, onAC: false))
    _ = await harness.engine.handle(.systemWoke)
    _ = await harness.engine.handle(.powerChanged(harness.reading(78)))
    #expect(harness.helper.commands == [true, true])
}

@Test func theWritePathComingBackOwesAWrite() async {
    let harness = EngineHarness(level: 78)
    harness.helper.scriptPings(.failure(.timedOut), .failure(.timedOut))
    harness.helper.scriptCommands(.failure(.timedOut))
    _ = await harness.engine.start()
    #expect(await harness.answer { .probe($0) } == .succeeded)
    #expect(harness.helper.commands == [true, true])
}

@Test func aTransportFailureIsRepairedExactlyOncePerOutage() async {
    let harness = EngineHarness()
    harness.helper.scriptPings(.failure(.transport("gone")), .success(1))
    _ = await harness.engine.start()
    #expect(harness.registrar.registers == 2)
    #expect(await harness.snapshots(1).first?.writePath == .ready)

    harness.helper.scriptPings(.failure(.transport("gone")), .failure(.transport("gone")), .failure(.transport("gone")))
    _ = await harness.answer { .probe($0) }
    _ = await harness.answer { .probe($0) }
    #expect(harness.registrar.registers == 3)
}

@Test func aConnectionLossIsIgnoredWhileTheHelperIsUnreachable() async {
    let harness = EngineHarness()
    harness.helper.scriptPings(.failure(.timedOut), .failure(.timedOut))
    harness.helper.scriptCommands(.failure(.timedOut))
    _ = await harness.engine.start()
    let pings = harness.helper.pings
    _ = await harness.engine.handle(.helperConnectionLost)
    #expect(harness.helper.pings == pings)
}

@Test func aConnectionLossWhileReachableProbesAgain() async {
    let harness = EngineHarness()
    _ = await harness.engine.start()
    _ = await harness.engine.handle(.helperConnectionLost)
    #expect(harness.helper.pings == 2)
}

@Test func aCommandWithoutAnAnswerDropsTheConnectionAndShowsUnreachable() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    harness.helper.scriptCommands(.failure(.timedOut))
    _ = await harness.engine.handle(.powerChanged(harness.reading(80)))
    #expect(harness.helper.drops == 1)
    #expect(await harness.snapshots(2).last?.writePath == .unreachable)
}

@Test func anIdlePassSendsNothingAndPingsNothing() async {
    // FR-LIM-9.
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    let journal = harness.journal.entries
    for _ in 0..<3 {
        _ = await harness.engine.handle(.tick)
    }
    #expect(harness.journal.entries == journal)
}

@Test func aSettingsChangeTakesEffectAtOnce() async {
    // FR-LIM-11: raising the stop threshold above a held inhibit releases it.
    let harness = EngineHarness(level: 80)
    _ = await harness.engine.start()
    harness.settings.set(ChargeSettings(thresholds: .normalized(lower: 75, upper: 85), protection: true))
    _ = await harness.engine.handle(.settingsChanged)
    #expect(harness.helper.commands == [false, true])
}

@Test func anExternalBatteryManagerSilencesTheEngine() async {
    let harness = EngineHarness(level: 80)
    harness.processes.set(["/Applications/AlDente.app/Contents/MacOS/AlDente"])
    _ = await harness.engine.start()
    #expect(harness.helper.commands.isEmpty)
    #expect(await harness.snapshots(1).first?.externalBatteryManager == .alDente)
}

@Test func anUnreadableBatteryPublishesNothing() async {
    let harness = EngineHarness()
    harness.power.set(nil)
    _ = await harness.engine.start()
    #expect(harness.helper.commands.isEmpty)
    harness.power.set(harness.reading(77))
    _ = await harness.engine.handle(.tick)
    #expect(await harness.snapshots(1).first?.level == 77)
}

@Test func anUnchangedSnapshotIsPublishedOnce() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    _ = await harness.engine.handle(.tick)
    _ = await harness.engine.handle(.powerChanged(harness.reading(79)))
    #expect(await harness.snapshots(2).map(\.level) == [78, 79])
}

@Test func aHotBatteryHoldsTheChargeOnceAndACoolOneReleasesIt() async {
    let harness = EngineHarness(level: 70)
    _ = await harness.engine.start()
    #expect(harness.helper.commands == [true])
    harness.power.set(harness.reading(70, temperature: 41))
    _ = await harness.engine.handle(.tick)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [true, false])
    #expect(await harness.snapshots(2).last?.mode == .heatPaused)
    harness.power.set(harness.reading(70, temperature: 36))
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [true, false, true])
}

@Test func aFailedTemperatureReadChangesNothing() async {
    let harness = EngineHarness(level: 70)
    _ = await harness.engine.start()
    harness.power.set(harness.reading(70, temperature: 42))
    _ = await harness.engine.handle(.tick)
    harness.power.set(harness.reading(70, temperature: nil))
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [true, false])
}

@Test func aRefusedHeatInhibitIsSentAgainOnTheNextPass() async {
    let harness = EngineHarness(level: 70)
    _ = await harness.engine.start()
    harness.helper.scriptCommands(.success(.refused))
    harness.power.set(harness.reading(70, temperature: 42))
    _ = await harness.engine.handle(.tick)
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [true, false, false])
}

@Test func heatIsIgnoredWithoutTheAdapter() async {
    let harness = EngineHarness(level: 70, onAC: false)
    _ = await harness.engine.start()
    harness.power.set(harness.reading(70, onAC: false, temperature: 45))
    _ = await harness.engine.handle(.tick)
    #expect(!harness.helper.commands.contains(false))
}
