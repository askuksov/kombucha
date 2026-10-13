import Synchronization

/// Delivers the first result and drops the rest: a reply, a transport error and the deadline
/// can all reach the same call.
final class ResumeOnce<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Result<Value, HelperCallError>, Never>?>

    init(_ continuation: CheckedContinuation<Result<Value, HelperCallError>, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ result: Result<Value, HelperCallError>) {
        let pending = continuation.withLock { stored in
            defer { stored = nil }
            return stored
        }
        pending?.resume(returning: result)
    }
}
