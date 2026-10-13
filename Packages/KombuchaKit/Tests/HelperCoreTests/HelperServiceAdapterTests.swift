import Foundation
import HelperProtocol
import SMCKit
import Synchronization
import Testing
@testable import HelperCore

/// An adapter switch in memory. Writes land and reads give the last value written, unless a failure is scripted.
final class RecordingAdapter: AdapterWriting {
    private struct State {
        var enabled: Bool?
        var calls: [Bool] = []
        var writeFailures: [SMCError] = []
        var readFailure: SMCError?
    }

    private let state: Mutex<State>
    private let log: CallLog?

    init(enabled: Bool? = true, log: CallLog? = nil) {
        state = Mutex(State(enabled: enabled))
        self.log = log
    }

    /// `true` for each enable and `false` for each disable, in order, landed or not.
    var recorded: [Bool] { state.withLock { $0.calls } }

    /// The next writes fail with these errors, one each, in order.
    func failWrites(_ errors: SMCError...) { state.withLock { $0.writeFailures.append(contentsOf: errors) } }

    func failReads(with error: SMCError) { state.withLock { $0.readFailure = error } }

    func setAdapter(enabled: Bool) throws {
        log?.note(enabled ? "adapter on" : "adapter off")
        let failure: SMCError? = state.withLock { state in
            state.calls.append(enabled)
            guard state.writeFailures.isEmpty else { return state.writeFailures.removeFirst() }
            state.enabled = enabled
            return nil
        }
        if let failure { throw failure }
    }

    func currentlyEnabled() throws -> Bool? {
        let (value, failure) = state.withLock { ($0.enabled, $0.readFailure) }
        if let failure { throw failure }
        return value
    }
}

/// One reply, captured synchronously: the service replies before `setAdapter` returns.
private final class Reply: Sendable {
    private let value = Mutex<(Int, String)?>(nil)
    var code: Int? { value.withLock { $0?.0 } }
    var detail: String? { value.withLock { $0?.1 } }
    func record(_ code: Int, _ detail: String) { value.withLock { $0 = (code, detail) } }
}

/// Stands in for an XPC connection: a client is told apart by the object it came over.
private final class Connection {}

private func makeService(_ adapter: RecordingAdapter?,
                     _ scheduler: ManualScheduler = ManualScheduler(),
                     writer: RecordingWriter = RecordingWriter(),
                     exits: Occurrences = Occurrences()) -> HelperService {
    HelperService(writer: writer, adapter: adapter, scheduler: scheduler, exitProcess: { exits.record() })
}

@discardableResult
private func send(_ service: HelperService, enabled: Bool, lease: Int = 180, client: ClientID? = nil) -> Reply {
    let reply = Reply()
    service.setAdapter(enabled: enabled, leaseSeconds: lease, client: client) { reply.record($0, $1) }
    return reply
}

// MARK: lease

@Test func aDisableLandsAndTheLeaseSwitchesTheAdapterBackOnAtItsDeadline() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    let reply = send(service, enabled: false)
    #expect(reply.code == HelperResult.done.rawValue)
    #expect(reply.detail == "setAdapter: disable — done")
    scheduler.advance(by: 179)
    #expect(adapter.recorded == [false])
    scheduler.advance(by: 1)
    #expect(adapter.recorded == [false, true])
    scheduler.advance(by: 1000)
    #expect(adapter.recorded == [false, true])
}

@Test func everyDisableRestartsTheDeadline() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false)
    scheduler.advance(by: 120)
    send(service, enabled: false)
    scheduler.advance(by: 120)
    #expect(adapter.recorded == [false, false])
    scheduler.advance(by: 60)
    #expect(adapter.recorded == [false, false, true])
}

@Test func anEnableEndsTheLease() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false)
    let reply = send(service, enabled: true)
    #expect(reply.detail == "setAdapter: enable — done")
    scheduler.advance(by: 1000)
    #expect(adapter.recorded == [false, true])
}

@Test func theLeaseIsKeptWithinItsRange() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false, lease: 0)
    scheduler.advance(by: 1)
    #expect(adapter.recorded == [false, true])
    send(service, enabled: false, lease: 100_000)
    scheduler.advance(by: 599)
    #expect(adapter.recorded == [false, true, false])
    scheduler.advance(by: 1)
    #expect(adapter.recorded == [false, true, false, true])
}

@Test func aRenewThatTakesTheLockFirstWinsOverTheExpiry() {
    let adapter = RecordingAdapter()
    let service = makeService(adapter)
    send(service, enabled: false)
    // The timer fired, and a renew armed the lease again before the expiry got the lock.
    service.leaseExpired()
    #expect(adapter.recorded == [false])
}

