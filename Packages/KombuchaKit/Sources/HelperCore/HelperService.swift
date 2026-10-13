import Foundation
import HelperProtocol
import Synchronization
import os

public final class HelperService: NSObject, KombuchaHelperProtocol, @unchecked Sendable {
    /// What the service knows about the adapter switch. Guarded together with every write.
    struct AdapterBook {
        /// The client whose disable is in force: when its connection ends, the adapter goes back on.
        var owner: ClientID?
        /// Between system sleep and the next full wake a disable is refused.
        var sleeping = false
        /// The seconds of the lease in force, for a grant that has to be repeated.
        var leaseSeconds = 0
    }

    /// The lease the app asks for is kept within this range, so a bad value neither expires at once nor never.
    static let leaseRange = 1...600
    /// The lease for an adapter found off when no lease was ever granted.
    static let defaultLeaseSeconds = 180

    private let writer: any ChargeWriting
    private let adapter: (any AdapterWriting)?
    private let lease: AdapterLease
    private let exitProcess: @Sendable () -> Void
    /// Held across a write, its read-back and its reply; taken for good by `retire` and `stop`.
    private let writing = Mutex(AdapterBook())
    private let log = Logger(subsystem: HelperIdentity.machServiceName, category: "charge")
    private let adapterLog = Logger(subsystem: HelperIdentity.machServiceName, category: "adapter")
    private let startupLog = Logger(subsystem: HelperIdentity.machServiceName, category: "startup")

    public init(writer: any ChargeWriting,
                adapter: (any AdapterWriting)? = nil,
                scheduler: any LeaseScheduler = DispatchLeaseScheduler(),
                exitProcess: @escaping @Sendable () -> Void = { Foundation.exit(0) }) {
        self.writer = writer
        self.adapter = adapter
        self.lease = AdapterLease(scheduler: scheduler)
        self.exitProcess = exitProcess
    }

    public func ping(reply: @escaping @Sendable (Int) -> Void) {
        log.info("ping — done")
        reply(HelperIdentity.protocolVersion)
    }

    public func setCharging(allow: Bool, reply: @escaping @Sendable (Int, String) -> Void) {
        let intent = allow ? "allow" : "inhibit"
        writing.withLock { _ in
            do {
                try writer.setCharging(allow: allow)
                let detail = "setCharging: \(intent) — done"
                log.info("\(detail, privacy: .public)")
                reply(HelperResult.done.rawValue, detail)
            } catch {
                let detail = "setCharging: \(intent) — failed: \(error)"
                log.error("\(detail, privacy: .public)")
                reply(HelperResult.failed.rawValue, detail)
            }
        }
    }

    public func setAdapter(enabled: Bool, leaseSeconds: Int, reply: @escaping @Sendable (Int, String) -> Void) {
        setAdapter(enabled: enabled, leaseSeconds: leaseSeconds,
                   client: NSXPCConnection.current().map(ClientID.init), reply: reply)
    }

    func setAdapter(enabled: Bool, leaseSeconds: Int, client: ClientID?,
                    reply: @escaping @Sendable (Int, String) -> Void) {
        let intent = enabled ? "enable" : "disable"
        writing.withLock { book in
            func fail(_ why: String) {
                let detail = "setAdapter: \(intent) — failed: \(why)"
                adapterLog.error("\(detail, privacy: .public)")
                reply(HelperResult.failed.rawValue, detail)
            }
            guard let adapter else { return fail("adapter key not found") }
            if !enabled, book.sleeping { return fail("the system is going to sleep") }
            do {
                try adapter.setAdapter(enabled: enabled)
            } catch {
                if !enabled {
                    // A disable that did not land must not leave the adapter in a state nobody knows; if the
                    // undo fails too, this client owns the doubt and a lease is armed.
                    if book.leaseSeconds == 0 { book.leaseSeconds = clampedLease(leaseSeconds) }
                    book.owner = client ?? book.owner
                    restore(&book, because: "a disable did not land")
                }
                return fail(String(describing: error))
            }
            if enabled {
                lease.cancel()
                book.owner = nil
            } else {
                book.owner = client
                let seconds = clampedLease(leaseSeconds)
                book.leaseSeconds = seconds
                grantLease(seconds)
            }
            let detail = "setAdapter: \(intent) — done"
            adapterLog.info("\(detail, privacy: .public)")
            reply(HelperResult.done.rawValue, detail)
        }
    }

