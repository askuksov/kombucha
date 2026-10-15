import Foundation

/// Where the latest release tag comes from. The app's implementation talks to GitHub; tests use a fake.
public protocol ReleaseFetching: Sendable {
    /// The tag name of the latest published release, such as `v0.2.0`. Throws when it cannot be read.
    func latestTag() async throws -> String
}

public enum UpdateOutcome: Equatable, Sendable {
    case upToDate
    case available(AppVersion)
    case failed
}

/// One look at the latest release, compared with the running version.
public struct UpdateChecker: Sendable {
    private let fetcher: any ReleaseFetching
    private let running: AppVersion

    public init(fetcher: any ReleaseFetching, running: AppVersion) {
        self.fetcher = fetcher
        self.running = running
    }

    /// A fetch that throws and a tag that is not a release number are both `.failed`: never a false "available".
    public func check() async -> UpdateOutcome {
        guard let tag = try? await fetcher.latestTag(), let latest = AppVersion(tag) else { return .failed }
        return latest > running ? .available(latest) : .upToDate
    }
}

/// When to check and when to announce. The clock is a parameter.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60
    /// How long a failed automatic check waits before the next try: a Mac that wakes before Wi-Fi is back
    /// should not lose a whole day.
    public static let retryInterval: TimeInterval = 60 * 60

    /// A check that never ran, or one stamped in the future, is due now. After a long sleep the result is in
    /// the past: the caller checks once, not once per missed day.
    public static func nextCheck(lastCheck: Date?, now: Date) -> Date {
        guard let lastCheck, lastCheck <= now else { return now }
        return lastCheck.addingTimeInterval(interval)
    }

    public static func shouldAnnounce(found: AppVersion, running: AppVersion, lastAnnounced: AppVersion?) -> Bool {
        guard found > running else { return false }
        guard let lastAnnounced else { return true }
        return found > lastAnnounced
    }
}
