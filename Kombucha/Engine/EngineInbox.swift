/// The engine's single queue. Every producer posts here; only the engine's loop consumes.
final class EngineInbox: Sendable {
    let events: AsyncStream<EngineEvent>
    private let continuation: AsyncStream<EngineEvent>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    /// False once the loop has ended: nobody will handle the event.
    @discardableResult
    func post(_ event: EngineEvent) -> Bool {
        if case .enqueued = continuation.yield(event) { return true }
        return false
    }

    func finish() {
        continuation.finish()
    }
}
