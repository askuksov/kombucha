import KombuchaCore
import Testing
@testable import Kombucha

/// A model fed by the harness's engine and a gateway attached to both. The harness must not subscribe itself.
@MainActor
private func wire(_ harness: EngineHarness, limit: Duration = .seconds(2)) -> (LiveEngineGateway, AppModel) {
    let model = AppModel()
    model.attach(engine: harness.engine, settings: harness.settings)
    let gateway = LiveEngineGateway(model: model, readinessLimit: limit, pollInterval: .milliseconds(5))
    gateway.attach(engine: harness.engine, settings: harness.settings)
    Task { await model.consume(harness.engine.snapshots) }
    return (gateway, model)
}

@MainActor
private func error(of call: () async throws -> Void) async -> GatewayError? {
    do {
        try await call()
        return nil
    } catch let error as GatewayError {
        return error
    } catch {
        Issue.record("unexpected \(error)")
        return nil
    }
}

@MainActor
@Test func statusReportsTheSnapshotAndItsStatusLine() async throws {
    let harness = EngineHarness(level: 78, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let status = try await gateway.status()
    #expect(status == BatteryStatus(level: 78, mode: .protected, thresholds: .standard, protection: true,
                                    holdingLimit: true, line: Copy.statusLine(.protected, .standard)))
}

