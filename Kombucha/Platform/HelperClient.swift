import Foundation
import HelperProtocol

enum HelperCallError: Error, Equatable, Sendable {
    case transport(String)
    case timedOut
}

struct ChargeReply: Equatable, Sendable {
    let result: HelperResult
    let detail: String
}

protocol HelperConnecting: Sendable {
    func ping() async -> Result<Int, HelperCallError>
    func setCharging(allow: Bool) async -> Result<ChargeReply, HelperCallError>
    /// Protocol 2 only: the engine checks the helper's version first.
    func setAdapter(enabled: Bool, leaseSeconds: Int) async -> Result<ChargeReply, HelperCallError>
    func dropConnection()
}

final class HelperClient: HelperConnecting, @unchecked Sendable {
    static let deadline: DispatchTimeInterval = .seconds(2)

    private let deadline: DispatchTimeInterval
    private let makeConnection: @Sendable () -> NSXPCConnection
    private let onConnectionLost: @Sendable () -> Void
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    init(deadline: DispatchTimeInterval = HelperClient.deadline,
         onConnectionLost: @escaping @Sendable () -> Void,
         makeConnection: @escaping @Sendable () -> NSXPCConnection) {
        self.deadline = deadline
        self.onConnectionLost = onConnectionLost
        self.makeConnection = makeConnection
    }

    deinit {
        drop(connection)
    }

    static func machService(requirement: String) -> @Sendable () -> NSXPCConnection {
        {
            let connection = NSXPCConnection(machServiceName: HelperIdentity.machServiceName, options: .privileged)
            connection.setCodeSigningRequirement(requirement)
            return connection
        }
    }

    func ping() async -> Result<Int, HelperCallError> {
        await call { proxy, done in
            proxy.ping { version in done(version) }
        }
    }

    func setCharging(allow: Bool) async -> Result<ChargeReply, HelperCallError> {
        let raw = await call { (proxy, done: @escaping @Sendable ((Int, String)) -> Void) in
            proxy.setCharging(allow: allow) { code, detail in done((code, detail)) }
        }
        return raw.map { code, detail in
            ChargeReply(result: HelperResult(rawValue: code) ?? .failed, detail: detail)
        }
    }

    func setAdapter(enabled: Bool, leaseSeconds: Int) async -> Result<ChargeReply, HelperCallError> {
        let raw = await call { (proxy, done: @escaping @Sendable ((Int, String)) -> Void) in
            proxy.setAdapter(enabled: enabled, leaseSeconds: leaseSeconds) { code, detail in done((code, detail)) }
        }
        return raw.map { code, detail in
            ChargeReply(result: HelperResult(rawValue: code) ?? .failed, detail: detail)
        }
    }

    func dropConnection() {
        drop(lock.withLock { connection })
    }

    // NSXPC has no reply timeout, and a job whose executable is gone never answers.
    private func call<Value: Sendable>(
        _ body: (KombuchaHelperProtocol, @escaping @Sendable (Value) -> Void) -> Void
    ) async -> Result<Value, HelperCallError> {
        let connection = currentConnection()
        let result: Result<Value, HelperCallError> = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(.failure(.transport(error.localizedDescription)))
            }
            guard let helper = proxy as? KombuchaHelperProtocol else {
                once.resume(.failure(.transport("the proxy does not implement the helper protocol")))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
                once.resume(.failure(.timedOut))
            }
            body(helper) { value in once.resume(.success(value)) }
        }
        if case .failure = result {
            drop(connection)
        }
        return result
    }

    private func currentConnection() -> NSXPCConnection {
        lock.withLock {
            if let connection { return connection }
            let created = makeConnection()
            created.remoteObjectInterface = NSXPCInterface(with: KombuchaHelperProtocol.self)
            let lost = onConnectionLost
            // An interrupted connection is rebuilt by NSXPC on the next message; an invalidated one never is.
            created.interruptionHandler = { lost() }
            created.invalidationHandler = { [weak self, weak created] in
                self?.forget(created)
                lost()
            }
            created.resume()
            connection = created
            return created
        }
    }

    // Only the connection a call used is dropped: a failure from an older one leaves its replacement alone.
    private func drop(_ target: NSXPCConnection?) {
        guard let target else { return }
        let owned = lock.withLock {
            guard connection === target else { return false }
            connection = nil
            return true
        }
        guard owned else { return }
        // A deliberate drop is not a lost connection.
        target.interruptionHandler = nil
        target.invalidationHandler = nil
        target.invalidate()
    }

    private func forget(_ target: NSXPCConnection?) {
        lock.withLock {
            if let target, connection === target { connection = nil }
        }
    }
}
