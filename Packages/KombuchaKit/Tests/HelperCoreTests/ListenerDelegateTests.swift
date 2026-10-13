import Foundation
import HelperProtocol
import Security
import Synchronization
import Testing
@testable import HelperCore

private let clientRequirement = #"identifier "dev.kuksov.kombucha" and anchor apple generic"#

private final class PidRecorder: Sendable {
    private let pids = Mutex<[pid_t]>([])

    var recorded: [pid_t] { pids.withLock { $0 } }

    func record(_ pid: pid_t) { pids.withLock { $0.append(pid) } }
}

private func delegate(verdict: CallerVerdict, recorder: PidRecorder? = nil) -> ListenerDelegate {
    ListenerDelegate(requirementText: clientRequirement, service: HelperService(writer: RecordingWriter())) { pid in
        recorder?.record(pid)
        return verdict
    }
}

@Test func acceptsACallerThatMatchesTheRequirementAndExportsTheService() {
    let listener = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    defer { connection.invalidate() }

    let accepted = delegate(verdict: CallerVerdict(accepted: true, path: "/Applications/Kombucha.app", status: errSecSuccess))
        .listener(listener, shouldAcceptNewConnection: connection)

    #expect(accepted)
    #expect(connection.exportedObject is HelperService)
    #expect(connection.exportedInterface != nil)
}

@Test func refusesACallerThatDoesNotMatchTheRequirementAndExportsNothing() {
    let listener = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    defer { connection.invalidate() }

    let accepted = delegate(verdict: CallerVerdict(accepted: false, path: "/bin/sleep", status: errSecCSReqFailed))
        .listener(listener, shouldAcceptNewConnection: connection)

    #expect(!accepted)
    #expect(connection.exportedObject == nil)
    #expect(connection.exportedInterface == nil)
}

@Test func theDecisionIsTakenAboutTheConnectionsOwnProcess() {
    let listener = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    defer { connection.invalidate() }
    let recorder = PidRecorder()

    _ = delegate(verdict: CallerVerdict(accepted: false, path: "unused", status: errSecCSReqFailed), recorder: recorder)
        .listener(listener, shouldAcceptNewConnection: connection)

    #expect(recorder.recorded == [connection.processIdentifier])
}

@Test func aDelegateNeedsARequirementThatCompiles() {
    let service = HelperService(writer: RecordingWriter(), exitProcess: {})
    let identity = CodeIdentity(executablePath: "/bin/ls")
    #expect(ListenerDelegate(requirementText: "", identity: identity, service: service) == nil)
    #expect(ListenerDelegate(requirementText: "identifier and and", identity: identity, service: service) == nil)
    #expect(ListenerDelegate(requirementText: clientRequirement, identity: identity, service: service) != nil)
}

// The real verifier refuses what it cannot look up: an anonymous listener's connection has pid 0.
@Test func theRealVerifierRefusesAConnectionWhosePidCannotBeLookedUp() throws {
    let listener = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    defer { connection.invalidate() }
    // /bin/ls does not change during the test, so the identity check passes and the caller check decides.
    let service = HelperService(writer: RecordingWriter(), exitProcess: {})
    let delegate = try #require(ListenerDelegate(requirementText: clientRequirement, identity: CodeIdentity(executablePath: "/bin/ls"), service: service))
    #expect(CodeIdentity(executablePath: "/bin/ls").matchesDisk())

    #expect(connection.processIdentifier == 0)
    #expect(!delegate.listener(listener, shouldAcceptNewConnection: connection))
    #expect(connection.exportedObject == nil)
}

@Test func aHelperWhoseCodeLeftTheDiskRefusesTheConnectionAndRetires() {
    let listener = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    defer { connection.invalidate() }
    let callers = PidRecorder()
    let exits = Occurrences()
    let service = HelperService(writer: RecordingWriter(), exitProcess: { exits.record() })
    let delegate = ListenerDelegate(requirementText: clientRequirement, service: service, matchesDisk: { false }) { pid in
        callers.record(pid)
        return CallerVerdict(accepted: true, path: "/Applications/Kombucha.app", status: errSecSuccess)
    }

    #expect(!delegate.listener(listener, shouldAcceptNewConnection: connection))
    #expect(exits.count == 1)
    #expect(callers.recorded.isEmpty)
    #expect(connection.exportedObject == nil)
}

@Test func theEndOfTheConnectionThatSwitchedTheAdapterOffSwitchesItBackOn() {
    let listener = NSXPCListener.anonymous()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    defer { connection.invalidate() }
    let adapter = RecordingAdapter()
    let service = HelperService(writer: RecordingWriter(), adapter: adapter, scheduler: ManualScheduler(), exitProcess: {})
    let delegate = ListenerDelegate(requirementText: clientRequirement, service: service) { _ in
        CallerVerdict(accepted: true, path: "/Applications/Kombucha.app", status: errSecSuccess)
    }
    #expect(delegate.listener(listener, shouldAcceptNewConnection: connection))
    service.setAdapter(enabled: false, leaseSeconds: 180, client: ClientID(connection)) { _, _ in }
    // What libxpc does when the app crashes or quits.
    connection.invalidationHandler?()
    #expect(adapter.recorded == [false, true])
}
