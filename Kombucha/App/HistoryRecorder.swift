import Foundation
import KombuchaCore
import Synchronization

/// Where a battery alert goes. The notification controller conforms; the recorder never touches the centre.
@MainActor
protocol BatteryAlertPosting: Sendable {
    func post(_ alert: BatteryAlert)
}

/// Hands every pass to several observers: the engine holds one.
struct CompositeObserver: ChargeObserving {
    private let observers: [any ChargeObserving]

    init(_ observers: [any ChargeObserving]) {
        self.observers = observers
    }

    func observe(_ snapshot: ChargeSnapshot, fullChargeEnded: FullChargeEnding?) {
        for observer in observers { observer.observe(snapshot, fullChargeEnded: fullChargeEnded) }
    }
}

/// Records the battery and watches it. `observe` runs on the engine's actor on every pass and returns at once:
/// unless a sample is due (50 s since the last one, so about once per engine tick) it does nothing, and a due
/// sample goes to a background queue that reads the registry, appends to the file and posts alerts, in order.
/// Nothing here holds the whole history in memory; the cursor and the watch are a few values.
final class HistoryRecorder: ChargeObserving, Sendable {
    private struct Sample: Sendable {
        let snapshot: ChargeSnapshot
        let time: Date
    }

    private struct State {
        var cursor = HistoryCursor()
        var watch = BatteryWatch()
        var failureLogged = false
    }

    private struct Outcome {
        var appendPoint = false
        var health: HealthPoint?
        var baseline: Int?
        var alerts: [BatteryAlert] = []
    }

    private let store: any HistoryStoring
    private let ui: any UISettingsStoring
    private let alerts: any BatteryAlertPosting
    private let readHealth: @Sendable () -> BatteryHealth?
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let state = Mutex(State())
    private let samples: AsyncStream<Sample>.Continuation
    private let pending = Mutex(0)

    init(store: any HistoryStoring,
         ui: any UISettingsStoring,
         alerts: any BatteryAlertPosting,
         readHealth: @escaping @Sendable () -> BatteryHealth?,
         now: @escaping @Sendable () -> Date = { Date() },
         calendar: Calendar = .current) {
        self.store = store
        self.ui = ui
        self.alerts = alerts
        self.readHealth = readHealth
        self.now = now
        self.calendar = calendar
        let (stream, continuation) = AsyncStream<Sample>.makeStream(bufferingPolicy: .unbounded)
        samples = continuation
        Task.detached(priority: .utility) { [weak self] in
            self?.start()
            for await sample in stream {
                await self?.process(sample)
                self?.pending.withLock { $0 -= 1 }
            }
        }
    }

    deinit {
        samples.finish()
    }

    nonisolated func observe(_ snapshot: ChargeSnapshot, fullChargeEnded: FullChargeEnding?) {
        let moment = now()
        guard state.withLock({ $0.cursor.isDue(at: moment) }) else { return }
        pending.withLock { $0 += 1 }
        samples.yield(Sample(snapshot: snapshot, time: moment))
    }

    /// Tests only: returns once every sample taken so far has been processed.
    func settled() async {
        while pending.withLock({ $0 > 0 }) { await Task.yield() }
    }

    /// Loads what the file holds, drops anything past retention, rewrites the file clean (this also removes a
    /// line a crash left half-written) and continues from the last point and the stored baseline. An empty log is
    /// never written back: `load()` also returns [] after a read error, and that must not erase the file.
    private func start() {
        let log = HistoryLog(records: store.load()).pruned(now: now())
        if !log.records.isEmpty { report(store.replaceAll(with: log.records)) }
        state.withLock {
            $0.cursor.resume(from: log)
            $0.watch = BatteryWatch(healthBaseline: log.baseline)
        }
    }

    private func process(_ sample: Sample) async {
        let health = readHealth()
        let temperature = health.flatMap { HistoryPoint.rounded($0.temperatureCelsius) }
        let point = HistoryPoint(snapshot: sample.snapshot, temperatureCelsius: temperature, at: sample.time)
        let day = calendar.startOfDay(for: sample.time)
        let enabled = ui.notifyBatteryAttention
        let outcome = state.withLock { state -> Outcome in
            var outcome = Outcome()
            outcome.appendPoint = state.cursor.accept(point)
            if let health, state.cursor.acceptHealth(day: day) {
                outcome.health = HealthPoint(day: day, maximumCapacityPercent: health.maximumCapacityPercent,
                                             cycleCount: health.cycleCount)
            }
            let before = state.watch.healthBaseline
            outcome.alerts = state.watch.observe(snapshot: sample.snapshot,
                                                 temperatureCelsius: temperature,
                                                 dailyCapacityPercent: outcome.health?.maximumCapacityPercent,
                                                 now: sample.time,
                                                 enabled: enabled)
            if state.watch.healthBaseline != before { outcome.baseline = state.watch.healthBaseline }
            return outcome
        }
        var written = true
        if outcome.appendPoint { written = store.append(.point(point)) && written }
        if let health = outcome.health { written = store.append(.health(health)) && written }
        if let baseline = outcome.baseline { written = store.append(.baseline(baseline)) && written }
        // Once a day, with the day's health point: drop what went out of retention.
        if outcome.health != nil {
            // Same guard as at launch: an empty log may be a failed read, and a skipped rewrite is not a failure.
            let log = HistoryLog(records: store.load()).pruned(now: sample.time)
            if !log.records.isEmpty { written = store.replaceAll(with: log.records) && written }
        }
        report(written)
        for alert in outcome.alerts { await alerts.post(alert) }
    }

    /// A failed write is logged once per launch and otherwise ignored.
    private func report(_ written: Bool) {
        guard !written, state.withLock({ state in
            defer { state.failureLogged = true }
            return !state.failureLogged
        }) else { return }
        AppLog.history.error("the history file could not be written")
    }
}
