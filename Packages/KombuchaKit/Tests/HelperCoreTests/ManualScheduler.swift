import HelperCore
import Synchronization

/// A clock for the lease that moves only when a test says so.
final class ManualScheduler: LeaseScheduler {
    private struct Entry: Sendable {
        let id: Int
        let due: Int
        let work: @Sendable () -> Void
    }

    private struct State {
        var now = 0
        var nextID = 0
        var pending: [Entry] = []
        var cancelled: [Entry] = []
    }

    private let state = Mutex(State())

    var pendingCount: Int { state.withLock { $0.pending.count } }

    func schedule(after seconds: Int, _ work: @escaping @Sendable () -> Void) -> LeaseTimer {
        let id: Int = state.withLock { state in
            state.nextID += 1
            state.pending.append(Entry(id: state.nextID, due: state.now + seconds, work: work))
            return state.nextID
        }
        return LeaseTimer(onCancel: { [self] in
            state.withLock { state in
                if let index = state.pending.firstIndex(where: { $0.id == id }) {
                    state.cancelled.append(state.pending.remove(at: index))
                }
            }
        })
    }

    /// Moves the clock and runs, in order and outside the lock, every item that came due.
    func advance(by seconds: Int) {
        let due: [Entry] = state.withLock { state in
            state.now += seconds
            let ready = state.pending.filter { $0.due <= state.now }.sorted { $0.due < $1.due }
            state.pending.removeAll { $0.due <= state.now }
            return ready
        }
        due.forEach { $0.work() }
    }

    /// Runs the items that were cancelled, as a timer does that fired just before its cancel arrived.
    func runCancelled() {
        let stale: [Entry] = state.withLock { state in
            let cancelled = state.cancelled
            state.cancelled = []
            return cancelled
        }
        stale.forEach { $0.work() }
    }
}
