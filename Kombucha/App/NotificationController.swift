import Foundation
import KombuchaCore
import Synchronization
import UserNotifications

/// Turns the decider's posts into notifications. The engine calls `observe` from its own actor on every pass,
/// so the calls go through one stream and are applied in order: out-of-order passes would break the dedupe and
/// the one-stopped-per-interruption bookkeeping.
@MainActor
final class NotificationController: NSObject, ChargeObserving, BatteryAlertPosting, @preconcurrency UNUserNotificationCenterDelegate {
    static let writePathCategory = "dev.kuksov.kombucha.notification.writePath"
    static let updateCategory = "dev.kuksov.kombucha.notification.update"

    private enum Event {
        case pass(ChargeSnapshot, FullChargeEnding?)
        case tick
    }

    private var decider = NotificationDecider()
    private let centre: any NotificationCentering
    private let ui: any UISettingsStoring
    private let now: @Sendable () -> Date
    private let openHelperTab: @MainActor () -> Void
    private let events: AsyncStream<Event>.Continuation
    private var pump: Task<Void, Never>?
    private var wake: Task<Void, Never>?
    /// Events yielded and not yet applied; `settled()` waits for it to reach zero. Incremented synchronously
    /// inside `observe`, before the yield, and decremented by the pump after `apply(event)` — a `Mutex` rather
    /// than a `Task { @MainActor in ... }` hop, because that hop can land after the pump has already applied
    /// the event and decremented, sending the counter negative and letting `settled()` return early.
    private let pending = Mutex(0)

    var wakeIsScheduled: Bool { wake != nil }

    /// Set by the app: opens the release page of the newest known version. The click carries no payload.
    var openUpdate: @MainActor () -> Void = {}

    init(centre: any NotificationCentering,
         ui: any UISettingsStoring,
         now: @escaping @Sendable () -> Date = { Date() },
         openHelperTab: @MainActor @escaping () -> Void) {
        self.centre = centre
        self.ui = ui
        self.now = now
        self.openHelperTab = openHelperTab
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        events = continuation
        super.init()
        centre.register(categories: [UNNotificationCategory(identifier: Self.writePathCategory,
                                                            actions: [],
                                                            intentIdentifiers: [],
                                                            options: []),
                                     UNNotificationCategory(identifier: Self.updateCategory,
                                                            actions: [],
                                                            intentIdentifiers: [],
                                                            options: [])])
        centre.setDelegate(self)
        pump = Task { @MainActor [weak self] in
            for await event in stream {
                self?.apply(event)
                self?.pending.withLock { $0 -= 1 }
            }
        }
    }

    deinit {
        events.finish()
    }

    nonisolated func observe(_ snapshot: ChargeSnapshot, fullChargeEnded: FullChargeEnding?) {
        pending.withLock { $0 += 1 }
        events.yield(.pass(snapshot, fullChargeEnded))
    }

    /// Tests only: returns once every event yielded so far has been applied.
    func settled() async {
        while pending.withLock({ $0 > 0 }) { await Task.yield() }
    }

    /// Tests only: applies a tick without waiting for the timer.
    func tickNow() async {
        apply(.tick)
        await settled()
    }

    /// The comparison FR-NOT-4 asks for, plus the update category. The delegate method is a two-line adapter over this.
    func respond(toCategory identifier: String) {
        if identifier == Self.writePathCategory {
            openHelperTab()
        } else if identifier == Self.updateCategory {
            openUpdate()
        }
    }

    /// A battery alert has no place to go (no category, FR-NOT-4 concerns the write path only).
    func post(_ alert: BatteryAlert) {
        let content = UNMutableNotificationContent()
        content.title = Copy.alertTitle(alert)
        content.body = Copy.alertBody(alert)
        centre.post(content)
    }

    /// An update announcement: its gate is the daily-check switch, not the three notification switches. If macOS
    /// has not allowed notifications it drops the post and About still shows the version.
    func postUpdate(_ version: AppVersion) {
        let content = UNMutableNotificationContent()
        content.title = Copy.updateNotificationTitle(version)
        content.body = Copy.updateNotificationBody
        content.categoryIdentifier = Self.updateCategory
        centre.post(content)
    }

    /// The completion-handler form, not the async one: this is the shape every macOS in the supported range
    /// agrees on.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        respond(toCategory: response.notification.request.content.categoryIdentifier)
        completionHandler()
    }

    private func apply(_ event: Event) {
        let gates = NotificationGates(fullChargeFinished: ui.notifyFullChargeFinished,
                                      protectionChanges: ui.notifyProtectionChanges)
        let decision: NotificationDecision
        switch event {
        case .pass(let snapshot, let ending):
            decision = decider.observe(snapshot, fullChargeEnded: ending, gates: gates, now: now())
        case .tick:
            decision = decider.tick(gates: gates, now: now())
        }
        for post in decision.posts { send(post) }
        schedule(decision.wakeAt)
    }

    private func send(_ post: NotificationPost) {
        let content = UNMutableNotificationContent()
        content.title = Copy.notificationTitle(post)
        content.body = Copy.notificationBody(post)
        if case .protectionStopped(.writePathBlocked) = post {
            // Only a write-path notification has somewhere to go (FR-NOT-4).
            content.categoryIdentifier = Self.writePathCategory
        }
        centre.post(content)
    }

    private func schedule(_ moment: Date?) {
        wake?.cancel()
        wake = nil
        guard let moment else { return }
        let delay = max(0, moment.timeIntervalSince(now()))
        wake = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.wake = nil
            self?.apply(.tick)
        }
    }
}