@Test func aRenewAfterTheExpirySwitchesTheAdapterOffAgainWithAFreshLease() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false)
    scheduler.advance(by: 180)
    #expect(adapter.recorded == [false, true])
    // The app was hung; its next pass still wants the discharge.
    send(service, enabled: false)
    scheduler.advance(by: 179)
    #expect(adapter.recorded == [false, true, false])
    scheduler.advance(by: 1)
    #expect(adapter.recorded == [false, true, false, true])
}

// MARK: failures

@Test func withoutTheKeyEverySetAdapterFails() {
    let service = makeService(nil)
    let off = send(service, enabled: false)
    #expect(off.code == HelperResult.failed.rawValue)
    #expect(off.detail == "setAdapter: disable — failed: adapter key not found")
    #expect(send(service, enabled: true).detail == "setAdapter: enable — failed: adapter key not found")
}

@Test func aDisableThatDidNotLandIsUndoneAndArmsNothing() {
    let adapter = RecordingAdapter()
    adapter.failWrites(.writeNotApplied(wrote: [0x08], read: [0x00]))
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    let reply = send(service, enabled: false)
    #expect(reply.code == HelperResult.failed.rawValue)
    #expect(reply.detail?.hasPrefix("setAdapter: disable — failed:") == true)
    #expect(adapter.recorded == [false, true])
    scheduler.advance(by: 1000)
    #expect(adapter.recorded == [false, true])
}

@Test func aFailedEnableKeepsTheLeaseSoTheExpiryTriesAgain() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false)
    adapter.failWrites(.permissionDenied)
    #expect(send(service, enabled: true).code == HelperResult.failed.rawValue)
    scheduler.advance(by: 180)
    #expect(adapter.recorded == [false, true, true])
}

@Test func anExpiryThatCannotSwitchTheAdapterOnArmsTheLeaseAgain() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false)
    adapter.failWrites(.permissionDenied)
    scheduler.advance(by: 180)
    #expect(adapter.recorded == [false, true])
    #expect(scheduler.pendingCount == 1)
    scheduler.advance(by: 180)
    #expect(adapter.recorded == [false, true, true])
    #expect(scheduler.pendingCount == 0)
    // The adapter is on and nothing is armed any more.
    scheduler.advance(by: 1000)
    #expect(adapter.recorded == [false, true, true])
}

@Test func aClientThatLeavesWhenTheEnableFailsLeavesTheLeaseArmed() {
    let client = Connection()
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false, client: ClientID(object: client))
    adapter.failWrites(.permissionDenied)
    service.clientLeft(ClientID(object: client))
    #expect(adapter.recorded == [false, true])
    #expect(scheduler.pendingCount == 1)
    scheduler.advance(by: 180)
    #expect(adapter.recorded == [false, true, true])
    #expect(scheduler.pendingCount == 0)
    withExtendedLifetime(client) {}
}

@Test func aRenewWhoseDisableAndUndoBothFailLeavesTheLeaseArmed() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false)
    adapter.failWrites(.permissionDenied, .permissionDenied)
    #expect(send(service, enabled: false).code == HelperResult.failed.rawValue)
    #expect(adapter.recorded == [false, false, true])
    #expect(scheduler.pendingCount == 1)
    scheduler.advance(by: 180)
    #expect(adapter.recorded == [false, false, true, true])
    #expect(scheduler.pendingCount == 0)
}

@Test func aFirstDisableWhoseUndoFailsTooArmsTheRequestedLease() {
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    adapter.failWrites(.permissionDenied, .permissionDenied)
    send(service, enabled: false, lease: 60)
    #expect(scheduler.pendingCount == 1)
    scheduler.advance(by: 59)
    #expect(adapter.recorded == [false, true])
    scheduler.advance(by: 1)
    #expect(adapter.recorded == [false, true, true])
}

@Test func aKeyFoundOffAtStartThatCannotBeSwitchedOnArmsTheDefaultLease() {
    let adapter = RecordingAdapter(enabled: false)
    let scheduler = ManualScheduler()
    adapter.failWrites(.permissionDenied)
    let service = makeService(adapter, scheduler)
    service.restoreAdapterAtStart()
    #expect(scheduler.pendingCount == 1)
    scheduler.advance(by: 180)
    #expect(adapter.recorded == [true, true])
}

// MARK: the connection

