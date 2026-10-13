import Dispatch
import Synchronization

/// Counts calls from any thread; a test can wait for the next one.
final class Occurrences: Sendable {
    private let calls = Mutex(0)
    private let signal = DispatchSemaphore(value: 0)

    var count: Int { calls.withLock { $0 } }

    func record() {
        calls.withLock { $0 += 1 }
        signal.signal()
    }

    /// True when a call arrived within the time.
    func wait(seconds: Double) -> Bool {
        signal.wait(timeout: .now() + seconds) == .success
    }
}
