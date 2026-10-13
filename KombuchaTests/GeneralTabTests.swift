import ServiceManagement
import Testing
import UserNotifications
@testable import Kombucha

@MainActor
private func model(loginItem: SMAppService.Status = .enabled,
                   authorization: UNAuthorizationStatus = .authorized,
                   ui: FakeUISettings = FakeUISettings()) async -> AppModel {
    let model = AppModel()
    let centre = FakeNotificationCentre(authorization: authorization)
    model.attach(loginItem: FakeLoginItem(loginItem), notifications: centre, ui: ui)
    await model.refreshNotificationAuthorization()
    return model
}

@MainActor
@Test func anAuthorizedCentreShowsNoExtraLine() async {
    #expect(GeneralTab.authorization(for: await model()) == .asked)
}

@MainActor
@Test func anUndeterminedAuthorizationWithASwitchOnOffersToAsk() async {
    let model = await model(authorization: .notDetermined)
    #expect(GeneralTab.authorization(for: model) == .notAsked)
}

@MainActor
@Test func anUndeterminedAuthorizationWithEveryNotificationSwitchOffSaysNothing() async {
    let model = await model(authorization: .notDetermined,
                            ui: FakeUISettings(fullCharge: false, protectionChanges: false, batteryAttention: false))
    #expect(GeneralTab.authorization(for: model) == .asked)
}

@MainActor
@Test func anUndeterminedAuthorizationWithOnlyTheAttentionSwitchOnOffersToAsk() async {
    let model = await model(authorization: .notDetermined,
                            ui: FakeUISettings(fullCharge: false, protectionChanges: false, batteryAttention: true))
    #expect(GeneralTab.authorization(for: model) == .notAsked)
}

@MainActor
@Test func deniedAuthorizationDisablesTheSwitches() async {
    let model = await model(authorization: .denied)
    #expect(GeneralTab.authorization(for: model) == .denied)
    #expect(GeneralTab.authorization(for: model).switchesAreDisabled)
    #expect(!GeneralTab.Authorization.notAsked.switchesAreDisabled)
}

@MainActor
@Test func aProvisionalAuthorizationCountsAsAsked() async {
    #expect(GeneralTab.authorization(for: await model(authorization: .provisional)) == .asked)
}

@MainActor
@Test func theRefusedLoginItemIsExplained() async {
    let approval = await model(loginItem: .requiresApproval)
    #expect(approval.launchAtLoginNeedsApproval)
    #expect(!approval.launchAtLoginIsOn)
    let enabled = await model(loginItem: .enabled)
    #expect(!enabled.launchAtLoginNeedsApproval)
    #expect(enabled.launchAtLoginIsOn)
}

@Test func theDoorsPointAtTheRightPanes() {
    #expect(Copy.SystemSettings.loginItems.absoluteString
        == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    #expect(Copy.SystemSettings.notifications.absoluteString
        == "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
}
