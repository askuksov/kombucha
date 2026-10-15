import Foundation
import KombuchaCore
import Observation

/// Looks for a newer release when asked and, if the user turned it on, once a day. It installs nothing.
@MainActor
@Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppVersion)
        case failed
    }

    private(set) var state: State
    private(set) var dailyCheck: Bool
    /// The newest version known to be newer than the running one. It outlives a running check, so the link and
    /// the notification click keep working while `state` says "Checking…".
    private(set) var newerVersion: AppVersion?

    @ObservationIgnored private let checker: UpdateChecker?
    @ObservationIgnored private let running: AppVersion?
    @ObservationIgnored private let store: any UpdateStateStoring
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let announce: @MainActor (AppVersion) -> Void
    @ObservationIgnored private let askForNotifications: @MainActor () async -> Void
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var inFlight = false

    var wakeIsScheduled: Bool { wake != nil }

    /// The page of the newest version known to be newer than the running one.
    var releaseURL: URL? { newerVersion?.releasePage }

    /// A running version that cannot be read (`running` nil) makes every check fail without a request.
    init(fetcher: any ReleaseFetching,
         running: AppVersion?,
         store: any UpdateStateStoring,
         now: @escaping @Sendable () -> Date = { Date() },
         announce: @escaping @MainActor (AppVersion) -> Void,
         askForNotifications: @escaping @MainActor () async -> Void,
         openURL: @escaping @MainActor (URL) -> Void) {
        self.running = running
        self.checker = running.map { UpdateChecker(fetcher: fetcher, running: $0) }
        self.store = store
        self.now = now
        self.announce = announce
        self.askForNotifications = askForNotifications
        self.openURL = openURL
        dailyCheck = store.updateCheckDaily
        if let running, let latest = store.updateLatestVersion, latest > running {
            newerVersion = latest
            state = .available(latest)
        } else {
            state = .idle
        }
    }

    func openReleasePage() {
        if let releaseURL { openURL(releaseURL) }
    }

    /// The button. Runs whatever the daily switch says.
    func checkNow() async {
        await check(automatic: false)
    }

    /// At launch: with the daily switch on, a check that is due runs now and the next one is scheduled.
    func start() async {
        await checkIfDue()
    }

    /// The wake-up and the launch both come here, so a long sleep produces one check, not one per missed day.
    func checkIfDue() async {
        guard dailyCheck, checker != nil else { return }
        let due = UpdateSchedule.nextCheck(lastCheck: store.updateLastCheck, now: now())
        if due <= now() {
            await check(automatic: true)
        } else {
            schedule()
        }
    }

    /// Switching on asks for notification permission when it was never answered and checks at once.
    func setDailyCheck(_ on: Bool) async {
        store.setUpdateCheckDaily(on)
        dailyCheck = on
        guard on else {
            wake?.cancel()
            wake = nil
            return
        }
        await askForNotifications()
        await check(automatic: true)
        schedule()
    }

    private func check(automatic: Bool) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        store.setUpdateLastCheck(now())
        guard let checker, let running else {
            if !automatic { state = .failed }
            return
        }
        let before = state
        state = .checking
        switch await checker.check() {
        case .failed:
            state = automatic ? before : .failed
            // Backdate the stamp so the next try comes after `retryInterval`, not after a whole day.
            if automatic { store.setUpdateLastCheck(now().addingTimeInterval(UpdateSchedule.retryInterval - UpdateSchedule.interval)) }
        case .upToDate:
            store.setUpdateLatestVersion(nil)
            newerVersion = nil
            state = .upToDate
        case .available(let found):
            store.setUpdateLatestVersion(found)
            newerVersion = found
            state = .available(found)
            if UpdateSchedule.shouldAnnounce(found: found, running: running, lastAnnounced: store.updateAnnouncedVersion) {
                // A manual find counts as announced without a notification: the user is looking at it.
                if automatic { announce(found) }
                store.setUpdateAnnouncedVersion(found)
            }
        }
        schedule()
    }

    private func schedule() {
        wake?.cancel()
        wake = nil
        guard dailyCheck, checker != nil else { return }
        let due = UpdateSchedule.nextCheck(lastCheck: store.updateLastCheck, now: now())
        let delay = max(0, due.timeIntervalSince(now()))
        wake = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.wake = nil
            await self?.checkIfDue()
        }
    }
}
