import Dispatch
import Testing
@testable import Kombucha

// The numbers are IOMessage.h's iokit_common_msg() values, written out so the tests pin them.

@Test func aSleepQueryIsAllowedAtOnce() {
    #expect(WakeMonitor.response(to: 0xE000_0270) == .allowSleep)  // can system sleep
}

@Test func aComingSleepAsksTheEngineFirst() {
    #expect(WakeMonitor.response(to: 0xE000_0280) == .willSleep)  // system will sleep
    #expect(WakeMonitor.engineWait == .seconds(2))
}

@Test func aWakeIsPosted() {
    #expect(WakeMonitor.response(to: 0xE000_0300) == .woke)  // system has powered on
}

@Test func otherPowerMessagesAreIgnored() {
    #expect(WakeMonitor.response(to: 0xE000_0290) == .ignore)  // system will not sleep
    #expect(WakeMonitor.response(to: 0xE000_0320) == .ignore)  // system will power on
}

/// Runs the blocking wait on a dispatch thread, as the monitor's own queue does; never on the cooperative pool.
private func waitOnADispatchThread(limit: Duration,
                                   _ post: @escaping @Sendable (Answer) -> Bool) async -> (answered: Bool, took: Duration) {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            let started = ContinuousClock.now
            let answered = WakeMonitor.waitForEngine(limit: limit, post)
            continuation.resume(returning: (answered, ContinuousClock.now - started))
        }
    }
}

@Test func theWaitEndsAsSoonAsTheEngineAnswers() async {
    let result = await waitOnADispatchThread(limit: .seconds(2)) { answer in
        answer.resolve(.succeeded)
        return true
    }
    #expect(result.answered)
    #expect(result.took < .milliseconds(500))
}

@Test func theWaitNeverOutlastsItsLimit() async {
    let result = await waitOnADispatchThread(limit: .milliseconds(200)) { _ in true }
    #expect(!result.answered)
    #expect(result.took < .seconds(1))
}

@Test func anEndedLoopIsNotWaitedFor() async {
    let result = await waitOnADispatchThread(limit: .seconds(2)) { _ in false }
    #expect(!result.answered)
    #expect(result.took < .milliseconds(100))
}
