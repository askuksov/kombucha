import Foundation
import IOKit
import IOKit.pwr_mgt
import Synchronization

/// System sleep and wake through IOKit: a coming sleep waits for the engine at most 2 s, every full wake is posted. A dark wake posts nothing.
final class WakeMonitor: EventSource, @unchecked Sendable {
    enum Response: Equatable {
        case allowSleep, willSleep, woke, ignore
    }

    /// How long a coming sleep waits for the engine to switch the adapter back on.
    static let engineWait: Duration = .seconds(2)

    // iokit_common_msg() is a function-like macro, so Swift does not import these.
    enum Message {
        static let canSystemSleep: UInt32 = 0xE000_0270
        static let systemWillSleep: UInt32 = 0xE000_0280
        static let systemHasPoweredOn: UInt32 = 0xE000_0300
    }

    let name = "wake monitor"
    private let inbox: EngineInbox
    private let queue = DispatchQueue(label: "dev.kuksov.kombucha.wake")
    private let lock = NSLock()
    private var root: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init(inbox: EngineInbox) {
        self.inbox = inbox
    }

    deinit {
        stop()
    }

    static func response(to message: UInt32) -> Response {
        switch message {
        case Message.canSystemSleep: .allowSleep
        case Message.systemWillSleep: .willSleep
        case Message.systemHasPoweredOn: .woke
        default: .ignore
        }
    }

    /// Posts the question and blocks the calling queue until the engine answers or `limit` passes. Call it from a
    /// dispatch queue only, never from Swift concurrency. False when nobody answered in time or the loop has ended.
    static func waitForEngine(limit: Duration, _ post: (Answer) -> Bool) -> Bool {
        let answer = Answer()
        guard post(answer) else { return false }
        let waiter = SleepWaiter()
        Task {
            waiter.finish(answered: await answer.value(waitingAtMost: limit) != .failed(.noAnswer))
        }
        // The answer's own deadline ends the wait; the margin covers a task that is slow to start.
        let margin = DispatchTimeInterval.milliseconds(Int(limit / .milliseconds(1)) + 500)
        guard waiter.semaphore.wait(timeout: .now() + margin) == .success else { return false }
        return waiter.answered
    }

    /// False when already started or when IOKit refuses the registration.
    func start() -> Bool {
        lock.withLock {
            guard root == 0 else { return false }
            var port: IONotificationPortRef?
            var notifier: io_object_t = 0
            // The registration never outlives the monitor: stop() removes it.
            let context = Unmanaged.passUnretained(self).toOpaque()
            let root = IORegisterForSystemPower(context, &port, { context, _, message, argument in
                guard let context else { return }
                Unmanaged<WakeMonitor>.fromOpaque(context).takeUnretainedValue().handle(message, argument)
            }, &notifier)
            guard root != 0, let port else { return false }
            IONotificationPortSetDispatchQueue(port, queue)
            self.root = root
            self.port = port
            self.notifier = notifier
            return true
        }
    }

    func stop() {
        lock.withLock {
            guard root != 0 else { return }
            IODeregisterForSystemPower(&notifier)
            IOServiceClose(root)
            if let port { IONotificationPortDestroy(port) }
            root = 0
            port = nil
            notifier = 0
        }
    }

    // A registered process that does not answer holds up the machine's sleep for up to 30 s.
    private func handle(_ message: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch Self.response(to: message) {
        case .allowSleep:
            allowSleep(argument)
        case .willSleep:
            // A running discharge ends and the adapter goes back on before the Mac sleeps.
            let inbox = inbox
            if !Self.waitForEngine(limit: Self.engineWait, { inbox.post(.willSleep($0)) }) {
                AppLog.engine.error("the engine did not answer before sleep")
            }
            allowSleep(argument)
        case .woke:
            AppLog.engine.info("the system woke")
            inbox.post(.systemWoke)
        case .ignore:
            break
        }
    }

    private func allowSleep(_ argument: UnsafeMutableRawPointer?) {
        let result = IOAllowPowerChange(lock.withLock { root }, Int(bitPattern: argument))
        if result != kIOReturnSuccess {
            AppLog.engine.error("sleep acknowledgement failed: \(String(format: "0x%08x", result), privacy: .public)")
        }
    }
}

/// The answer to one sleep question, handed from a task to the blocked dispatch queue.
private final class SleepWaiter: Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let result = Mutex(false)

    var answered: Bool { result.withLock { $0 } }

    func finish(answered: Bool) {
        result.withLock { $0 = answered }
        semaphore.signal()
    }
}
