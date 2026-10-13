import ServiceManagement
import Testing
import UserNotifications
@testable import Kombucha

@MainActor
private func parts(welcomeCompleted: Bool = false)
    -> (model: AppModel, item: FakeLoginItem, centre: FakeNotificationCentre, ui: FakeUISettings) {
    let model = AppModel()
    let item = FakeLoginItem(.notRegistered)
    item.whenRegistered(becomes: .enabled)
    let centre = FakeNotificationCentre(authorization: .notDetermined)
    centre.whenAsked(grants: .authorized)
    let ui = FakeUISettings(welcomeCompleted: welcomeCompleted)
    model.attach(loginItem: item, notifications: centre, ui: ui)
    return (model, item, centre, ui)
}

@MainActor
@Test func theWindowIsAskedForOnAFirstLaunchOnly() {
    let first = parts(welcomeCompleted: false)
    first.model.publish(.supported)
    #expect(first.model.welcomePending)

    let later = parts(welcomeCompleted: true)
    later.model.publish(.supported)
    #expect(!later.model.welcomePending)
}

@MainActor
@Test func closingWelcomeWritesNothing() {
    let (model, item, centre, ui) = parts()
    model.publish(.supported)
    model.welcomeOpened()          // the window appeared
    // The red button: no Done, so nothing at all happened.
    #expect(item.calls.isEmpty)
    #expect(centre.requests == 0)
    #expect(!ui.welcomeCompleted)
    #expect(ui.notifyFullChargeFinished)
    #expect(ui.notifyProtectionChanges)
    // A second launch asks again.
    let again = AppModel()
    again.attach(loginItem: item, notifications: centre, ui: ui)
    again.publish(.supported)
    #expect(again.welcomePending)
}

@MainActor
@Test func doneRegistersAsksStoresAndStopsAsking() async {
    let (model, item, centre, ui) = parts()
    model.publish(.supported)
    model.welcomeOpened()
    await model.finishWelcome(launchAtLogin: true, fullCharge: true, protectionChanges: true)
    #expect(item.calls == ["register"])
    #expect(centre.requests == 1)
    #expect(ui.welcomeCompleted)
    #expect(!model.welcomePending)
    #expect(model.loginItemStatus == .enabled)
}

@MainActor
@Test func anUnsupportedMacGetsTheReasonAndNoSwitches() {
    let (model, _, _, _) = parts()
    model.publish(.noBattery)
    #expect(WelcomeView.showsSteps(for: model) == false)
    #expect(Copy.unsupportedReason(.noBattery).isEmpty == false)
}

@MainActor
@Test func aSupportedMacGetsTheFourSteps() {
    let (model, _, _, _) = parts()
    model.publish(.supported)
    #expect(WelcomeView.showsSteps(for: model))
}

@Test func theWindowHasAStableIdentifier() {
    #expect(WelcomeView.windowID == "welcome")
}
