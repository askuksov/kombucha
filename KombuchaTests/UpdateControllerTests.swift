import Foundation
import KombuchaCore
import Testing
@testable import Kombucha

private let launch = Date(timeIntervalSince1970: 1_800_000_000)
private let current = AppVersion(0, 1, 0)
private let day = UpdateSchedule.interval

@MainActor
private final class Clock {
    var now = launch
}

/// What the controller reached out to.
@MainActor
private final class Outside {
    var announced: [AppVersion] = []
    var opened: [URL] = []
    var asked = 0
}

@MainActor
private func controller(_ fetcher: any ReleaseFetching = FakeReleaseFetcher([.success("v0.1.0")]),
                        store: FakeUpdateState = FakeUpdateState(),
                        running: AppVersion? = current,
                        clock: Clock = Clock(),
                        outside: Outside = Outside()) -> UpdateController {
    UpdateController(fetcher: fetcher, running: running, store: store,
                     now: { MainActor.assumeIsolated { clock.now } },
                     announce: { outside.announced.append($0) },
                     askForNotifications: { outside.asked += 1 },
                     openURL: { outside.opened.append($0) })
}

private let offline: Result<String, any Error> = .failure(URLError(.notConnectedToInternet))

@MainActor
@Test func aLaunchWithNothingStoredIsIdle() {
    let controller = controller()
    #expect(controller.state == .idle)
    #expect(!controller.dailyCheck)
    #expect(controller.releaseURL == nil)
}

@MainActor
@Test func aStoredNewerVersionShowsAtLaunchWithoutAsking() {
    let fetcher = FakeReleaseFetcher([.success("v0.1.0")])
    let outside = Outside()
    let controller = controller(fetcher, store: FakeUpdateState(latest: AppVersion(0, 2, 0)), outside: outside)
    #expect(controller.state == .available(AppVersion(0, 2, 0)))
    #expect(controller.releaseURL == AppVersion(0, 2, 0).releasePage)
    controller.openReleasePage()
    #expect(outside.opened == [AppVersion(0, 2, 0).releasePage])
    #expect(fetcher.calls == 0)
}

@MainActor
@Test func aStoredVersionThatIsNoLongerNewerIsNotShown() {
    let controller = controller(store: FakeUpdateState(latest: AppVersion(0, 1, 0)))
    #expect(controller.state == .idle)
}

@MainActor
@Test func openingTheReleasePageWithNothingKnownDoesNothing() {
    let outside = Outside()
    controller(outside: outside).openReleasePage()
    #expect(outside.opened.isEmpty)
}

@MainActor
@Test func aManualCheckThatFindsNothingNewIsUpToDate() async {
    let store = FakeUpdateState(latest: AppVersion(0, 2, 0))
    let controller = controller(FakeReleaseFetcher([.success("v0.1.0")]), store: store)
    await controller.checkNow()
    #expect(controller.state == .upToDate)
    #expect(store.updateLatestVersion == nil)
    #expect(store.updateLastCheck == launch)
}

@MainActor
@Test func aManualCheckThatFindsANewerVersionShowsItAndPostsNothing() async {
    let store = FakeUpdateState()
    let outside = Outside()
    let controller = controller(FakeReleaseFetcher([.success("v0.2.0")]), store: store, outside: outside)
    await controller.checkNow()
    #expect(controller.state == .available(AppVersion(0, 2, 0)))
    #expect(store.updateLatestVersion == AppVersion(0, 2, 0))
    #expect(store.updateAnnouncedVersion == AppVersion(0, 2, 0))
    #expect(outside.announced.isEmpty)
}

@MainActor
@Test func aFailedManualCheckSaysSoAndCountsAsAnAttempt() async {
    let store = FakeUpdateState()
    let outside = Outside()
    let controller = controller(FakeReleaseFetcher([offline]), store: store, outside: outside)
    await controller.checkNow()
    #expect(controller.state == .failed)
    #expect(store.updateLastCheck == launch)
    #expect(outside.announced.isEmpty)
}

