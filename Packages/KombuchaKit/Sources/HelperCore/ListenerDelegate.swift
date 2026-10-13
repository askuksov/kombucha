import Foundation
import HelperProtocol
import Security
import os

public final class ListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let requirementText: String
    private let checkCaller: @Sendable (pid_t) -> CallerVerdict
    private let matchesDisk: @Sendable () -> Bool
    private let service: HelperService
    private let log = Logger(subsystem: HelperIdentity.machServiceName, category: "xpc")

    /// Nil when the text does not compile: a listener that cannot check its callers must not run.
    public convenience init?(requirementText: String, identity: CodeIdentity, service: HelperService) {
        guard let compiled = CallerVerifier.compile(requirementText) else { return nil }
        let box = RequirementBox(requirement: compiled)
        self.init(requirementText: requirementText, service: service, matchesDisk: { identity.matchesDisk() }) { pid in
            CallerVerifier.check(pid: pid, against: box.requirement)
        }
    }

    /// Tests only: both checks are injected, and `requirementText` is not compiled here.
    init(
        requirementText: String,
        service: HelperService,
        matchesDisk: @escaping @Sendable () -> Bool = { true },
        checkCaller: @escaping @Sendable (pid_t) -> CallerVerdict
    ) {
        self.requirementText = requirementText
        self.service = service
        self.matchesDisk = matchesDisk
        self.checkCaller = checkCaller
        super.init()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The app drops every reply from code that no longer matches its signature; make way for the new binary.
        guard matchesDisk() else {
            log.error("refused a connection: my code no longer matches the disk")
            service.retire(because: "my code no longer matches the disk")
            return false
        }
        // libxpc drops messages that fail the requirement without telling the listener; check here to log it.
        let verdict = checkCaller(connection.processIdentifier)
        guard verdict.accepted else {
            log.error("refused a caller: \(verdict.path, privacy: .public): \(verdict.status)")
            return false
        }
        connection.setCodeSigningRequirement(requirementText)
        connection.exportedInterface = NSXPCInterface(with: KombuchaHelperProtocol.self)
        connection.exportedObject = service
        // A client that crashes or quits invalidates its connection; a disable it left in force is undone.
        let client = ClientID(connection)
        connection.invalidationHandler = { [service] in service.clientLeft(client) }
        connection.resume()
        return true
    }
}

/// A compiled requirement is an immutable CF object; the Security framework declares no Sendable conformance.
private struct RequirementBox: @unchecked Sendable {
    let requirement: SecRequirement
}