    /// The lease ran out: the app did not renew in time.
    func leaseExpired() {
        writing.withLock { book in
            // A renew that took the lock first armed the lease again; it wins.
            guard !lease.isArmed else { return }
            restore(&book, because: "the lease expired")
        }
    }

    private func clampedLease(_ seconds: Int) -> Int {
        min(max(seconds, Self.leaseRange.lowerBound), Self.leaseRange.upperBound)
    }

    private func grantLease(_ seconds: Int) {
        lease.grant(seconds: seconds) { [weak self] in self?.leaseExpired() }
    }

    /// A client's connection ended (quit or crash). Only the client whose disable is in force matters.
    public func clientLeft(_ client: ClientID) {
        writing.withLock { book in
            guard book.owner == client else { return }
            restore(&book, because: "the client that switched it off is gone")
        }
    }

    /// A crash, a kill or a restart may have left the adapter off.
    public func restoreAdapterAtStart() {
        writing.withLock { book in
            restoreIfOff(&book, because: "found switched off at my start")
        }
    }

    public func systemWillSleep() {
        adapterLog.notice("system will sleep")
        writing.withLock { book in
            book.sleeping = true
            restoreIfOff(&book, because: "the system is going to sleep")
        }
    }

    public func systemDidWake() {
        writing.withLock { $0.sleeping = false }
    }

    /// Releases the charger and switches the adapter on, then ends the process once no write is in flight;
    /// launchd starts the binary on disk for the next message. A replaced app can no longer reach this helper to
    /// release on its way out.
    public func retire(because reason: String) {
        writing.withLock { book in
            startupLog.notice("retiring: \(reason, privacy: .public)")
            do {
                try writer.setCharging(allow: true)
                startupLog.notice("allow landed before retiring")
            } catch {
                startupLog.error("allow did not land before retiring: \(String(describing: error), privacy: .public)")
            }
            restoreIfOff(&book, because: "retiring")
            exitProcess()
        }
    }

    /// launchd stops the job (removed, or the Mac shuts down): the adapter goes back on, the charger is left as is.
    public func stop(because reason: String) {
        writing.withLock { book in
            startupLog.notice("stopping: \(reason, privacy: .public)")
            restoreIfOff(&book, because: "stopping")
            exitProcess()
        }
    }

    /// Switches the adapter on and forgets the lease and its owner. Runs under `writing`. A write that does not
    /// land keeps the owner and arms the lease again, so the adapter is never left off with nothing to switch it
    /// back on. False when the write did not land.
    @discardableResult
    private func restore(_ book: inout AdapterBook, because reason: String) -> Bool {
        lease.cancel()
        guard let adapter else {
            book.owner = nil
            return true
        }
        do {
            try adapter.setAdapter(enabled: true)
            book.owner = nil
            adapterLog.notice("adapter switched back on: \(reason, privacy: .public)")
            return true
        } catch {
            grantLease(book.leaseSeconds > 0 ? book.leaseSeconds : Self.defaultLeaseSeconds)
            adapterLog.error("adapter not switched back on (\(reason, privacy: .public)): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// At start, at sleep and on the way out the key decides: anything but "on", or a key that cannot be read, is
    /// switched on.
    private func restoreIfOff(_ book: inout AdapterBook, because reason: String) {
        guard let adapter else { return }
        if (try? adapter.currentlyEnabled()) == true { return }
        restore(&book, because: reason)
    }
}
