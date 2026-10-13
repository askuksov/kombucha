import KombuchaCore
import Testing
@testable import Kombucha

@Test func aCallAfterTheLoopEndedFailsAtOnce() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
    let started = ContinuousClock.now
    #expect(await harness.engine.setProtection(false) == .failed(.noAnswer))
    #expect(ContinuousClock.now - started < .seconds(1))
    #expect(harness.settings.chargeSettings.protection == true)
}

@Test func theSnapshotStreamEndsWithTheLoop() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
    #expect(await eventually { harness.snapshotsEnded.isRaised })
}

@Test func anUnsupportedMacEndsBothStreams() async {
    let harness = EngineHarness(hasInternalBattery: false)
    #expect(await harness.engine.start() == .noBattery)
    #expect(await eventually { harness.snapshotsEnded.isRaised })
    let started = ContinuousClock.now
    #expect(await harness.engine.probe() == .failed(.noAnswer))
    #expect(ContinuousClock.now - started < .seconds(1))
}

@Test func aSecondLoopIsRefusedAndTheFirstKeepsRunning() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    let first = harness.runLoop()
    let second = harness.runLoop()
    #expect(await eventually { first.isRaised || second.isRaised })
    #expect(!(first.isRaised && second.isRaised))
    harness.inbox.post(.powerChanged(harness.reading(80)))
    #expect(await harness.engine.shutdown(waitingAtMost: .seconds(1)) == .succeeded)
    #expect(await eventually { first.isRaised && second.isRaised })
    #expect(harness.helper.commands == [true, false, true])
}

@Test func aRestartPublishesItsFirstSnapshotAgain() async {
    let harness = EngineHarness(level: 78)
    _ = await harness.engine.start()
    _ = await harness.engine.start()
    #expect(await harness.snapshots(2).count == 2)
}

@Test func withoutASubscriberOnlyTheNewestSnapshotIsKept() async {
    let harness = EngineHarness(level: 78, snapshotBuffer: .bufferingNewest(1), subscribe: false)
    _ = await harness.engine.start()
    _ = await harness.engine.handle(.powerChanged(harness.reading(79)))
    _ = await harness.engine.handle(.powerChanged(harness.reading(80)))
    var snapshots = harness.engine.snapshots.makeAsyncIterator()
    #expect(await snapshots.next()?.level == 80)
}
