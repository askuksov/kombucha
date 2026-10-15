import Foundation
import KombuchaCore
import Testing
import UserNotifications
@testable import Kombucha

private let range = Thresholds.standard
private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func snapshot(level: Double = 78,
                      fullCharge: Bool = false,
                      writePath: WritePath = .ready) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: true, charging: false, thresholds: range, protection: true,
                   fullChargeActive: fullCharge, writePath: writePath)
}

@MainActor
private final class Clock {
    var now = start
}

@MainActor
private func controller(centre: FakeNotificationCentre,
                        ui: FakeUISettings = FakeUISettings(),
                        clock: Clock,
                        onHelperTab: @escaping @MainActor () -> Void = {}) -> NotificationController {
    NotificationController(centre: centre, ui: ui, now: { MainActor.assumeIsolated { clock.now } },
                           openHelperTab: onHelperTab)
}

@MainActor
@Test func aFullChargeThatReachedFullIsPosted() async {
    let centre = FakeNotificationCentre(authorization: .authorized)
    let clock = Clock()
    let controller = controller(centre: centre, clock: clock)
    controller.observe(snapshot(level: 99, fullCharge: true), fullChargeEnded: nil)
    controller.observe(snapshot(level: 100), fullChargeEnded: .reachedFull)
    await controller.settled()
    #expect(centre.posted.map(\.title) == [Copy.notificationTitle(.fullyCharged(range))])
    #expect(centre.posted.map(\.body) == [Copy.notificationBody(.fullyCharged(range))])
    #expect(centre.posted.map(\.categoryIdentifier) == [""])
}

@MainActor
@Test func aSwitchThatIsOffKeepsTheNotificationAway() async {
    let centre = FakeNotificationCentre(authorization: .authorized)
    let clock = Clock()
    let controller = controller(centre: centre, ui: FakeUISettings(fullCharge: false), clock: clock)
    controller.observe(snapshot(level: 99, fullCharge: true), fullChargeEnded: nil)
    controller.observe(snapshot(level: 100), fullChargeEnded: .reachedFull)
    await controller.settled()
    #expect(centre.posted.isEmpty)
}

@MainActor
@Test func passesAreAppliedInOrder() async {
    // Two passes back to back: the interruption must be seen as starting at the second one, not lost.
    let centre = FakeNotificationCentre(authorization: .authorized)
    let clock = Clock()
    let controller = controller(centre: centre, clock: clock)
    controller.observe(snapshot(), fullChargeEnded: nil)
    controller.observe(snapshot(writePath: .notRegistered), fullChargeEnded: nil)
    await controller.settled()
    #expect(centre.posted.isEmpty)
    clock.now = start.addingTimeInterval(NotificationDecider.interruptionGrace)
    await controller.tickNow()
    #expect(centre.posted.map(\.title)
        == [Copy.notificationTitle(.protectionStopped(.writePathBlocked(.notRegistered, level: 78)))])
}

@MainActor
@Test func aWritePathNotificationSelectsTheHelperTab() async {
    let centre = FakeNotificationCentre(authorization: .authorized)
    let clock = Clock()
    var opened = 0
    let controller = controller(centre: centre, clock: clock, onHelperTab: { opened += 1 })
    controller.observe(snapshot(), fullChargeEnded: nil)
    controller.observe(snapshot(writePath: .notRegistered), fullChargeEnded: nil)
    await controller.settled()
    clock.now = start.addingTimeInterval(NotificationDecider.interruptionGrace)
    await controller.tickNow()
    #expect(centre.posted.map(\.categoryIdentifier) == [NotificationController.writePathCategory])
    #expect(Set(centre.categories.map(\.identifier)) == [NotificationController.writePathCategory,
                                                         NotificationController.updateCategory])
    // A category that is not the write-path one — e.g. an external-battery-manager stop, which carries none —
    // must not open the Helper tab.
    controller.respond(toCategory: "")
    #expect(opened == 0)
    controller.respond(toCategory: NotificationController.writePathCategory)
    #expect(opened == 1)
}

@MainActor
@Test func theControllerAsksToBeWokenWhileAnInterruptionIsYoung() async {
    let centre = FakeNotificationCentre(authorization: .authorized)
    let clock = Clock()
    let controller = controller(centre: centre, clock: clock)
    controller.observe(snapshot(), fullChargeEnded: nil)
    controller.observe(snapshot(writePath: .notRegistered), fullChargeEnded: nil)
    await controller.settled()
    #expect(controller.wakeIsScheduled)
    controller.observe(snapshot(), fullChargeEnded: nil)
    await controller.settled()
    #expect(!controller.wakeIsScheduled)
}

@MainActor
@Test func aBatteryAlertIsPostedWithItsTitleAndBodyAndNoCategory() {
    let centre = FakeNotificationCentre(authorization: .authorized)
    let controller = controller(centre: centre, clock: Clock())
    let alert = BatteryAlert.healthDropped(from: 92, to: 91)
    controller.post(alert)
    #expect(centre.posted.map(\.title) == [Copy.alertTitle(alert)])
    #expect(centre.posted.map(\.body) == [Copy.alertBody(alert)])
    #expect(centre.posted.map(\.categoryIdentifier) == [""])
}

@MainActor
@Test func anUpdateNotificationCarriesItsCategoryAndTheVersion() {
    let centre = FakeNotificationCentre(authorization: .authorized)
    let controller = controller(centre: centre, clock: Clock())
    controller.postUpdate(AppVersion(0, 2, 0))
    #expect(centre.posted.map(\.title) == [Copy.updateNotificationTitle(AppVersion(0, 2, 0))])
    #expect(centre.posted.map(\.body) == [Copy.updateNotificationBody])
    #expect(centre.posted.map(\.categoryIdentifier) == [NotificationController.updateCategory])
}

@MainActor
@Test func theThreeSwitchesDoNotGateAnUpdateNotification() {
    let centre = FakeNotificationCentre(authorization: .authorized)
    let ui = FakeUISettings(fullCharge: false, protectionChanges: false, batteryAttention: false)
    let controller = controller(centre: centre, ui: ui, clock: Clock())
    controller.postUpdate(AppVersion(0, 2, 0))
    #expect(centre.posted.count == 1)
}

@MainActor
@Test func clickingAnUpdateNotificationOpensTheReleaseAndNothingElse() {
    let centre = FakeNotificationCentre(authorization: .authorized)
    var helperTab = 0
    var release = 0
    let controller = controller(centre: centre, clock: Clock(), onHelperTab: { helperTab += 1 })
    controller.openUpdate = { release += 1 }
    controller.respond(toCategory: "")
    controller.respond(toCategory: NotificationController.writePathCategory)
    #expect(release == 0)
    #expect(helperTab == 1)
    controller.respond(toCategory: NotificationController.updateCategory)
    #expect(release == 1)
    #expect(helperTab == 1)
}
