import ServiceManagement
import Testing
import UserNotifications
@testable import Kombucha

@MainActor
@Test func theLoginItemReportsTheServiceStatusWithoutTouchingIt() {
    // Reading the status registers nothing: the test host must stay out of the user's Login Items.
    let item = LoginItem()
    let status = item.status
    #expect([SMAppService.Status.notRegistered, .enabled, .requiresApproval, .notFound].contains(status))
    #expect(item.status == status)
}

@MainActor
@Test func theFakeLoginItemFollowsRegisterAndUnregister() throws {
    let fake = FakeLoginItem(.notRegistered)
    fake.whenRegistered(becomes: .enabled)
    try fake.register()
    #expect(fake.status == .enabled)
    try fake.unregister()
    #expect(fake.status == .notRegistered)
    #expect(fake.calls == ["register", "unregister"])
}

@MainActor
@Test func theFakeCentreRemembersWhatItWasAskedAndGiven() async {
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    centre.whenAsked(grants: .authorized)
    #expect(await centre.authorization() == .notDetermined)
    #expect(await centre.requestAuthorization() == .authorized)
    #expect(await centre.authorization() == .authorized)
    let content = UNMutableNotificationContent()
    content.title = "Fully charged"
    centre.post(content)
    #expect(centre.posted.map(\.title) == ["Fully charged"])
    #expect(centre.requests == 1)
}
