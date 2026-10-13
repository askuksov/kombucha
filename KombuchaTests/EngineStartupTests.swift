import KombuchaCore
import Testing
@testable import Kombucha

@Test func anUnsupportedMacGetsNoHelperNoEventSourcesAndNoPass() async {
    let harness = EngineHarness(hasInternalBattery: false)
    #expect(await harness.engine.start() == .noBattery)
    #expect(harness.journal.entries.isEmpty)
    #expect(harness.settings.normalizations == 0)
}

@Test func aMacWhoseSMCRefusesIsNotSupported() async {
    let harness = EngineHarness(smc: .otherFailure)
    #expect(await harness.engine.start() == .smcUnusable)
    #expect(harness.journal.entries.isEmpty)
}

@Test func startupRegistersStartsTheSourcesPingsAndPasses() async {
    let harness = EngineHarness()
    #expect(await harness.engine.start() == .supported)
    #expect(harness.settings.normalizations == 1)
    #expect(harness.journal.entries == ["register", "start power", "start wake", "ping", "allow"])
}

@Test func aNewProcessWritesTheImpliedCommandOnceEvenInsideTheBand() async {
    // FR-LIM-7: an inhibit left by a killed process is released by the first pass.
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.commands == [true])
}

@Test func aSourceThatFailsToStartDoesNotStopTheStartup() async {
    let harness = EngineHarness(sourceStarts: false)
    #expect(await harness.engine.start() == .supported)
    #expect(harness.helper.pings == 1)
    #expect(harness.helper.commands == [true])
}

@Test func aHelperAwaitingApprovalIsNotPingedAndShowsWhy() async {
    let harness = EngineHarness(registration: .requiresApproval)
    _ = await harness.engine.start()
    #expect(harness.helper.pings == 0)
    #expect(harness.helper.commands.isEmpty)
    #expect(await harness.snapshots(1).first?.writePath == .requiresApproval)
}

@Test func anAdapterLeftSwitchedOffIsSwitchedOnAtStart() async {
    // The cable is in, the power source says battery: a key left off by a crash or a restart.
    let harness = EngineHarness(level: 85, onAC: false, adapterPresent: true)
    _ = await harness.engine.start()
    #expect(harness.journal.entries == ["register", "start power", "start wake", "ping", "adapter on", "inhibit"])
}

@Test func aProtocolOneHelperIsNeverAskedToSwitchTheAdapter() async {
    let harness = EngineHarness(level: 85, onAC: false, adapterPresent: true)
    harness.helper.answerPings(with: 1)
    _ = await harness.engine.start()
    #expect(harness.helper.adapterCalls.isEmpty)
    #expect(harness.journal.entries == ["register", "start power", "start wake", "ping"])
}

@Test func anAdapterSwitchedOffBesideAnExternalBatteryManagerIsLeftAlone() async {
    // The manager may have switched it off itself; Kombucha neither switches it on nor owes it.
    let harness = EngineHarness(level: 85, onAC: false, adapterPresent: true)
    harness.processes.set(["/Applications/AlDente.app/Contents/MacOS/AlDente"])
    _ = await harness.engine.start()
    #expect(harness.helper.adapterCalls.isEmpty)
    harness.processes.set([])
    _ = await harness.engine.handle(.tick)
    #expect(harness.helper.adapterCalls.isEmpty)
}
