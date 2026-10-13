import Foundation
import HelperProtocol
import Testing
@testable import Kombucha

/// An in-process stand-in for the helper, reached through an anonymous listener.
private final class StandInHelper: NSObject, KombuchaHelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var pingDelay: TimeInterval = 0
    private var accepting = true
    private var peers: [NSXPCConnection] = []
    let peerEnds = Tally()

    override init() {
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func delayPings(by seconds: TimeInterval) { lock.withLock { pingDelay = seconds } }
    func refuseCallers() { lock.withLock { accepting = false } }
    func invalidatePeers() { lock.withLock { peers }.forEach { $0.invalidate() } }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard lock.withLock({ accepting }) else { return false }
        connection.exportedInterface = NSXPCInterface(with: KombuchaHelperProtocol.self)
        connection.exportedObject = self
        lock.withLock { peers.append(connection) }
        let ends = peerEnds
        connection.invalidationHandler = { ends.increment() }
        connection.resume()
        return true
    }

    func ping(reply: @escaping @Sendable (Int) -> Void) {
        let delay = lock.withLock { pingDelay }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { reply(HelperIdentity.protocolVersion) }
    }

    func setCharging(allow: Bool, reply: @escaping @Sendable (Int, String) -> Void) {
        reply(HelperResult.done.rawValue, allow ? "allow — done" : "inhibit — done")
    }

    func setAdapter(enabled: Bool, leaseSeconds: Int, reply: @escaping @Sendable (Int, String) -> Void) {
        reply(HelperResult.done.rawValue, enabled ? "adapter on — done" : "adapter off — done (lease \(leaseSeconds) s)")
    }
}

private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var newest: NSXPCConnection?
    var count: Int { lock.withLock { value } }
    var last: NSXPCConnection? { lock.withLock { newest } }
    func increment() { lock.withLock { value += 1 } }
    func record(_ connection: NSXPCConnection) { lock.withLock { value += 1; newest = connection } }
}

private func client(for helper: StandInHelper, deadline: DispatchTimeInterval = .seconds(2),
                    connections: Tally, losses: Tally) -> HelperClient {
    let endpoint = helper.listener.endpoint
    return HelperClient(deadline: deadline, onConnectionLost: { losses.increment() }, makeConnection: {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connections.record(connection)
        return connection
    })
}

@Test func aPingIsAnsweredWithTheProtocolVersion() async {
    let helper = StandInHelper()
    let client = client(for: helper, connections: Tally(), losses: Tally())
    #expect(await client.ping() == .success(HelperIdentity.protocolVersion))
}

@Test func aChargeReplyCarriesTheResultAndTheDetail() async {
    let helper = StandInHelper()
    let client = client(for: helper, connections: Tally(), losses: Tally())
    #expect(await client.setCharging(allow: false) == .success(ChargeReply(result: .done, detail: "inhibit — done")))
}

@Test func consecutiveCallsShareOneConnection() async {
    let helper = StandInHelper()
    let connections = Tally()
    let client = client(for: helper, connections: connections, losses: Tally())
    _ = await client.ping()
    _ = await client.setCharging(allow: true)
    #expect(connections.count == 1)
}

@Test func aReplyLaterThanTheDeadlineTimesOutAndTheNextCallReconnects() async {
    let helper = StandInHelper()
    helper.delayPings(by: 1)
    let connections = Tally()
    let losses = Tally()
    let client = client(for: helper, deadline: .milliseconds(200), connections: connections, losses: losses)
    let started = ContinuousClock.now
    #expect(await client.ping() == .failure(.timedOut))
    #expect(ContinuousClock.now - started < .seconds(1))
    helper.delayPings(by: 0)
    #expect(await client.ping() == .success(HelperIdentity.protocolVersion))
    #expect(connections.count == 2)
    #expect(losses.count == 0)
}

@Test func aRefusedCallIsATransportErrorAndTheNextCallReconnects() async {
    let helper = StandInHelper()
    helper.refuseCallers()
    let connections = Tally()
    let client = client(for: helper, connections: connections, losses: Tally())
    guard case .failure(.transport) = await client.ping() else {
        Issue.record("a refused call must fail with a transport error")
        return
    }
    _ = await client.ping()
    #expect(connections.count == 2)
}

@Test func aLateFailureOnADroppedConnectionLeavesItsReplacementAlone() async {
    let helper = StandInHelper()
    helper.delayPings(by: 1)
    let connections = Tally()
    let client = client(for: helper, deadline: .milliseconds(300), connections: connections, losses: Tally())
    async let slow = client.ping()
    try? await Task.sleep(for: .milliseconds(50))
    client.dropConnection()
    helper.delayPings(by: 0)
    #expect(await client.ping() == .success(HelperIdentity.protocolVersion))
    _ = await slow
    #expect(await client.ping() == .success(HelperIdentity.protocolVersion))
    #expect(connections.count == 2)
}

@Test func aDeliberateDropIsNotReportedAsALoss() async {
    let helper = StandInHelper()
    let losses = Tally()
    let client = client(for: helper, connections: Tally(), losses: losses)
    _ = await client.ping()
    client.dropConnection()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(losses.count == 0)
}

@Test func anInterruptedConnectionIsReportedAndKept() async {
    let helper = StandInHelper()
    let connections = Tally()
    let losses = Tally()
    let client = client(for: helper, connections: connections, losses: losses)
    _ = await client.ping()
    helper.invalidatePeers()
    try? await Task.sleep(for: .milliseconds(300))
    #expect(losses.count == 1)
    #expect(await client.ping() == .success(HelperIdentity.protocolVersion))
    #expect(connections.count == 1)
}

@Test func anInvalidatedConnectionIsReportedAndForgotten() async {
    let helper = StandInHelper()
    let connections = Tally()
    let losses = Tally()
    let client = client(for: helper, connections: connections, losses: losses)
    _ = await client.ping()
    // Invalidated behind the client's back, as the system does when the service goes away.
    connections.last?.invalidate()
    try? await Task.sleep(for: .milliseconds(300))
    #expect(losses.count == 1)
    #expect(await client.ping() == .success(HelperIdentity.protocolVersion))
    #expect(connections.count == 2)
}

@Test func aReleasedClientClosesItsConnectionQuietly() async {
    let helper = StandInHelper()
    let losses = Tally()
    var client: HelperClient? = client(for: helper, connections: Tally(), losses: losses)
    #expect(await client?.ping() == .success(HelperIdentity.protocolVersion))
    client = nil
    #expect(await eventually { helper.peerEnds.count == 1 })
    #expect(losses.count == 0)
}

@Test func anAdapterReplyCarriesTheResultAndTheDetail() async {
    let helper = StandInHelper()
    let client = client(for: helper, connections: Tally(), losses: Tally())
    #expect(await client.setAdapter(enabled: false, leaseSeconds: 180)
            == .success(ChargeReply(result: .done, detail: "adapter off — done (lease 180 s)")))
    #expect(await client.setAdapter(enabled: true, leaseSeconds: 0)
            == .success(ChargeReply(result: .done, detail: "adapter on — done")))
}
