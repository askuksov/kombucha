import UserNotifications

/// Everything the app asks of `UNUserNotificationCenter`, behind a protocol so the controller can be tested
/// without the system centre — which refuses to answer inside a test host anyway.
@MainActor
protocol NotificationCentering: Sendable {
    func authorization() async -> UNAuthorizationStatus
    /// Asks the user. Returns the status after the answer, whatever it is.
    func requestAuthorization() async -> UNAuthorizationStatus
    func register(categories: Set<UNNotificationCategory>)
    func post(_ content: UNNotificationContent)
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate)
}

@MainActor
final class NotificationCenterClient: NotificationCentering {
    private let centre = UNUserNotificationCenter.current()

    func authorization() async -> UNAuthorizationStatus {
        await centre.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> UNAuthorizationStatus {
        // A refusal is an answer, not an error: the tab shows the denied state either way.
        _ = try? await centre.requestAuthorization(options: [.alert])
        return await authorization()
    }

    func register(categories: Set<UNNotificationCategory>) {
        centre.setNotificationCategories(categories)
    }

    func post(_ content: UNNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        centre.add(request)
    }

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        centre.delegate = delegate
    }
}
