import Foundation
import KombuchaCore
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

/// Stands in for `SettingsStore` where only the update keys matter.
final class FakeUpdateState: UpdateStateStoring, Sendable {
    private struct State {
        var daily: Bool
        var lastCheck: Date?
        var latest: AppVersion?
        var announced: AppVersion?
    }

    private let state: Mutex<State>

    init(daily: Bool = false, lastCheck: Date? = nil, latest: AppVersion? = nil, announced: AppVersion? = nil) {
        state = Mutex(State(daily: daily, lastCheck: lastCheck, latest: latest, announced: announced))
    }

    var updateCheckDaily: Bool { state.withLock { $0.daily } }
    var updateLastCheck: Date? { state.withLock { $0.lastCheck } }
    var updateLatestVersion: AppVersion? { state.withLock { $0.latest } }
    var updateAnnouncedVersion: AppVersion? { state.withLock { $0.announced } }

    func setUpdateCheckDaily(_ on: Bool) { state.withLock { $0.daily = on } }
    func setUpdateLastCheck(_ date: Date?) { state.withLock { $0.lastCheck = date } }
    func setUpdateLatestVersion(_ version: AppVersion?) { state.withLock { $0.latest = version } }
    func setUpdateAnnouncedVersion(_ version: AppVersion?) { state.withLock { $0.announced = version } }
}

/// Answers one scripted result per call; the last result repeats.
final class FakeReleaseFetcher: ReleaseFetching, Sendable {
    private struct State {
        var results: [Result<String, any Error>]
        var calls = 0
    }

    private let state: Mutex<State>

    init(_ results: [Result<String, any Error>]) {
        state = Mutex(State(results: results))
    }

    var calls: Int { state.withLock { $0.calls } }

    func latestTag() async throws -> String {
        let result = state.withLock { state -> Result<String, any Error> in
            state.calls += 1
            return state.results.count > 1 ? state.results.removeFirst() : state.results[0]
        }
        return try result.get()
    }
}

/// Answers one result, but runs a hook first, while the request is still in flight.
final class HookedReleaseFetcher: ReleaseFetching, Sendable {
    private let result: Result<String, any Error>
    private let whileWaiting: @Sendable () async -> Void

    init(_ result: Result<String, any Error>, whileWaiting: @escaping @Sendable () async -> Void) {
        self.result = result
        self.whileWaiting = whileWaiting
    }

    func latestTag() async throws -> String {
        await whileWaiting()
        return try result.get()
    }
}

final class FakeRestarter: Restarting, Sendable {
    private let count = Mutex(0)

    var restarts: Int { count.withLock { $0 } }

    func restart() -> Bool {
        count.withLock { $0 += 1 }
        return true
    }
}

/// A restarter whose spawn always fails.
final class FailingRestarter: Restarting, Sendable {
    private let count = Mutex(0)

    var restarts: Int { count.withLock { $0 } }

    func restart() -> Bool {
        count.withLock { $0 += 1 }
        return false
    }
}
