import KombuchaCore
import Testing
@testable import Kombucha

@Test func aCallerStopsWaitingAtItsLimitAndTheEventStaysQueued() async {
    let harness = EngineHarness(level: 78, timing: Engine.Timing(tick: .seconds(60), callerWait: .milliseconds(100)))
    _ = await harness.engine.start()
    #expect(await harness.engine.setProtection(false) == .failed(.noAnswer))
    // Queued, not handled: nothing consumes the queue until the loop runs.
    #expect(harness.settings.chargeSettings.protection == true)
    let ended = harness.runLoop()
    #expect(await harness.engine.shutdown(waitingAtMost: .seconds(2)) == .succeeded)
    #expect(await eventually { ended.isRaised })
    #expect(harness.settings.chargeSettings.protection == false)
}

@Test func aQuietLoopRunsAPassOnEveryTick() async {
    let harness = EngineHarness(level: 78, timing: Engine.Timing(tick: .milliseconds(100), callerWait: .seconds(1)))
    _ = await harness.engine.start()
    let reads = harness.power.reads
    let started = ContinuousClock.now
    let ended = harness.runLoop()
    #expect(await eventually { harness.power.reads - reads >= 3 })
    // Three ticks cannot come sooner than three intervals; a loop spinning on its tick would.
    #expect(ContinuousClock.now - started >= .milliseconds(300))
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
    #expect(harness.helper.commands == [true])
}

@Test func eventsFromProducersReachTheLoopInOrder() async {
    let harness = EngineHarness(level: 78, timing: Engine.Timing(tick: .seconds(60), callerWait: .seconds(1)))
    _ = await harness.engine.start()
    let ended = harness.runLoop()
    harness.inbox.post(.powerChanged(harness.reading(80)))
    harness.inbox.post(.powerChanged(harness.reading(76)))
    harness.inbox.post(.powerChanged(harness.reading(75)))
    _ = await harness.engine.shutdown(waitingAtMost: .seconds(1))
    #expect(await eventually { ended.isRaised })
    #expect(harness.helper.commands == [true, false, true])
}
