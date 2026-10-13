import Testing
@testable import Kombucha

@Test func anAnswerGivenBeforeTheCallerWaitsIsDelivered() async {
    let answer = Answer()
    answer.resolve(.succeeded)
    #expect(await answer.value(waitingAtMost: .seconds(1)) == .succeeded)
}

@Test func anAnswerGivenWhileTheCallerWaitsIsDelivered() async {
    let answer = Answer()
    Task {
        try? await Task.sleep(for: .milliseconds(50))
        answer.resolve(.failed(.adapterRequired))
    }
    #expect(await answer.value(waitingAtMost: .seconds(1)) == .failed(.adapterRequired))
}

@Test func aCallerThatWaitsTooLongGetsNoAnswerAndTheLateAnswerIsDropped() async {
    let answer = Answer()
    let started = ContinuousClock.now
    #expect(await answer.value(waitingAtMost: .milliseconds(100)) == .failed(.noAnswer))
    #expect(ContinuousClock.now - started < .seconds(1))
    answer.resolve(.succeeded)
    // A stored late answer would come back here as `.succeeded`.
    #expect(await answer.value(waitingAtMost: .zero) == .failed(.noAnswer))
}

@Test func aCancelledCallerStopsWaitingAtOnce() async {
    let answer = Answer()
    let started = ContinuousClock.now
    let waiter = Task { await answer.value(waitingAtMost: .seconds(5)) }
    try? await Task.sleep(for: .milliseconds(50))
    waiter.cancel()
    #expect(await waiter.value == .failed(.noAnswer))
    #expect(ContinuousClock.now - started < .seconds(1))
}
