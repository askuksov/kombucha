import KombuchaCore
import Observation
import ServiceManagement
import UserNotifications

/// UI state on the main actor: the newest snapshot, the support verdict, what is being asked of the engine
/// and what became of it.
@MainActor
@Observable
final class AppModel {
    enum HealthState: Equatable {
        case reading, unavailable, read(BatteryHealth)
    }

    /// What Settings → Battery shows about power. `apps` is nil until a second sample exists ("Measuring…"),
    /// and empty when nothing is using noticeable power. `adapterShown` is decided when the numbers are sampled and
    /// freezes with them, so a paused display never mixes old numbers with a new row layout.
    struct PowerState: Equatable {
        var readings: PowerReadings?
        var apps: [AppEnergy]?
        var adapterShown: Bool
        static let empty = PowerState(readings: nil, apps: nil, adapterShown: false)
    }

    /// The chart data for both ranges, built when the History tab opens.
    struct HistoryContent: Equatable {
        var week: [HistoryBucket]
        var month: [HistoryBucket]
        var health: [HealthPoint]
        /// The moment the buckets were built for; the chart's x axis ends here.
        var generatedAt: Date
    }

    enum HistoryState: Equatable {
        case loading, empty, ready(HistoryContent)
    }

    private(set) var snapshot: ChargeSnapshot?
    private(set) var verdict: SupportVerdict?
    private(set) var health: HealthState = .reading
    private(set) var power: PowerState = .empty
    private(set) var history: HistoryState = .loading
    private(set) var controlFailure: ActionFailure?
    private(set) var helperFailure: ActionFailure?
    /// A requested value, shown until the engine answers.
    private(set) var pendingProtection: Bool?
    private(set) var pendingFullCharge: Bool?
    private(set) var pendingDischarge: Bool?
    private(set) var pendingHelperAction = false
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    private(set) var welcomePending = false
    /// The store's own defaults are all three on, so these starting values are right even before anything is
    /// attached. Tracked stored properties, not pass-throughs to `ui`, so a bound view is re-rendered: `ui`
    /// itself is `@ObservationIgnored` and neither `SettingsStore` nor `FakeUISettings` is `@Observable`.
    private(set) var notifyFullChargeFinished = true
    private(set) var notifyProtectionChanges = true
    private(set) var notifyBatteryAttention = true
    var settingsTab: SettingsTab = .general
    /// `MenuBarLabel` sets this once, from its own `@Environment(\.openSettings)`: the only proven way to open
    /// the Settings scene from outside a view. A notification click has no view of its own to read the
    /// environment from, so it calls this instead of the private `showSettingsWindow:` selector, which does
    /// not fire reliably (found live, 2026-09-30).
    @ObservationIgnored var openSettingsAction: (() -> Void)?

    /// While anything is pending, a press does nothing.
    var isPending: Bool { pendingProtection != nil || pendingFullCharge != nil || pendingDischarge != nil || pendingHelperAction }

    /// The switch is on only when macOS says the item is enabled: `requiresApproval` is not on.
    var launchAtLoginIsOn: Bool { loginItemStatus == .enabled }
    var launchAtLoginNeedsApproval: Bool { loginItemStatus == .requiresApproval }

    @ObservationIgnored private var engine: Engine?
    @ObservationIgnored private var settings: (any SettingsStoring)?
    @ObservationIgnored private var loginItem: (any LoginItemControlling)?
    @ObservationIgnored private var notifications: (any NotificationCentering)?
    @ObservationIgnored private var ui: (any UISettingsStoring)?
    @ObservationIgnored private let readHealth: @Sendable () -> BatteryHealth?
    @ObservationIgnored private let readPower: @Sendable () -> PowerReadings
    @ObservationIgnored private let sampleEnergy: @Sendable () -> EnergyReading
    @ObservationIgnored private let readHistory: @Sendable () -> HistoryLog
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var historyGeneration = 0
    @ObservationIgnored private var previousEnergy: EnergyReading?
    /// The last few raw readings, averaged before they are shown.
    @ObservationIgnored private var recentReadings: [PowerReadings] = []
    /// Bumped by every pause and reset, so a step that started before one can tell it is stale.
    @ObservationIgnored private var powerGeneration = 0
    /// The SMC reports system power about one update after adapter power, so a single reading can show System
    /// above Adapter; the mean of the last three (about 6 s) smooths that out.
    private static let smoothingWindow = 3