@MainActor
@Test func twoPressesAtOnceMakeOneRequest() async {
    let fetcher = FakeReleaseFetcher([.success("v0.1.0")])
    let controller = controller(fetcher)
    async let first: Void = controller.checkNow()
    async let second: Void = controller.checkNow()
    _ = await (first, second)
    #expect(fetcher.calls == 1)
}

@MainActor
@Test func aRunningVersionThatCannotBeReadFailsWithoutARequest() async {
    let fetcher = FakeReleaseFetcher([.success("v0.2.0")])
    let controller = controller(fetcher, running: nil)
    await controller.checkNow()
    #expect(controller.state == .failed)
    #expect(fetcher.calls == 0)
}

@MainActor
@Test func aRunningVersionThatCannotBeReadShowsFailedWhenTheDailySwitchGoesOn() async {
    let fetcher = FakeReleaseFetcher([.success("v0.2.0")])
    let controller = controller(fetcher, running: nil)
    await controller.setDailyCheck(true)
    #expect(controller.state == .failed)
    #expect(fetcher.calls == 0)
}

@MainActor
private final class Holder {
    var controller: UpdateController?
}

@MainActor
@Test func aSwitchTurnedOffWhileACheckRunsDoesNotAnnounce() async {
    let holder = Holder()
    let outside = Outside()
    let store = FakeUpdateState(daily: true)
    let fetcher = HookedReleaseFetcher(.success("v0.2.0")) { await holder.controller?.setDailyCheck(false) }
    let controller = controller(fetcher, store: store, outside: outside)
    holder.controller = controller
    await controller.start()
    #expect(controller.state == .available(AppVersion(0, 2, 0)))
    #expect(outside.announced.isEmpty)
    #expect(store.updateAnnouncedVersion == nil)
    #expect(!controller.wakeIsScheduled)
}

@MainActor
@Test func withTheDailySwitchOffNothingRunsAtLaunch() async {
    let fetcher = FakeReleaseFetcher([.success("v0.2.0")])
    let controller = controller(fetcher)
    await controller.start()
    #expect(fetcher.calls == 0)
    #expect(!controller.wakeIsScheduled)
}

@MainActor
@Test func aDailyCheckThatNeverRanRunsAtLaunchAndSchedulesTheNext() async {
    let fetcher = FakeReleaseFetcher([.success("v0.1.0")])
    let controller = controller(fetcher, store: FakeUpdateState(daily: true))
    await controller.start()
    #expect(fetcher.calls == 1)
    #expect(controller.wakeIsScheduled)
}

@MainActor
@Test func aDailyCheckThatRanAnHourAgoWaits() async {
    let fetcher = FakeReleaseFetcher([.success("v0.2.0")])
    let controller = controller(fetcher, store: FakeUpdateState(daily: true, lastCheck: launch.addingTimeInterval(-3600)))
    await controller.start()
    #expect(fetcher.calls == 0)
    #expect(controller.wakeIsScheduled)
}

@MainActor
@Test func aMacThatSleptForDaysChecksOnceOnWake() async {
    let fetcher = FakeReleaseFetcher([.success("v0.1.0")])
    let clock = Clock()
    let controller = controller(fetcher, store: FakeUpdateState(daily: true, lastCheck: launch.addingTimeInterval(-5 * day)),
                                clock: clock)
    await controller.checkIfDue()
    #expect(fetcher.calls == 1)
    await controller.checkIfDue()
    #expect(fetcher.calls == 1)
    clock.now = launch.addingTimeInterval(day)
    await controller.checkIfDue()
    #expect(fetcher.calls == 2)
}