@Test func theClientThatSwitchedTheAdapterOffLeavingSwitchesItBackOn() {
    let first = Connection()
    let second = Connection()
    let adapter = RecordingAdapter()
    let scheduler = ManualScheduler()
    let service = makeService(adapter, scheduler)
    send(service, enabled: false, client: ClientID(object: first))
    service.clientLeft(ClientID(object: second))
    #expect(adapter.recorded == [false])
    service.clientLeft(ClientID(object: first))
    #expect(adapter.recorded == [false, true])
    scheduler.advance(by: 1000)
    #expect(adapter.recorded == [false, true])
    withExtendedLifetime((first, second)) {}
}

@Test func aClientLeavingAfterItsEnableChangesNothing() {
    let client = Connection()
    let adapter = RecordingAdapter()
    let service = makeService(adapter)
    send(service, enabled: false, client: ClientID(object: client))
    send(service, enabled: true, client: ClientID(object: client))
    service.clientLeft(ClientID(object: client))
    #expect(adapter.recorded == [false, true])
    withExtendedLifetime(client) {}
}

@Test func theLatestDisableOwnsTheAdapter() {
    let first = Connection()
    let second = Connection()
    let adapter = RecordingAdapter()
    let service = makeService(adapter)
    send(service, enabled: false, client: ClientID(object: first))
    send(service, enabled: false, client: ClientID(object: second))
    service.clientLeft(ClientID(object: first))
    #expect(adapter.recorded == [false, false])
    service.clientLeft(ClientID(object: second))
    #expect(adapter.recorded == [false, false, true])
    withExtendedLifetime((first, second)) {}
}

// MARK: start, sleep, retire, stop

@Test func aKeyFoundOffAtStartIsSwitchedOn() {
    let adapter = RecordingAdapter(enabled: false)
    makeService(adapter).restoreAdapterAtStart()
    #expect(adapter.recorded == [true])
}

@Test func aKeyFoundOnAtStartIsLeftAlone() {
    let adapter = RecordingAdapter(enabled: true)
    makeService(adapter).restoreAdapterAtStart()
    #expect(adapter.recorded.isEmpty)
}

@Test func aKeyThatCannotBeReadOrHoldsAStrangeValueIsSwitchedOn() {
    let unreadable = RecordingAdapter(enabled: true)
    unreadable.failReads(with: .smcResult(0x85))
    makeService(unreadable).restoreAdapterAtStart()
    #expect(unreadable.recorded == [true])
    let strange = RecordingAdapter(enabled: nil)
    makeService(strange).restoreAdapterAtStart()
    #expect(strange.recorded == [true])
}

@Test func sleepSwitchesTheAdapterOnAndRefusesADisableUntilTheWake() {
    let adapter = RecordingAdapter()
    let service = makeService(adapter)
    send(service, enabled: false)
    service.systemWillSleep()
    #expect(adapter.recorded == [false, true])
    let refused = send(service, enabled: false)
    #expect(refused.code == HelperResult.failed.rawValue)
    #expect(refused.detail == "setAdapter: disable — failed: the system is going to sleep")
    #expect(adapter.recorded == [false, true])
    #expect(send(service, enabled: true).code == HelperResult.done.rawValue)
    service.systemDidWake()
    #expect(send(service, enabled: false).code == HelperResult.done.rawValue)
    #expect(adapter.recorded == [false, true, true, false])
}

@Test func sleepWithTheAdapterOnWritesNothing() {
    let adapter = RecordingAdapter(enabled: true)
    makeService(adapter).systemWillSleep()
    #expect(adapter.recorded.isEmpty)
}

@Test func retiringReleasesTheChargerThenSwitchesTheAdapterOn() {
    let log = CallLog()
    let exits = Occurrences()
    let adapter = RecordingAdapter(enabled: false, log: log)
    makeService(adapter, writer: RecordingWriter(log: log), exits: exits).retire(because: "a test")
    #expect(log.entries == ["allow", "adapter on"])
    #expect(exits.count == 1)
}

@Test func stoppingSwitchesTheAdapterOnAndLeavesTheChargerAlone() {
    let log = CallLog()
    let exits = Occurrences()
    let adapter = RecordingAdapter(enabled: false, log: log)
    makeService(adapter, writer: RecordingWriter(log: log), exits: exits).stop(because: "a test")
    #expect(log.entries == ["adapter on"])
    #expect(exits.count == 1)
}

@Test func stoppingWithoutTheKeyStillEnds() {
    let exits = Occurrences()
    makeService(nil, exits: exits).stop(because: "a test")
    #expect(exits.count == 1)
}
