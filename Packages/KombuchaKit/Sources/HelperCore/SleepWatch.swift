import Foundation
import HelperProtocol
import IOKit
import IOKit.pwr_mgt
import os

/// System sleep and wake for the helper, through IOKit on its own queue. Before a sleep is allowed the adapter
/// goes back on; a full wake lifts the refusal of a disable. A dark wake posts nothing.
public final class SleepWatch: @unchecked Sendable {
    public enum Response: Equatable, Sendable {
        case allow, willSleep, woke, ignore
    }

    // iokit_common_msg() is a function-like macro, so Swift does not import these.
    enum Message {
        static let canSystemSleep: UInt32 = 0xE000_0270
        static let systemWillSleep: UInt32 = 0xE000_0280
        static let systemHasPoweredOn: UInt32 = 0xE000_0300
    }

    private let queue: DispatchQueue
    private let onWillSleep: @Sendable () -> Void
    private let onWake: @Sendable () -> Void
    private let lock = NSLock()
    private var root: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private let log = Logger(subsystem: HelperIdentity.machServiceName, category: "sleep")

    public init(queue: DispatchQueue,
                onWillSleep: @escaping @Sendable () -> Void,
                onWake: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onWillSleep = onWillSleep
        self.onWake = onWake
    }

    deinit {
        stop()
    }

    public static func response(to message: UInt32) -> Response {
        switch message {
        case Message.canSystemSleep: .allow
        case Message.systemWillSleep: .willSleep
        case Message.systemHasPoweredOn: .woke
        default: .ignore
        }
    }

    /// False when already started or when IOKit refuses the registration.
    public func start() -> Bool {
        lock.withLock {
            guard root == 0 else { return false }
            var port: IONotificationPortRef?
            var notifier: io_object_t = 0
            // The registration never outlives the watch: stop() removes it.
            let context = Unmanaged.passUnretained(self).toOpaque()
            let root = IORegisterForSystemPower(context, &port, { context, _, message, argument in
                guard let context else { return }
                Unmanaged<SleepWatch>.fromOpaque(context).takeUnretainedValue().handle(message, argument)
            }, &notifier)
            guard root != 0, let port else { return false }
            IONotificationPortSetDispatchQueue(port, queue)
            self.root = root
            self.port = port
            self.notifier = notifier
            return true
        }
    }

    public func stop() {
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
        case .allow:
            allowSleep(argument)
        case .willSleep:
            onWillSleep()
            allowSleep(argument)
        case .woke:
            onWake()
        case .ignore:
            break
        }
    }

    private func allowSleep(_ argument: UnsafeMutableRawPointer?) {
        let result = IOAllowPowerChange(lock.withLock { root }, Int(bitPattern: argument))
        if result != kIOReturnSuccess {
            log.error("sleep acknowledgement failed: \(String(format: "0x%08x", result), privacy: .public)")
        }
    }
}