@MainActor
@Test func aNewVersionIsAnnouncedOncePerVersion() async {
    let fetcher = FakeReleaseFetcher([.success("v0.2.0"), .success("v0.2.0"), .success("v0.3.0")])
    let clock = Clock()
    let outside = Outside()
    let controller = controller(fetcher, store: FakeUpdateState(daily: true), clock: clock, outside: outside)
    await controller.start()
    #expect(outside.announced == [AppVersion(0, 2, 0)])
    clock.now = launch.addingTimeInterval(day)
    await controller.checkIfDue()
    #expect(fetcher.calls == 2)
    #expect(outside.announced == [AppVersion(0, 2, 0)])
    clock.now = launch.addingTimeInterval(2 * day)
    await controller.checkIfDue()
    #expect(outside.announced == [AppVersion(0, 2, 0), AppVersion(0, 3, 0)])
}

@MainActor
@Test func aManualFindIsNotAnnouncedAgain() async {
    let fetcher = FakeReleaseFetcher([.success("v0.2.0")])
    let clock = Clock()
    let outside = Outside()
    let controller = controller(fetcher, store: FakeUpdateState(daily: true), clock: clock, outside: outside)
    await controller.checkNow()
    clock.now = launch.addingTimeInterval(day)
    await controller.checkIfDue()
    #expect(fetcher.calls == 2)
    #expect(outside.announced.isEmpty)
}

@MainActor
@Test func aFailedAutomaticCheckIsSilentAndIsRetriedAfterAnHour() async {
    let fetcher = FakeReleaseFetcher([offline])
    let store = FakeUpdateState(daily: true)
    let clock = Clock()
    let outside = Outside()
    let controller = controller(fetcher, store: store, clock: clock, outside: outside)
    await controller.start()
    #expect(controller.state == .idle)
    #expect(fetcher.calls == 1)
    await controller.checkIfDue()
    #expect(fetcher.calls == 1)
    clock.now = launch.addingTimeInterval(UpdateSchedule.retryInterval - 1)
    await controller.checkIfDue()
    #expect(fetcher.calls == 1)
    clock.now = launch.addingTimeInterval(UpdateSchedule.retryInterval)
    await controller.checkIfDue()
    #expect(fetcher.calls == 2)
    #expect(outside.announced.isEmpty)
}

@MainActor
@Test func aNewerVersionStaysKnownWhenACheckFails() async {
    let outside = Outside()
    let controller = controller(FakeReleaseFetcher([offline]), store: FakeUpdateState(latest: AppVersion(0, 2, 0)),
                                outside: outside)
    await controller.checkNow()
    #expect(controller.state == .failed)
    #expect(controller.newerVersion == AppVersion(0, 2, 0))
    controller.openReleasePage()
    #expect(outside.opened == [AppVersion(0, 2, 0).releasePage])
}

@MainActor
@Test func aCheckThatFindsNothingNewForgetsTheNewerVersion() async {
    let controller = controller(FakeReleaseFetcher([.success("v0.1.0")]),
                                store: FakeUpdateState(latest: AppVersion(0, 2, 0)))
    await controller.checkNow()
    #expect(controller.newerVersion == nil)
    #expect(controller.releaseURL == nil)
}

@MainActor
@Test func aFailedAutomaticCheckKeepsAnEarlierAnswer() async {
    let controller = controller(FakeReleaseFetcher([offline]),
                                store: FakeUpdateState(daily: true, latest: AppVersion(0, 2, 0)))
    await controller.start()
    #expect(controller.state == .available(AppVersion(0, 2, 0)))
}

@MainActor
@Test func theDailySwitchStartsAndStopsTheSchedule() async {
    let fetcher = FakeReleaseFetcher([.success("v0.1.0")])
    let store = FakeUpdateState()
    let outside = Outside()
    let controller = controller(fetcher, store: store, outside: outside)
    await controller.setDailyCheck(true)
    #expect(outside.asked == 1)
    #expect(fetcher.calls == 1)
    #expect(store.updateCheckDaily)
    #expect(controller.dailyCheck)
    #expect(controller.wakeIsScheduled)
    await controller.setDailyCheck(false)
    #expect(!store.updateCheckDaily)
    #expect(!controller.dailyCheck)
    #expect(!controller.wakeIsScheduled)
    await controller.checkIfDue()
    #expect(fetcher.calls == 1)
}
