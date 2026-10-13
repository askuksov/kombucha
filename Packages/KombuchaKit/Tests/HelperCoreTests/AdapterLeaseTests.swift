import Dispatch
import Testing
@testable import HelperCore

@Test func aGrantFiresOnceAtItsDeadline() {
    let scheduler = ManualScheduler()
    let lease = AdapterLease(scheduler: scheduler)
    let expiries = Occurrences()
    lease.grant(seconds: 180) { expiries.record() }
    scheduler.advance(by: 179)
    #expect(expiries.count == 0)
    #expect(lease.isArmed)
    scheduler.advance(by: 1)
    #expect(expiries.count == 1)
    #expect(!lease.isArmed)
    scheduler.advance(by: 1000)
    #expect(expiries.count == 1)
}

@Test func aNewGrantRestartsTheDeadline() {
    let scheduler = ManualScheduler()
    let lease = AdapterLease(scheduler: scheduler)
    let expiries = Occurrences()
    lease.grant(seconds: 180) { expiries.record() }
    scheduler.advance(by: 120)
    lease.grant(seconds: 180) { expiries.record() }
    scheduler.advance(by: 120)
    #expect(expiries.count == 0)
    #expect(scheduler.pendingCount == 1)
    scheduler.advance(by: 60)
    #expect(expiries.count == 1)
}

@Test func aCancelledLeaseNeverFires() {
    let scheduler = ManualScheduler()
    let lease = AdapterLease(scheduler: scheduler)
    let expiries = Occurrences()
    lease.grant(seconds: 180) { expiries.record() }
    lease.cancel()
    #expect(!lease.isArmed)
    scheduler.advance(by: 1000)
    #expect(expiries.count == 0)
}

@Test func aTimerThatFiresAfterItWasReplacedDoesNothing() {
    let scheduler = ManualScheduler()
    let lease = AdapterLease(scheduler: scheduler)
    let expiries = Occurrences()
    lease.grant(seconds: 180) { expiries.record() }
    lease.grant(seconds: 180) { expiries.record() }
    scheduler.runCancelled()
    #expect(expiries.count == 0)
    #expect(lease.isArmed)
    scheduler.advance(by: 180)
    #expect(expiries.count == 1)
}

@Test func aTimerThatFiresAfterTheCancelDoesNothing() {
    let scheduler = ManualScheduler()
    let lease = AdapterLease(scheduler: scheduler)
    let expiries = Occurrences()
    lease.grant(seconds: 180) { expiries.record() }
    lease.cancel()
    scheduler.runCancelled()
    #expect(expiries.count == 0)
}

@Test func theDispatchSchedulerRunsWorkAndCanCancelIt() {
    let scheduler = DispatchLeaseScheduler()
    let runs = Occurrences()
    _ = scheduler.schedule(after: 0) { runs.record() }
    #expect(runs.wait(seconds: 2))
    let cancelled = Occurrences()
    let timer = scheduler.schedule(after: 1) { cancelled.record() }
    timer.cancel()
    #expect(!cancelled.wait(seconds: 1.5))
}