@MainActor
@Test func holdingTheLimitIsOffWhileProtectionIsOff() async throws {
    let harness = EngineHarness(level: 78, protection: false, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let status = try await gateway.status()
    #expect(status.protection == false)
    #expect(status.holdingLimit == false)
}

@MainActor
@Test func holdingTheLimitIsOffOnBatteryAndDuringAFullCharge() async throws {
    let onBattery = EngineHarness(level: 78, onAC: false, subscribe: false)
    let (batteryGateway, batteryModel) = wire(onBattery)
    batteryModel.publish(await onBattery.engine.start())
    #expect(try await batteryGateway.status().holdingLimit == false)

    let harness = EngineHarness(level: 78, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    try await gateway.startFullCharge()
    #expect(await eventually { model.snapshot?.fullChargeActive == true })
    #expect(try await gateway.status().holdingLimit == false)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func aClosedGateStillReportsStatusWithItsHeading() async throws {
    let harness = EngineHarness(level: 78, registration: .requiresApproval, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let status = try await gateway.status()
    #expect(status.holdingLimit == false)
    #expect(status.line == Copy.heading(.requiresApproval))
}

@MainActor
@Test func aClosedGateRefusesHardwareChangesWithItsHeading() async {
    let harness = EngineHarness(level: 78, registration: .requiresApproval, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let heading = Copy.heading(.requiresApproval)
    #expect(await error { _ = try await gateway.setProtection(false) } == .gate(heading))
    #expect(await error { try await gateway.startFullCharge() } == .gate(heading))
    #expect(harness.settings.chargeSettings.protection == true)
}

@MainActor
@Test func anExternalBatteryManagerIsAGateToo() async {
    let harness = EngineHarness(level: 80, subscribe: false)
    harness.processes.set(["/Applications/AlDente.app/Contents/MacOS/AlDente"])
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    #expect(await error { _ = try await gateway.setProtection(false) }
            == .gate(Copy.externalManagerHeading(.alDente)))
    #expect(await error { try await gateway.startFullCharge() } == .gate(Copy.externalManagerHeading(.alDente)))
}

@MainActor
@Test func stopFullChargeSucceedsWhileAGateIsClosed() async {
    let harness = EngineHarness(level: 78, subscribe: false)
    harness.processes.set(["/Applications/AlDente.app/Contents/MacOS/AlDente"])
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    #expect(await error { try await gateway.stopFullCharge() } == nil)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func stopFullChargeSucceedsBehindABlockedWritePath() async {
    let harness = EngineHarness(level: 78, registration: .requiresApproval, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    #expect(await error { try await gateway.stopFullCharge() } == nil)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func aRefusedStopWithTheGateOpenIsReported() async {
    let harness = EngineHarness(level: 80, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    // The full charge releases the inhibit held at the limit; ending it must inhibit again, and that is refused.
    #expect(await error { try await gateway.startFullCharge() } == nil)
    harness.helper.scriptCommands(.success(.refused))
    #expect(await error { try await gateway.stopFullCharge() } == .failed(.chargerNotReached))
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func setProtectionGoesThroughTheEngine() async throws {
    let harness = EngineHarness(level: 80, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    #expect(try await gateway.setProtection(false) == false)
    #expect(harness.settings.chargeSettings.protection == false)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func aRefusedCommandIsReportedAndTheSettingRestored() async {
    let harness = EngineHarness(level: 80, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    harness.helper.scriptCommands(.success(.refused))
    #expect(await error { _ = try await gateway.setProtection(false) } == .failed(.chargerNotReached))
    #expect(harness.settings.chargeSettings.protection == true)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func startFullChargeOnBatteryAsksForTheAdapter() async {
    let harness = EngineHarness(level: 78, onAC: false, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    #expect(await error { try await gateway.startFullCharge() } == .failed(.adapterRequired))
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func anIntentIsNotDroppedWhileThePanelWaits() async throws {
    let harness = EngineHarness(level: 80, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let ended = harness.runLoop()
    harness.helper.delayCommands(by: .milliseconds(200))
    let press = Task { await model.setProtection(false) }
    #expect(await eventually { model.isPending })
    #expect(try await gateway.setProtection(true) == true)
    await press.value
    #expect(harness.settings.chargeSettings.protection == true)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func anUnsupportedMacFailsAtOnce() async {
    let harness = EngineHarness(smc: .keyNotFound, subscribe: false)
    let (gateway, model) = wire(harness, limit: .seconds(30))
    model.publish(await harness.engine.start())
    let started = ContinuousClock.now
    #expect(await error { _ = try await gateway.status() } == .unsupported)
    #expect(await error { _ = try await gateway.setProtection(true) } == .unsupported)
    #expect(await error { try await gateway.startFullCharge() } == .unsupported)
    #expect(await error { try await gateway.stopFullCharge() } == .unsupported)
    #expect(ContinuousClock.now - started < .seconds(1))
}

@MainActor
@Test func theLimitIsStoredOnAnUnsupportedMac() async throws {
    let harness = EngineHarness(smc: .keyNotFound, subscribe: false)
    let (gateway, model) = wire(harness)
    model.publish(await harness.engine.start())
    let pair = try await gateway.setThresholds(stop: 70, resume: 60)
    #expect(pair == .normalized(lower: 60, upper: 70))
    #expect(harness.settings.chargeSettings.thresholds == pair)
}

@MainActor
@Test func theLimitIsNormalizedAndStored() async throws {
    let harness = EngineHarness(subscribe: false)
    let (gateway, _) = wire(harness)
    let pair = try await gateway.setThresholds(stop: 60, resume: 58)
    #expect(pair.upper == 60)
    #expect(pair.lower == 55)
    #expect(harness.settings.chargeSettings.thresholds == pair)
}

@MainActor
@Test func withoutASnapshotTheGatewayIsNotReady() async {
    let harness = EngineHarness(subscribe: false)
    let (gateway, _) = wire(harness, limit: .milliseconds(100))
    #expect(await error { _ = try await gateway.status() } == .notReady)
    #expect(await error { try await gateway.stopFullCharge() } == .notReady)
}

@MainActor
@Test func aSnapshotThatArrivesDuringTheWaitMakesItReady() async throws {
    let harness = EngineHarness(level: 78, subscribe: false)
    let (gateway, model) = wire(harness)
    let status = Task { try await gateway.status() }
    try await Task.sleep(for: .milliseconds(50))
    model.publish(await harness.engine.start())
    #expect(try await status.value.level == 78)
}

@MainActor
@Test func beforeTheEngineIsAttachedNothingIsReady() async {
    let model = AppModel()
    let gateway = LiveEngineGateway(model: model, readinessLimit: .milliseconds(100), pollInterval: .milliseconds(5))
    #expect(await error { _ = try await gateway.status() } == .notReady)
    #expect(await error { _ = try await gateway.setThresholds(stop: 80, resume: 75) } == .notReady)
}

@Test(arguments: [
    (GatewayError.notReady, "Kombucha is still starting. Try again in a moment."),
    (.unsupported, "This Mac isn't supported"),
    (.gate("The helper stopped answering"), "The helper stopped answering"),
    (.failed(.adapterRequired), "Plug in the adapter to charge to 100%."),
    (.failed(.chargerNotReached), "That did not reach the charger, so nothing was changed."),
])
func everyGatewayErrorSaysItsSentence(error: GatewayError, sentence: String) {
    #expect(error.message == sentence)
    #expect(String(localized: error.localizedStringResource) == sentence)
}
