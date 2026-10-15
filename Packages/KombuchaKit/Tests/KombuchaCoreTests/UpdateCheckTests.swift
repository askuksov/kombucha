import Foundation
import KombuchaCore
import Testing

private struct FixedFetcher: ReleaseFetching {
    let result: Result<String, any Error>
    func latestTag() async throws -> String { try result.get() }
}

private let running = AppVersion(0, 1, 0)

private func outcome(_ result: Result<String, any Error>) async -> UpdateOutcome {
    await UpdateChecker(fetcher: FixedFetcher(result: result), running: running).check()
}

@Test func aNewerTagIsAvailable() async {
    #expect(await outcome(.success("v0.2.0")) == .available(AppVersion(0, 2, 0)))
    #expect(await outcome(.success("v0.1.1")) == .available(AppVersion(0, 1, 1)))
}

@Test func theSameOrAnOlderTagIsUpToDate() async {
    #expect(await outcome(.success("v0.1.0")) == .upToDate)
    #expect(await outcome(.success("v0.0.9")) == .upToDate)
}

@Test func aFetchThatThrowsIsAFailedCheck() async {
    #expect(await outcome(.failure(URLError(.notConnectedToInternet))) == .failed)
}

@Test(arguments: ["v0.2.0-beta", "latest", "", "0.2"])
func aTagThatIsNotAReleaseNumberIsAFailedCheck(tag: String) async {
    #expect(await outcome(.success(tag)) == .failed)
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func aCheckThatNeverRanIsDueNow() {
    #expect(UpdateSchedule.nextCheck(lastCheck: nil, now: now) == now)
}

@Test func theNextCheckIsADayAfterTheLastOne() {
    let hourAgo = now.addingTimeInterval(-3600)
    #expect(UpdateSchedule.nextCheck(lastCheck: hourAgo, now: now) == hourAgo.addingTimeInterval(UpdateSchedule.interval))
    let dayAgo = now.addingTimeInterval(-UpdateSchedule.interval)
    #expect(UpdateSchedule.nextCheck(lastCheck: dayAgo, now: now) == now)
}

@Test func aFailedCheckIsRetriedSoonerThanADay() {
    #expect(UpdateSchedule.retryInterval == 3600)
    #expect(UpdateSchedule.retryInterval < UpdateSchedule.interval)
}

@Test func aCheckStampedInTheFutureIsDueNow() {
    #expect(UpdateSchedule.nextCheck(lastCheck: now.addingTimeInterval(3600), now: now) == now)
}

@Test func aLongSleepLeavesTheDueMomentInThePast() {
    let fiveDaysAgo = now.addingTimeInterval(-5 * UpdateSchedule.interval)
    let due = UpdateSchedule.nextCheck(lastCheck: fiveDaysAgo, now: now)
    #expect(due <= now)
}

@Test func aVersionIsAnnouncedOnlyWhenNewerThanBothTheRunningAndTheAnnouncedOne() {
    let found = AppVersion(0, 2, 0)
    #expect(UpdateSchedule.shouldAnnounce(found: found, running: running, lastAnnounced: nil))
    #expect(!UpdateSchedule.shouldAnnounce(found: found, running: found, lastAnnounced: nil))
    #expect(!UpdateSchedule.shouldAnnounce(found: AppVersion(0, 0, 9), running: running, lastAnnounced: nil))
    #expect(!UpdateSchedule.shouldAnnounce(found: found, running: running, lastAnnounced: found))
    #expect(UpdateSchedule.shouldAnnounce(found: AppVersion(0, 3, 0), running: running, lastAnnounced: found))
    #expect(!UpdateSchedule.shouldAnnounce(found: AppVersion(0, 1, 5), running: running, lastAnnounced: AppVersion(0, 2, 0)))
}
