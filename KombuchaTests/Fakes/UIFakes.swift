import ServiceManagement
import Synchronization
import UserNotifications
@testable import Kombucha

@MainActor
final class FakeLoginItem: LoginItemControlling {
    private(set) var status: SMAppService.Status
    private(set) var calls: [String] = []
    private var afterRegister: SMAppService.Status?
    private var registerError: (any Error)?

    init(_ status: SMAppService.Status) { self.status = status }

    func whenRegistered(becomes value: SMAppService.Status) { afterRegister = value }
    func whenRegisteredThrows(_ error: any Error) { registerError = error }

    func register() throws {
        calls.append("register")
        if let registerError { throw registerError }
        if let afterRegister { status = afterRegister }
    }

    func unregister() throws {
        calls.append("unregister")
        status = .notRegistered
    }
}

@MainActor
final class FakeNotificationCentre: NotificationCentering {
    private(set) var posted: [UNNotificationContent] = []
    private(set) var requests = 0
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var delegate: (any UNUserNotificationCenterDelegate)?
    private var status: UNAuthorizationStatus
    private var granted: UNAuthorizationStatus?

    init(authorization: UNAuthorizationStatus) { status = authorization }

    func whenAsked(grants value: UNAuthorizationStatus) { granted = value }
    func set(authorization value: UNAuthorizationStatus) { status = value }

    func authorization() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> UNAuthorizationStatus {
        requests += 1
        if let granted { status = granted }
        return status
    }

    func register(categories value: Set<UNNotificationCategory>) { categories = value }
    func post(_ content: UNNotificationContent) { posted.append(content) }
    func setDelegate(_ value: any UNUserNotificationCenterDelegate) { delegate = value }
}

/// A store the tests can watch, standing in for `SettingsStore` where only the UI keys matter.
final class FakeUISettings: UISettingsStoring, Sendable {
    private struct State {
        var notifyFullChargeFinished: Bool
        var notifyProtectionChanges: Bool
        var notifyBatteryAttention: Bool
        var welcomeCompleted: Bool
    }

    private let state: Mutex<State>

    init(fullCharge: Bool = true, protectionChanges: Bool = true, batteryAttention: Bool = true,
         welcomeCompleted: Bool = false) {
        state = Mutex(State(notifyFullChargeFinished: fullCharge, notifyProtectionChanges: protectionChanges,
                            notifyBatteryAttention: batteryAttention, welcomeCompleted: welcomeCompleted))
    }

    var notifyFullChargeFinished: Bool { state.withLock { $0.notifyFullChargeFinished } }
    var notifyProtectionChanges: Bool { state.withLock { $0.notifyProtectionChanges } }
    var notifyBatteryAttention: Bool { state.withLock { $0.notifyBatteryAttention } }
    var welcomeCompleted: Bool { state.withLock { $0.welcomeCompleted } }

    func setNotifyFullChargeFinished(_ on: Bool) { state.withLock { $0.notifyFullChargeFinished = on } }
    func setNotifyProtectionChanges(_ on: Bool) { state.withLock { $0.notifyProtectionChanges = on } }
    func setNotifyBatteryAttention(_ on: Bool) { state.withLock { $0.notifyBatteryAttention = on } }
    func setWelcomeCompleted(_ done: Bool) { state.withLock { $0.welcomeCompleted = done } }
}
