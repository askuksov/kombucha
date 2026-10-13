import Synchronization

/// One ordered record of the writes several fakes were asked for.
final class CallLog: Sendable {
    private let lines = Mutex<[String]>([])
    var entries: [String] { lines.withLock { $0 } }
    func note(_ line: String) { lines.withLock { $0.append(line) } }
}