    init(readHealth: @escaping @Sendable () -> BatteryHealth? = { nil },
         readPower: @escaping @Sendable () -> PowerReadings = { PowerReadings(systemWatts: nil, adapterWatts: nil) },
         sampleEnergy: @escaping @Sendable () -> EnergyReading = { EnergyReading(samples: [], seconds: 0) },
         readHistory: @escaping @Sendable () -> HistoryLog = { HistoryLog() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.readHealth = readHealth
        self.readPower = readPower
        self.sampleEnergy = sampleEnergy
        self.readHistory = readHistory
        self.now = now
    }

    func attach(engine: Engine, settings: any SettingsStoring) {
        self.engine = engine
        self.settings = settings
    }

    func attach(loginItem: any LoginItemControlling, notifications: any NotificationCentering,
                ui: any UISettingsStoring) {
        self.loginItem = loginItem
        self.notifications = notifications
        self.ui = ui
        refreshLoginItem()
        notifyFullChargeFinished = ui.notifyFullChargeFinished
        notifyProtectionChanges = ui.notifyProtectionChanges
        notifyBatteryAttention = ui.notifyBatteryAttention
    }

    /// Set after the support verdict: a Mac whose welcome was never finished opens it (§5.6).
    func publish(_ verdict: SupportVerdict) {
        self.verdict = verdict
        welcomePending = !(ui?.welcomeCompleted ?? true)
    }

    func refreshLoginItem() {
        guard let loginItem else { return }
        loginItemStatus = loginItem.status
    }

    /// Registers or unregisters, then shows the status macOS reports — never the requested value (FR-SET-2).
    func setLaunchAtLogin(_ on: Bool) async {
        guard let loginItem else { return }
        do {
            if on { try loginItem.register() } else { try loginItem.unregister() }
        } catch {
            AppLog.ui.error("the login item refused: \(error.localizedDescription, privacy: .public)")
        }
        refreshLoginItem()
    }

    func refreshNotificationAuthorization() async {
        guard let notifications else { return }
        notificationAuthorization = await notifications.authorization()
    }

    func requestNotificationAuthorization() async {
        guard let notifications else { return }
        notificationAuthorization = await notifications.requestAuthorization()
    }

    func setNotifyFullChargeFinished(_ on: Bool) async {
        ui?.setNotifyFullChargeFinished(on)
        notifyFullChargeFinished = on
        await askIfNeeded(on)
    }

    func setNotifyProtectionChanges(_ on: Bool) async {
        ui?.setNotifyProtectionChanges(on)
        notifyProtectionChanges = on
        await askIfNeeded(on)
    }

    func setNotifyBatteryAttention(_ on: Bool) async {
        ui?.setNotifyBatteryAttention(on)
        notifyBatteryAttention = on
        await askIfNeeded(on)
    }

    /// Clears the flag once the welcome window is on screen.
    func welcomeOpened() {
        welcomePending = false
    }

    func finishWelcome(launchAtLogin: Bool, fullCharge: Bool, protectionChanges: Bool) async {
        if launchAtLogin { await setLaunchAtLogin(true) }
        ui?.setNotifyFullChargeFinished(fullCharge)
        notifyFullChargeFinished = fullCharge
        ui?.setNotifyProtectionChanges(protectionChanges)
        notifyProtectionChanges = protectionChanges
        if fullCharge || protectionChanges || notifyBatteryAttention { await requestNotificationAuthorization() }
        ui?.setWelcomeCompleted(true)
        welcomePending = false
    }

    /// Switching a notification on for the first time is where macOS is asked (FR-NOT-3); switching off asks
    /// nothing, and a second switch-on asks nothing because the answer is already in.
    private func askIfNeeded(_ on: Bool) async {
        guard on, notificationAuthorization == .notDetermined else { return }
        await requestNotificationAuthorization()
    }

    /// Returns when the engine ends the stream.
    func consume(_ snapshots: AsyncStream<ChargeSnapshot>) async {
        for await snapshot in snapshots {
            self.snapshot = snapshot
        }
    }

    /// The panel and the Helper tab send it on every appearance: a helper whose job is gone is repaired only
    /// after a failed ping.
    func probeHelper() async {
        _ = await engine?.probe()
    }

    /// Every opening clears the control failure line and probes the helper.
    func panelOpened() async {
        controlFailure = nil
        await probeHelper()
    }

    func refreshHealth() {
        health = readHealth().map(HealthState.read) ?? .unavailable
    }

    /// One sample step for the Battery tab's loop. The system calls run off the main actor; a step that finishes
    /// after the loop was cancelled changes nothing. A step that started before a pause or reset must not
    /// repopulate the baselines or overwrite the numbers, whatever order SwiftUI cancels the task and calls
    /// onChange in, so the generation is checked as well.
    func refreshPower() async {
        let generation = powerGeneration
        let readPower = readPower, sampleEnergy = sampleEnergy
        let (readings, energy) = await Task.detached(priority: .utility) { (readPower(), sampleEnergy()) }.value
        guard !Task.isCancelled, generation == powerGeneration else { return }
        // With no previous sample the tab keeps what it shows: nil at the first start, the old list after a pause.
        let apps = previousEnergy.map { EnergyRanking.top(3, previous: $0, current: energy) } ?? power.apps
        previousEnergy = energy
        recentReadings.append(readings)
        recentReadings = Array(recentReadings.suffix(Self.smoothingWindow))
        power = PowerState(readings: PowerReadings.average(recentReadings), apps: apps,
                           adapterShown: Self.adapterRowApplies(snapshot))
    }

    /// Whether the Adapter row belongs on screen. The row means "this much comes from the adapter": next to System
    /// it shows how much goes into the battery, so it exists only while the battery charges on AC (not at rest in
    /// Battery Rest, not on battery). Decided when the numbers are sampled so a frozen display stays consistent.
    private static func adapterRowApplies(_ snapshot: ChargeSnapshot?) -> Bool {
        snapshot.map { $0.onAC && $0.charging } ?? false
    }

    /// The window lost focus: the numbers stay on screen, only the baselines go, so the next sample neither
    /// averages watts nor ranks apps over the idle time.
    func pausePower() {
        powerGeneration += 1
        previousEnergy = nil
        recentReadings = []
    }

    /// The tab left the front: forget the numbers and the sample, so the next visit measures from scratch.
    func resetPower() {
        powerGeneration += 1
        power = .empty
        previousEnergy = nil
        recentReadings = []
    }

    /// Reads the history file and builds both ranges off the main actor. A result that arrives after the tab
    /// went away changes nothing.
    func loadHistory() async {
        let generation = historyGeneration
        let readHistory = readHistory, now = now
        let content = await Task.detached(priority: .utility) { () -> HistoryContent? in
            let log = readHistory()
            guard !log.points.isEmpty else { return nil }
            let moment = now()
            return HistoryContent(week: log.buckets(.week, now: moment),
                                  month: log.buckets(.month, now: moment),
                                  health: log.healthPoints,
                                  generatedAt: moment)
        }.value
        guard !Task.isCancelled, generation == historyGeneration else { return }
        history = content.map(HistoryState.ready) ?? .empty
    }

    /// The tab left the front: let go of the chart data (NFR-3).
    func unloadHistory() {
        historyGeneration += 1
        history = .loading
    }

    func setProtection(_ on: Bool) async {
        guard begin() else { return }
        pendingProtection = on
        defer { pendingProtection = nil }
        controlFailure = await failure(of: { await $0.setProtection(on) })
    }

    func setFullCharge(_ on: Bool) async {
        guard begin() else { return }
        pendingFullCharge = on
        defer { pendingFullCharge = nil }
        controlFailure = await failure(of: { await $0.setFullCharge(on) })
    }

    func setDischarge(_ on: Bool) async {
        guard begin() else { return }
        pendingDischarge = on
        defer { pendingDischarge = nil }
        controlFailure = await failure(of: { await $0.setDischarge(on) })
    }

    func installHelper() async {
        guard begin() else { return }
        pendingHelperAction = true
        defer { pendingHelperAction = false }
        helperFailure = await failure(of: { await $0.installHelper() })
    }

    func removeHelper() async {
        guard begin() else { return }
        pendingHelperAction = true
        defer { pendingHelperAction = false }
        helperFailure = await failure(of: { await $0.removeHelper() })
    }

    /// Thresholds are not an engine action: the store reports the change and nobody waits.
    func setUpper(_ value: Int) {
        guard let settings else { return }
        let moved = settings.chargeSettings.thresholds.movingUpper(to: value)
        settings.setThresholds(lower: moved.lower, upper: moved.upper)
    }

    func setLower(_ value: Int) {
        guard let settings else { return }
        let moved = settings.chargeSettings.thresholds.movingLower(to: value)
        settings.setThresholds(lower: moved.lower, upper: moved.upper)
    }

    /// A press is taken only with an engine and nothing pending; it clears both failure lines.
    private func begin() -> Bool {
        guard engine != nil, !isPending else { return false }
        controlFailure = nil
        helperFailure = nil
        return true
    }

    private func failure(of action: (Engine) async -> ActionResult) async -> ActionFailure? {
        guard let engine, case .failed(let failure) = await action(engine) else { return nil }
        return failure
    }
}
