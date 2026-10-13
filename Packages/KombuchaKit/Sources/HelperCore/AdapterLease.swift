import Dispatch
import Synchronization

/// Runs work once after a delay. Injected so tests move time by hand.
public protocol LeaseScheduler: Sendable {
    func schedule(after seconds: Int, _ work: @escaping @Sendable () -> Void) -> LeaseTimer
}

/// Cancels one scheduled item. A cancel that comes too late is harmless: the lease checks its own state.
public struct LeaseTimer: Sendable {
    private let onCancel: @Sendable () -> Void

    public init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel()
    }
}

/// The real clock: uptime, so the lease does not run while the Mac sleeps. Sleep switches the adapter on anyway.
public struct DispatchLeaseScheduler: LeaseScheduler {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = DispatchQueue(label: "dev.kuksov.kombucha.helper.lease")) {
        self.queue = queue
    }

    public func schedule(after seconds: Int, _ work: @escaping @Sendable () -> Void) -> LeaseTimer {
        let pending = PendingWork(work)
        queue.asyncAfter(deadline: .now() + .seconds(seconds), execute: pending.item)
        return LeaseTimer(onCancel: { pending.item.cancel() })
    }
}

/// `DispatchWorkItem` is thread-safe but not declared `Sendable`.
private final class PendingWork: @unchecked Sendable {
    let item: DispatchWorkItem

    init(_ work: @escaping @Sendable () -> Void) {
        item = DispatchWorkItem(block: work)
    }
}

/// The helper's guard on a switched-off adapter: unless granted again in time, it calls back once.
public final class AdapterLease: Sendable {
    private struct State {
        var generation = 0
        var armed = false
        var timer: LeaseTimer?
    }

    private let scheduler: any LeaseScheduler
    private let state = Mutex(State())

    public init(scheduler: any LeaseScheduler) {
        self.scheduler = scheduler
    }

    public var isArmed: Bool { state.withLock { $0.armed } }

    /// Restarts the deadline; an earlier deadline no longer fires.
    public func grant(seconds: Int, onExpiry: @escaping @Sendable () -> Void) {
        state.withLock { state in
            state.timer?.cancel()
            state.generation += 1
            state.armed = true
            let generation = state.generation
            state.timer = scheduler.schedule(after: seconds) { [weak self] in
                self?.expire(generation, onExpiry)
            }
        }
    }

    public func cancel() {
        state.withLock { state in
            state.timer?.cancel()
            state.timer = nil
            state.armed = false
            state.generation += 1
        }
    }

    /// Only the newest grant may fire, and only once.
    private func expire(_ generation: Int, _ onExpiry: @Sendable () -> Void) {
        let due = state.withLock { state in
            guard state.armed, state.generation == generation else { return false }
            state.armed = false
            state.timer = nil
            return true
        }
        if due { onExpiry() }
    }
}
