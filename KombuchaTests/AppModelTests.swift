import Dispatch
import Foundation
import KombuchaCore
import Testing
@testable import Kombucha

@MainActor
private func model(for harness: EngineHarness, readHealth: @escaping @Sendable () -> BatteryHealth? = { nil }) -> AppModel {
    let model = AppModel(readHealth: readHealth)
    model.attach(engine: harness.engine, settings: harness.settings)
    return model
}

@MainActor
@Test func snapshotsReachTheModel() async {
    let harness = EngineHarness(level: 78, subscribe: false)
    let model = model(for: harness)
    Task { await model.consume(harness.engine.snapshots) }
    _ = await harness.engine.start()
    #expect(await eventually { model.snapshot?.displayLevel == 78 })
}

@MainActor
@Test func aFailedActionIsShownUntilTheNextPress() async {
    let harness = EngineHarness(level: 80)
    let model = model(for: harness)
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    harness.helper.scriptCommands(.success(.refused))
    await model.setProtection(false)
    #expect(model.controlFailure == .chargerNotReached)
    #expect(!model.isPending)
    await model.setProtection(false)
    #expect(model.controlFailure == nil)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func openingThePanelClearsTheControlFailure() async {
    let harness = EngineHarness(level: 80)
    let model = model(for: harness)
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    harness.helper.scriptCommands(.success(.refused))
    await model.setProtection(false)
    #expect(model.controlFailure == .chargerNotReached)
    await model.panelOpened()
    #expect(model.controlFailure == nil)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func probingTheHelperPingsItAndReadsNothingElse() async {
    let harness = EngineHarness(level: 78)
    let model = model(for: harness, readHealth: { Issue.record("health read on probe"); return nil })
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    let pings = harness.helper.pings
    await model.probeHelper()
    #expect(harness.helper.pings == pings + 1)
    #expect(model.health == .reading)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func readingHealthShowsWhatTheBatterySaid() {
    let health = BatteryHealth.derive(BatteryRegistryValues(cycleCount: 297, designCapacity: 8579,
                                                            nominalChargeCapacity: 7964, permanentFailureStatus: 0,
                                                            temperature: 3013, voltage: 12651))
    let reading = AppModel(readHealth: { health })
    #expect(reading.health == .reading)
    reading.refreshHealth()
    #expect(reading.health == .read(health!))
    let silent = AppModel(readHealth: { nil })
    silent.refreshHealth()
    #expect(silent.health == .unavailable)
}

@MainActor
@Test func refreshingHealthAgainShowsTheNewTemperature() {
    let fake = FakeHealth(temperature: 30)
    let model = AppModel(readHealth: { fake.read() })
    model.refreshHealth()
    fake.set(temperature: 36.5)
    model.refreshHealth()
    guard case .read(let health) = model.health else {
        Issue.record("health not read")
        return
    }
    #expect(health.temperatureCelsius == 36.5)
    #expect(fake.reads == 2)
}

