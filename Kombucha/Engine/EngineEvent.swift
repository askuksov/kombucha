import KombuchaCore
import Synchronization

enum EngineEvent: Sendable {
    case powerChanged(PowerReading)
    case settingsChanged
    case systemWoke
    case helperConnectionLost
    case tick
    case probe(Answer)
    case setProtection(Bool, Answer)
    case setFullCharge(Bool, Answer)
    case setDischarge(Bool, Answer)
    /// The Mac is about to sleep; `WakeMonitor` waits for the answer at most 2 s.
    case willSleep(Answer)
    case installHelper(Answer)
    case removeHelper(Answer)
    case shutdown(Answer)
}

/// What a pass did. `.nothingToDo` and `.wrote` are successes; `.failed` carries the reason.
enum Outcome: Equatable, Sendable {
    case nothingToDo
    case wrote
    case failed(String)
}

enum ActionFailure: Equatable, Sendable {
    case chargerNotReached
    case adapterRequired
    case helperNotInstalled
    case helperNotRemoved
    case noAnswer
}

enum ActionResult: Equatable, Sendable {
    case succeeded
    case failed(ActionFailure)
}

/// The engine's answer to one waiting caller. The first result wins: the engine's, or the caller's
/// own deadline; a late answer is dropped.
final class Answer: Sendable {
    private enum State {
        case pending(CheckedContinuation<ActionResult, Never>?)
        case answered(ActionResult)
        case delivered
    }

    private let state = Mutex(State.pending(nil))

    func resolve(_ result: ActionResult) {
        let waiter: CheckedContinuation<ActionResult, Never>? = state.withLock { state in
            guard case .pending(let waiter) = state else { return nil }
            state = waiter == nil ? .answered(result) : .delivered
            return waiter
        }
        waiter?.resume(returning: result)
    }

    func value(waitingAtMost limit: Duration) async -> ActionResult {
        let deadline = Task {
            guard (try? await Task.sleep(for: limit)) != nil else { return }
            resolve(.failed(.noAnswer))
        }
        defer { deadline.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let (ready, displaced): (ActionResult?, CheckedContinuation<ActionResult, Never>?) = state.withLock { state in
                    switch state {
                    case .answered(let result):
                        state = .delivered
                        return (result, nil)
                    case .pending(let waiter):
                        state = .pending(continuation)
                        return (nil, waiter)
                    case .delivered:
                        return (.failed(.noAnswer), nil)
                    }
                }
                displaced?.resume(returning: .failed(.noAnswer))
                if let ready { continuation.resume(returning: ready) }
            }
        } onCancel: {
            resolve(.failed(.noAnswer))
        }
    }
}