@MainActor
@Test func openingThePanelRepairsAHelperThatStoppedAnswering() async {
    // The job was booted out: the status still says enabled, and the first ping gets no answer.
    let harness = EngineHarness(level: 78)
    let model = model(for: harness)
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    harness.helper.scriptPings(.failure(.transport("the job is gone")))
    let registers = harness.registrar.registers
    await model.probeHelper()
    #expect(harness.registrar.registers == registers + 1)
    // Back after a gap, so the implied command is owed once more.
    #expect(harness.helper.commands == [true, true])
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func movingAThumbStoresTheMovedPair() {
    let harness = EngineHarness()
    let model = model(for: harness)
    model.setUpper(90)
    #expect(harness.settings.chargeSettings.thresholds == .normalized(lower: 75, upper: 90))
    model.setLower(60)
    #expect(harness.settings.chargeSettings.thresholds == .normalized(lower: 60, upper: 90))
}

@MainActor
@Test func withoutAnEngineTheControlsDoNothing() async {
    let model = AppModel()
    await model.setProtection(false)
    await model.probeHelper()
    model.setUpper(60)
    #expect(model.controlFailure == nil)
    #expect(!model.isPending)
    #expect(model.snapshot == nil)
}

@MainActor
@Test func aSecondPressWhilePendingIsIgnored() async {
    let harness = EngineHarness(level: 80, subscribe: false)
    let model = model(for: harness)
    Task { await model.consume(harness.engine.snapshots) }
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    let commands = harness.helper.commands.count
    harness.helper.delayCommands(by: .milliseconds(300))
    let first = Task { await model.setProtection(false) }
    #expect(await eventually { model.isPending })
    #expect(model.pendingProtection == false)
    await model.setFullCharge(true)
    await model.setProtection(true)
    await first.value
    #expect(harness.helper.commands.count == commands + 1)
    #expect(harness.settings.chargeSettings.protection == false)
    #expect(model.snapshot?.fullChargeActive == false)
    #expect(!model.isPending)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func theSnapshotCarriesTheNewValueWhenTheAnswerArrives() async {
    // The consumer task delivers the snapshot on its own turn, so it may land after setProtection returns.
    let harness = EngineHarness(level: 80, subscribe: false)
    let model = model(for: harness)
    Task { await model.consume(harness.engine.snapshots) }
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    #expect(await eventually { model.snapshot?.protection == true })
    await model.setProtection(false)
    #expect(model.pendingProtection == nil)
    #expect(await eventually { model.snapshot?.protection == false })
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func aHelperFailureIsKeptApartFromTheControls() async {
    let harness = EngineHarness(level: 78, registration: .notFound)
    harness.registrar.whenRegistered(becomes: .notFound)
    let model = model(for: harness)
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    await model.installHelper()
    #expect(model.helperFailure == .helperNotInstalled)
    #expect(model.controlFailure == nil)
    await model.setProtection(false)
    #expect(model.helperFailure == nil)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func aDragEndCommitsTheThresholdAtOnce() {
    let harness = EngineHarness()
    let model = model(for: harness)
    model.setUpper(85)
    #expect(harness.settings.chargeSettings.thresholds.upper == 85)
    #expect(harness.settings.thresholdWrites == 1)
}

@MainActor
private func uiModel(loginItem: FakeLoginItem = FakeLoginItem(.notRegistered),
                     centre: FakeNotificationCentre = FakeNotificationCentre(authorization: .notDetermined),
                     ui: FakeUISettings = FakeUISettings()) -> AppModel {
    let model = AppModel()
    model.attach(loginItem: loginItem, notifications: centre, ui: ui)
    return model
}

@MainActor
@Test func theLoginItemStatusIsReadOnAttach() {
    let item = FakeLoginItem(.enabled)
    #expect(uiModel(loginItem: item).loginItemStatus == .enabled)
}

@MainActor
@Test func switchingLaunchAtLoginOnRegistersAndShowsTheResult() async {
    let item = FakeLoginItem(.notRegistered)
    item.whenRegistered(becomes: .enabled)
    let model = uiModel(loginItem: item)
    await model.setLaunchAtLogin(true)
    #expect(item.calls == ["register"])
    #expect(model.loginItemStatus == .enabled)
    await model.setLaunchAtLogin(false)
    #expect(item.calls == ["register", "unregister"])
    #expect(model.loginItemStatus == .notRegistered)
}

@MainActor
@Test func anApprovalStatusLeavesTheSwitchOff() async {
    let item = FakeLoginItem(.notRegistered)
    item.whenRegistered(becomes: .requiresApproval)
    let model = uiModel(loginItem: item)
    await model.setLaunchAtLogin(true)
    // The switch shows the status after the call, never the value that was asked for.
    #expect(model.loginItemStatus == .requiresApproval)
    #expect(!model.launchAtLoginIsOn)
    #expect(model.launchAtLoginNeedsApproval)
}

@MainActor
@Test func aRefusedRegistrationIsShownAsTheStatusItLeft() async {
    struct Refused: Error {}
    let item = FakeLoginItem(.notRegistered)
    item.whenRegisteredThrows(Refused())
    let model = uiModel(loginItem: item)
    await model.setLaunchAtLogin(true)
    #expect(model.loginItemStatus == .notRegistered)
    #expect(!model.launchAtLoginIsOn)
}

@MainActor
@Test func theAuthorizationIsReadAndCanBeAskedFor() async {
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    centre.whenAsked(grants: .authorized)
    let model = uiModel(centre: centre)
    await model.refreshNotificationAuthorization()
    #expect(model.notificationAuthorization == .notDetermined)
    await model.requestNotificationAuthorization()
    #expect(model.notificationAuthorization == .authorized)
    #expect(centre.requests == 1)
}

@MainActor
@Test func theFirstManualSwitchOnAsksForAuthorizationAndTheSecondDoesNot() async {
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    centre.whenAsked(grants: .authorized)
    let ui = FakeUISettings(fullCharge: false, protectionChanges: false)
    let model = uiModel(centre: centre, ui: ui)
    await model.refreshNotificationAuthorization()
    await model.setNotifyFullChargeFinished(true)
    #expect(ui.notifyFullChargeFinished)
    #expect(model.notifyFullChargeFinished)
    #expect(centre.requests == 1)
    await model.setNotifyProtectionChanges(true)
    #expect(ui.notifyProtectionChanges)
    #expect(model.notifyProtectionChanges)
    #expect(centre.requests == 1)
}

@MainActor
@Test func switchingANotificationOffAsksForNothing() async {
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    let ui = FakeUISettings()
    let model = uiModel(centre: centre, ui: ui)
    await model.setNotifyProtectionChanges(false)
    #expect(!ui.notifyProtectionChanges)
    #expect(centre.requests == 0)
}

@MainActor
@Test func theWelcomeIsPendingUntilItIsOpened() {
    let unseen = uiModel(ui: FakeUISettings(welcomeCompleted: false))
    unseen.publish(.supported)
    #expect(unseen.welcomePending)
    unseen.welcomeOpened()
    #expect(!unseen.welcomePending)

    let seen = uiModel(ui: FakeUISettings(welcomeCompleted: true))
    seen.publish(.supported)
    #expect(!seen.welcomePending)
}

@MainActor
@Test func finishingTheWelcomeRegistersAsksAndStores() async {
    let item = FakeLoginItem(.notRegistered)
    item.whenRegistered(becomes: .enabled)
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    centre.whenAsked(grants: .authorized)
    let ui = FakeUISettings(fullCharge: false, protectionChanges: false)
    let model = uiModel(loginItem: item, centre: centre, ui: ui)
    await model.finishWelcome(launchAtLogin: true, fullCharge: true, protectionChanges: false)
    #expect(item.calls == ["register"])
    #expect(centre.requests == 1)
    #expect(ui.notifyFullChargeFinished)
    #expect(!ui.notifyProtectionChanges)
    #expect(ui.welcomeCompleted)
    #expect(model.loginItemStatus == .enabled)
    #expect(model.notifyFullChargeFinished)
    #expect(!model.notifyProtectionChanges)
}

@MainActor
@Test func finishingTheWelcomeWithEverythingOffAsksForNothing() async {
    let item = FakeLoginItem(.notRegistered)
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    let ui = FakeUISettings(batteryAttention: false)
    let model = uiModel(loginItem: item, centre: centre, ui: ui)
    await model.finishWelcome(launchAtLogin: false, fullCharge: false, protectionChanges: false)
    #expect(item.calls.isEmpty)
    #expect(centre.requests == 0)
    #expect(ui.welcomeCompleted)
}

@MainActor
@Test func theSettingsTabStartsOnGeneralAndCanBeChosen() {
    let model = uiModel()
    #expect(model.settingsTab == .general)
    model.settingsTab = .helper
    #expect(model.settingsTab == .helper)
}

@MainActor
@Test func openSettingsActionIsNilUntilAViewSetsItAndCanThenBeCalled() {
    let model = uiModel()
    #expect(model.openSettingsAction == nil)
    var opened = 0
    model.openSettingsAction = { opened += 1 }
    model.openSettingsAction?()
    #expect(opened == 1)
}

private let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"

@MainActor
@Test func theFirstPowerStepShowsWattsAndLeavesTheAppsMeasuring() async {
    let feed = PowerFeed(energy: [energyReading(10, [(1, xcode, 0)])])
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    #expect(model.power == .empty)
    await model.refreshPower()
    #expect(model.power.readings == PowerReadings(systemWatts: 5, adapterWatts: 6))
    #expect(model.power.apps == nil)
}

@MainActor
@Test func theSecondPowerStepRanksTheApps() async {
    let feed = PowerFeed(energy: [energyReading(10, [(1, xcode, 0)]),
                                  energyReading(12, [(1, xcode, 2_000_000_000)])])
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    await model.refreshPower()
    #expect(model.power.apps == [AppEnergy(name: "Xcode", watts: 1.0)])
}

@MainActor
@Test func aQuietMacShowsAnEmptyListNotNil() async {
    let feed = PowerFeed(energy: [energyReading(10, [(1, xcode, 7)]), energyReading(12, [(1, xcode, 7)])])
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    await model.refreshPower()
    #expect(model.power.apps == [])
}

@MainActor
@Test func resettingForgetsTheSampleSoTheNextStepMeasuresAgain() async {
    let feed = PowerFeed(energy: [energyReading(10, [(1, xcode, 0)]),
                                  energyReading(12, [(1, xcode, 2_000_000_000)])])
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    model.resetPower()
    #expect(model.power == .empty)
    await model.refreshPower()
    #expect(model.power.apps == nil)
}

@MainActor
@Test func aWattsKeyThatDidNotReadLeavesTheOtherRowAndTheAppsAlone() async {
    let feed = PowerFeed(readings: PowerReadings(systemWatts: nil, adapterWatts: 6),
                         energy: [energyReading(10, [(1, xcode, 0)]), energyReading(12, [(1, xcode, 2_000_000_000)])])
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    await model.refreshPower()
    #expect(model.power.readings == PowerReadings(systemWatts: nil, adapterWatts: 6))
    #expect(model.power.apps?.count == 1)
}

@MainActor
@Test func aPowerStepNeverTouchesHealthOrTheEngine() async {
    let feed = PowerFeed(energy: [energyReading(10, [])])
    let model = AppModel(readHealth: { Issue.record("health read by a power step"); return nil },
                         readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    #expect(model.health == .reading)
    #expect(model.snapshot == nil)
}

@MainActor
@Test func powerWattsAreTheMeanOfTheLastThreeReadings() async {
    let feed = PowerFeed(energy: [energyReading(10, [])])
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    var shown: [Double?] = []
    for watts in [5.0, 8, 11, 14] {
        feed.setReadings(PowerReadings(systemWatts: watts, adapterWatts: 6))
        await model.refreshPower()
        shown.append(model.power.readings?.systemWatts)
    }
    #expect(shown == [5, 6.5, 8, 11])
}

@MainActor
@Test func resettingForgetsTheSmoothingWindow() async {
    let feed = PowerFeed(energy: [energyReading(10, [])])
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    feed.setReadings(PowerReadings(systemWatts: 5, adapterWatts: 6))
    await model.refreshPower()
    model.resetPower()
    feed.setReadings(PowerReadings(systemWatts: 9, adapterWatts: 6))
    await model.refreshPower()
    #expect(model.power.readings?.systemWatts == 9)
}

private func pausedFeed() -> PowerFeed {
    PowerFeed(energy: [energyReading(10, [(1, xcode, 0)]),
                       energyReading(12, [(1, xcode, 2_000_000_000)]),
                       energyReading(100, [(1, xcode, 2_000_000_000)]),
                       energyReading(102, [(1, xcode, 6_000_000_000)])])
}

@MainActor
@Test func pausingKeepsTheShownNumbers() async {
    let feed = pausedFeed()
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    await model.refreshPower()
    let before = model.power
    #expect(before.apps == [AppEnergy(name: "Xcode", watts: 1.0)])
    model.pausePower()
    #expect(model.power == before)
}

@MainActor
@Test func theStepAfterAPauseUpdatesTheWattsAndKeepsTheOldApps() async {
    let feed = pausedFeed()
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    feed.setReadings(PowerReadings(systemWatts: 5, adapterWatts: 6))
    await model.refreshPower()
    await model.refreshPower()
    model.pausePower()
    feed.setReadings(PowerReadings(systemWatts: 9, adapterWatts: 6))
    await model.refreshPower()
    #expect(model.power.readings?.systemWatts == 9)
    #expect(model.power.apps == [AppEnergy(name: "Xcode", watts: 1.0)])
}

@MainActor
@Test func theSecondStepAfterAPauseRanksTheAppsOverTheNewInterval() async {
    let feed = pausedFeed()
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    await model.refreshPower()
    model.pausePower()
    await model.refreshPower()
    await model.refreshPower()
    #expect(model.power.apps == [AppEnergy(name: "Xcode", watts: 2.0)])
}

@MainActor
@Test func resettingAfterAPauseStillClearsEverything() async {
    let feed = pausedFeed()
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    await model.refreshPower()
    await model.refreshPower()
    model.pausePower()
    model.resetPower()
    #expect(model.power == .empty)
}

@MainActor
@Test func aFirstEverStepStillLeavesTheAppsNil() async {
    let feed = pausedFeed()
    let model = AppModel(readPower: feed.readPower, sampleEnergy: feed.sampleEnergy)
    model.pausePower()
    await model.refreshPower()
    #expect(model.power.apps == nil)
}

/// A power step whose reading blocks (off the main actor) until `release` is signalled; every wait is bounded,
/// so a broken test fails instead of hanging.
private final class GatedPower: Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let feed: PowerFeed

    init(feed: PowerFeed) { self.feed = feed }

    var readPower: @Sendable () -> PowerReadings {
        { [self] in
            started.signal()
            _ = release.wait(timeout: .now() + 5)
            return feed.readPower()
        }
    }

    private func hasStarted() -> Bool { started.wait(timeout: .now()) == .success }

    /// Returns once the blocked reading has begun; false on timeout.
    @MainActor
    func waitUntilStarted() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !hasStarted() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}

@MainActor
@Test func aStepThatStartedBeforeAPauseChangesNothing() async {
    let feed = pausedFeed()
    let gate = GatedPower(feed: feed)
    let model = AppModel(readPower: gate.readPower, sampleEnergy: feed.sampleEnergy)
    let before = model.power
    let step = Task { await model.refreshPower() }
    #expect(await gate.waitUntilStarted())
    model.pausePower()
    gate.release.signal()
    await step.value
    #expect(model.power == before)
    // The late step left no baseline: the next step is a first one, so the apps stay as they were (nil)
    // and the watts are not averaged with the late reading.
    feed.setReadings(PowerReadings(systemWatts: 9, adapterWatts: 6))
    gate.release.signal()
    await model.refreshPower()
    #expect(model.power.readings?.systemWatts == 9)
    #expect(model.power.apps == nil)
}

@MainActor
@Test func aStepThatStartedBeforeAResetChangesNothing() async {
    let feed = pausedFeed()
    let gate = GatedPower(feed: feed)
    let model = AppModel(readPower: gate.readPower, sampleEnergy: feed.sampleEnergy)
    let step = Task { await model.refreshPower() }
    #expect(await gate.waitUntilStarted())
    model.resetPower()
    gate.release.signal()
    await step.value
    #expect(model.power == .empty)
}

// The Adapter row is decided when the numbers are sampled (the snapshot is fed through `consume`).

private func chargeSnapshot(onAC: Bool, charging: Bool) -> ChargeSnapshot {
    ChargeSnapshot(level: 78, onAC: onAC, charging: charging,
                   thresholds: .standard, protection: true, fullChargeActive: false)
}

@MainActor
private func publishSnapshot(_ snapshot: ChargeSnapshot, to model: AppModel) async {
    let (stream, continuation) = AsyncStream.makeStream(of: ChargeSnapshot.self)
    continuation.yield(snapshot)
    continuation.finish()
    await model.consume(stream)
}

@MainActor
private func adapterShownAfterOneStep(_ snapshot: ChargeSnapshot?) async -> Bool {
    let feedP = PowerFeed(energy: [energyReading(10, [])])
    let model = AppModel(readPower: feedP.readPower, sampleEnergy: feedP.sampleEnergy)
    if let snapshot { await publishSnapshot(snapshot, to: model) }
    await model.refreshPower()
    return model.power.adapterShown
}

@MainActor
@Test func theAdapterRowShowsOnAnAdapterWhileCharging() async {
    #expect(await adapterShownAfterOneStep(chargeSnapshot(onAC: true, charging: true)))
}

@MainActor
@Test func theAdapterRowIsHiddenAtRest() async {
    #expect(await !adapterShownAfterOneStep(chargeSnapshot(onAC: true, charging: false)))
}

@MainActor
@Test func theAdapterRowIsHiddenOnBatteryEvenIfChargingIsReported() async {
    #expect(await !adapterShownAfterOneStep(chargeSnapshot(onAC: false, charging: true)))
}

@MainActor
@Test func theAdapterRowIsHiddenBeforeTheFirstSnapshot() async {
    #expect(await !adapterShownAfterOneStep(nil))
}

@MainActor
@Test func theAdapterRowFreezesWithTheNumbersAndFollowsTheNextSample() async {
    let feedP = PowerFeed(energy: [energyReading(10, [])])
    let model = AppModel(readPower: feedP.readPower, sampleEnergy: feedP.sampleEnergy)
    await publishSnapshot(chargeSnapshot(onAC: true, charging: true), to: model)
    await model.refreshPower()
    #expect(model.power.adapterShown)
    await publishSnapshot(chargeSnapshot(onAC: true, charging: false), to: model)
    model.pausePower()
    #expect(model.power.adapterShown)
    await model.refreshPower()
    #expect(!model.power.adapterShown)
}

@MainActor
@Test func resettingClearsTheAdapterRow() async {
    let feedP = PowerFeed(energy: [energyReading(10, [])])
    let model = AppModel(readPower: feedP.readPower, sampleEnergy: feedP.sampleEnergy)
    await publishSnapshot(chargeSnapshot(onAC: true, charging: true), to: model)
    await model.refreshPower()
    model.resetPower()
    #expect(model.power == .empty)
    #expect(!model.power.adapterShown)
}

// The Power footer: the adapter row is shown and the averaged adapter falls short of the system.

@MainActor
private func adapterFallsShortAfterOneStep(_ readings: PowerReadings, _ snapshot: ChargeSnapshot?) async -> Bool {
    let feedP = PowerFeed(readings: readings, energy: [energyReading(10, [])])
    let model = AppModel(readPower: feedP.readPower, sampleEnergy: feedP.sampleEnergy)
    if let snapshot { await publishSnapshot(snapshot, to: model) }
    await model.refreshPower()
    return model.power.adapterFallsShort
}

@MainActor
@Test func thePowerFooterShowsWhenTheAdapterFallsShort() async {
    let weak = PowerReadings(systemWatts: 30, adapterWatts: 18.7)
    #expect(await adapterFallsShortAfterOneStep(weak, chargeSnapshot(onAC: true, charging: true)))
}

@MainActor
@Test func thePowerFooterIsHiddenWhenTheAdapterCoversTheSystem() async {
    let strong = PowerReadings(systemWatts: 8.3, adapterWatts: 17.4)
    #expect(await !adapterFallsShortAfterOneStep(strong, chargeSnapshot(onAC: true, charging: true)))
}

@MainActor
@Test func thePowerFooterNeedsTheAdapterRow() async {
    let weak = PowerReadings(systemWatts: 30, adapterWatts: 18.7)
    #expect(await !adapterFallsShortAfterOneStep(weak, chargeSnapshot(onAC: true, charging: false)))
    #expect(await !adapterFallsShortAfterOneStep(weak, nil))
}

@MainActor
@Test func resettingClearsThePowerFooter() async {
    let feedP = PowerFeed(readings: PowerReadings(systemWatts: 30, adapterWatts: 18.7),
                          energy: [energyReading(10, [])])
    let model = AppModel(readPower: feedP.readPower, sampleEnergy: feedP.sampleEnergy)
    await publishSnapshot(chargeSnapshot(onAC: true, charging: true), to: model)
    await model.refreshPower()
    #expect(model.power.adapterFallsShort)
    model.resetPower()
    #expect(!model.power.adapterFallsShort)
}

@MainActor
@Test func theBatteryAttentionSwitchIsStoredAndAsksOnFirstSwitchOn() async {
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    centre.whenAsked(grants: .authorized)
    let ui = FakeUISettings(fullCharge: false, protectionChanges: false, batteryAttention: false)
    let model = uiModel(centre: centre, ui: ui)
    await model.refreshNotificationAuthorization()
    #expect(!model.notifyBatteryAttention)
    await model.setNotifyBatteryAttention(true)
    #expect(ui.notifyBatteryAttention)
    #expect(model.notifyBatteryAttention)
    #expect(centre.requests == 1)
    await model.setNotifyBatteryAttention(false)
    #expect(!ui.notifyBatteryAttention)
    #expect(centre.requests == 1)
}

@MainActor
@Test func finishingTheWelcomeWithOnlyTheDefaultAttentionSwitchStillAsks() async {
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    centre.whenAsked(grants: .authorized)
    let model = uiModel(centre: centre, ui: FakeUISettings())
    await model.finishWelcome(launchAtLogin: false, fullCharge: false, protectionChanges: false)
    #expect(centre.requests == 1)
}

private let historyStart = Date(timeIntervalSince1970: 1_800_000_000)

private func historyPoint(_ minutes: Double, level: Int = 80) -> HistoryRecord {
    .point(HistoryPoint(time: historyStart.addingTimeInterval(minutes * 60), level: level, onAC: true,
                        charging: false, resting: true, temperatureCelsius: 30))
}

@MainActor
@Test func theHistoryStartsLoadingAndFillsBothRanges() async {
    let log = HistoryLog(records: [
        historyPoint(0), historyPoint(5, level: 81),
        .health(HealthPoint(day: historyStart, maximumCapacityPercent: 92, cycleCount: 100)),
    ])
    let model = AppModel(readHistory: { log }, now: { historyStart.addingTimeInterval(3_600) })
    #expect(model.history == .loading)
    await model.loadHistory()
    guard case .ready(let content) = model.history else {
        Issue.record("history is \(model.history)")
        return
    }
    #expect(content.week.map(\.level) == [81])
    #expect(content.month.map(\.level) == [81])
    #expect(content.health.map(\.maximumCapacityPercent) == [92])
    #expect(content.generatedAt == historyStart.addingTimeInterval(3_600))
}

@MainActor
@Test func aLogWithNoPointsIsEmpty() async {
    let model = AppModel(readHistory: { HistoryLog() })
    await model.loadHistory()
    #expect(model.history == .empty)
}

@MainActor
@Test func leavingTheTabReleasesTheHistory() async {
    let model = AppModel(readHistory: { HistoryLog(records: [historyPoint(0)]) },
                         now: { historyStart.addingTimeInterval(60) })
    await model.loadHistory()
    #expect(model.history != .loading)
    model.unloadHistory()
    #expect(model.history == .loading)
}

@MainActor
@Test func reloadingKeepsTheOldChartUntilTheNewOneIsReady() async {
    let model = AppModel(readHistory: { HistoryLog(records: [historyPoint(0)]) },
                         now: { historyStart.addingTimeInterval(60) })
    await model.loadHistory()
    let first = model.history
    await model.loadHistory()
    #expect(model.history == first)
}

@MainActor
@Test func theHistoryChartsCarryTheCurrentLimit() async {
    let model = AppModel(readHistory: { HistoryLog(records: [historyPoint(0)]) },
                         now: { historyStart.addingTimeInterval(60) })
    await publishSnapshot(chargeSnapshot(onAC: true, charging: false), to: model)
    #expect(model.historyLimit == .standard)
    await model.loadHistory()
    guard case .ready(let content) = model.history else {
        Issue.record("history is \(model.history)")
        return
    }
    #expect(content.weekChart.limit == .standard)
    #expect(content.monthChart.limit == .standard)
    #expect(content.weekChart.buckets == content.week)
    #expect(content.monthChart.buckets == content.month)
    #expect(content.weekChart.periodEnd == historyStart.addingTimeInterval(60))
}

@MainActor
@Test func theHistoryChartHasNoLimitWhileProtectionIsOff() async {
    let model = AppModel(readHistory: { HistoryLog(records: [historyPoint(0)]) },
                         now: { historyStart.addingTimeInterval(60) })
    let off = ChargeSnapshot(level: 78, onAC: true, charging: false, thresholds: .standard, protection: false,
                             fullChargeActive: false)
    await publishSnapshot(off, to: model)
    #expect(model.historyLimit == nil)
    await model.loadHistory()
    guard case .ready(let content) = model.history else {
        Issue.record("history is \(model.history)")
        return
    }
    #expect(content.weekChart.limit == nil)
}

@MainActor
@Test func theHistoryChartHasNoLimitBeforeTheFirstSnapshot() async {
    let model = AppModel(readHistory: { HistoryLog(records: [historyPoint(0)]) },
                         now: { historyStart.addingTimeInterval(60) })
    #expect(model.historyLimit == nil)
    await model.loadHistory()
    guard case .ready(let content) = model.history else {
        Issue.record("history is \(model.history)")
        return
    }
    #expect(content.monthChart.limit == nil)
}

@MainActor
@Test func aDischargePressReachesTheEngineAndShowsWhenItAnswers() async {
    let harness = EngineHarness(level: 94, adapterPresent: true, subscribe: false)
    let model = model(for: harness)
    Task { await model.consume(harness.engine.snapshots) }
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    #expect(await eventually { model.snapshot?.adapterSwitchAvailable == true })
    await model.setDischarge(true)
    #expect(model.pendingDischarge == nil)
    #expect(model.controlFailure == nil)
    #expect(await eventually { model.snapshot?.dischargeActive == true })
    #expect(harness.helper.adapterCalls == [.off])
    await model.setDischarge(false)
    #expect(await eventually { model.snapshot?.dischargeActive == false })
    #expect(harness.helper.adapterCalls == [.off, .on])
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func aDischargePressWhilePendingIsIgnored() async {
    let harness = EngineHarness(level: 94, adapterPresent: true, subscribe: false)
    let model = model(for: harness)
    Task { await model.consume(harness.engine.snapshots) }
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    #expect(await eventually { model.snapshot?.adapterSwitchAvailable == true })
    harness.helper.delayAdapter(by: .milliseconds(300))
    let first = Task { await model.setDischarge(true) }
    #expect(await eventually { model.isPending })
    #expect(model.pendingDischarge == true)
    await model.setDischarge(false)
    await first.value
    #expect(harness.helper.adapterCalls == [.off])
    #expect(!model.isPending)
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
}

@MainActor
@Test func theDailyUpdateCheckAsksForNotificationsOnlyWhenNothingWasAnswered() async {
    let asking = FakeNotificationCentre(authorization: .notDetermined)
    await uiModel(centre: asking).askForNotificationsIfNeeded()
    #expect(asking.requests == 1)
    let answered = FakeNotificationCentre(authorization: .denied)
    let model = uiModel(centre: answered)
    await model.refreshNotificationAuthorization()
    await model.askForNotificationsIfNeeded()
    #expect(answered.requests == 0)
}
