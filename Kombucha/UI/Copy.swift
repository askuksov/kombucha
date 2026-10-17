import Foundation
import KombuchaCore

/// What the top of the panel says; a nil part is not shown.
struct PanelHeader: Equatable {
    let level: String?
    let title: String?
    let detail: String?
    let note: String?
}

/// Every sentence the user reads. Views take their text from here and never build it.
enum Copy {
    // MARK: Panel header

    static func header(for state: PanelState) -> PanelHeader {
        switch state {
        case .unsupported(let verdict):
            PanelHeader(level: nil, title: unsupportedHeading, detail: unsupportedReason(verdict), note: unsupportedNote)
        case .firstReading:
            PanelHeader(level: firstReading, title: nil, detail: nil, note: nil)
        case .writePathBlocked(let path, let level):
            PanelHeader(level: percent(level), title: heading(path), detail: reason(path), note: nil)
        case .externalBatteryManager(let manager, let level):
            PanelHeader(level: percent(level), title: externalManagerHeading(manager),
                        detail: externalManagerReason(manager), note: nil)
        case .controls(let snapshot):
            PanelHeader(level: percent(snapshot.displayLevel), title: statusLine(snapshot.mode, snapshot.thresholds),
                        detail: explanation(snapshot.mode, snapshot.thresholds), note: nil)
        }
    }

    static func menuBarAccessibilityLabel(_ state: PanelState) -> String {
        switch state {
        case .firstReading:
            "Kombucha"
        case .unsupported:
            String(localized: "Kombucha, \(unsupportedHeading)")
        case .writePathBlocked(_, let level), .externalBatteryManager(_, let level):
            String(localized: "Kombucha, \(level)%, \(header(for: state).title ?? "")")
        case .controls(let snapshot):
            String(localized: "Kombucha, \(snapshot.displayLevel)%, \(statusLine(snapshot.mode, snapshot.thresholds))")
        }
    }

    // MARK: Modes

    static func statusLine(_ mode: Mode, _ range: Thresholds) -> String {
        switch mode {
        case .protected: String(localized: "Protected: Battery resting \(range.lower)% – \(range.upper)%")
        case .charging: String(localized: "Charging: Topping up to \(range.upper)%")
        case .fullCharge: String(localized: "Charging to 100%: reverts on unplug")
        case .protectionOff: String(localized: "Protection off: charging to 100%")
        case .onBattery: String(localized: "On battery: protection resumes on AC")
        case .heatPaused: String(localized: "Charging paused: battery is hot")
        case .discharging: String(localized: "Discharging: running on battery down to \(range.upper)%")
        }
    }

    static func explanation(_ mode: Mode, _ range: Thresholds) -> String {
        switch mode {
        case .protected:
            String(localized: "Your Mac is running straight from the adapter — nothing is wrong with the charger. The battery rests until it reaches \(range.lower)%.")
        case .charging:
            String(localized: "Topping the battery back up to \(range.upper)%, then it will run straight off the adapter again.")
        case .fullCharge:
            String(localized: "One-time full charge. Kombucha goes back to your \(range.lower)–\(range.upper)% range at 100%, or as soon as you unplug.")
        case .protectionOff:
            String(localized: "Charging all the way to 100%. The battery sits at full voltage while plugged in.")
        case .onBattery:
            String(localized: "Running on the battery. Protection resumes when you plug the adapter back in.")
        case .heatPaused:
            String(localized: "The battery is at \(Int(HeatPolicy.pauseCelsius)) °C or more, so Kombucha holds the charge. It continues at \(Int(HeatPolicy.resumeCelsius)) °C or less.")
        case .discharging:
            String(localized: "The adapter stays connected but is switched off until the battery reaches \(range.upper)%. Kombucha switches it back on then, before your Mac sleeps, or when you quit.")
        }
    }

    // MARK: Write path

    static func heading(_ path: WritePath) -> String {
        switch path {
        case .ready: String(localized: "Running — the charge limit is being held")
        case .notFound: String(localized: "Kombucha has no helper yet")
        case .notRegistered: String(localized: "The helper was removed")
        case .requiresApproval: String(localized: "macOS is waiting for your approval")
        case .unknown: String(localized: "macOS answered something this build does not know")
        case .unreachable: String(localized: "The helper stopped answering")
        }
    }

    static func reason(_ path: WritePath) -> String? {
        switch path {
        case .ready: nil
        case .notFound:
            String(localized: "Holding a charge limit needs a small helper running as root. Install it once — macOS will ask you to allow it, and nothing else changes.")
        case .notRegistered:
            String(localized: "Nothing is holding the charge limit, so this Mac is charging the way it did before Kombucha. Installing the helper again puts the limit back.")
        case .requiresApproval:
            String(localized: "The helper is installed and macOS will not start it until you allow it under Login Items & Extensions. Kombucha cannot grant that for you.")
        case .unknown:
            String(localized: "Rather than guess which state this resembles, Kombucha will not claim your battery is protected. Login Items & Extensions shows what macOS has on record.")
        case .unreachable:
            String(localized: "macOS says the helper is installed and allowed, and nothing answers it — so the charge limit is not being held. Kombucha has already tried to start it again; this tries once more.")
        }
    }

    static func action(_ path: WritePath) -> String {
        switch path {
        case .ready, .notRegistered: String(localized: "Reinstall helper")
        case .notFound: String(localized: "Install helper")
        case .requiresApproval, .unknown: String(localized: "Open Login Items")
        case .unreachable: String(localized: "Start helper again")
        }
    }

    // MARK: Unsupported Mac and external battery manager

    static var unsupportedHeading: String { String(localized: "This Mac isn't supported") }
    static var unsupportedNote: String { String(localized: "Kombucha will not change charging on this Mac.") }

    /// `.supported` has no reason; it never reaches an unsupported view.
    static func unsupportedReason(_ verdict: SupportVerdict) -> String {
        switch verdict {
        case .supported: ""
        case .noSMCService: String(localized: "This Mac publishes no SMC service — a virtual machine has no battery to protect.")
        case .noBattery: String(localized: "This Mac has no battery to protect.")
        case .chargeKeyMissing: String(localized: "This Mac or this macOS version has no charge-inhibit key, so charging cannot be held at a threshold.")
        case .smcUnusable: String(localized: "The SMC is here but would not answer, so charging cannot be held safely.")
        }
    }

    static func externalManagerHeading(_ manager: ExternalBatteryManager) -> String {
        String(localized: "\(manager.displayName) is running")
    }

    static func externalManagerReason(_ manager: ExternalBatteryManager) -> String {
        let name = manager.displayName
        return String(localized: "Two apps writing the same charge limit have no arbiter — whichever wrote last wins, and neither can tell you which. Kombucha has let go of the charger and will not touch it while \(name) is running. Quit it and the controls come back, with no restart.")
    }

    // MARK: Failures

    static func failure(_ failure: ActionFailure) -> String {
        switch failure {
        case .chargerNotReached: String(localized: "That did not reach the charger, so nothing was changed.")
        case .noAnswer: String(localized: "Kombucha did not hear back from the charger. Open the panel again to see where things stand.")
        case .adapterRequired: String(localized: "Plug in the adapter to charge to 100%.")
        case .helperNotInstalled: String(localized: "macOS did not install the helper, so nothing is holding the charge limit.")
        case .helperNotRemoved: String(localized: "macOS did not remove the helper, so it is still installed and running.")
        }
    }

    // MARK: Panel controls and footer

    static var protectionSwitch: String { String(localized: "Battery Protection") }
    static var stopSlider: String { String(localized: "Stop charging at") }
    static var resumeSlider: String { String(localized: "Resume charging at") }
    static var fullChargeStart: String { String(localized: "Charge to 100% Once") }
    static var fullChargeStop: String { String(localized: "Stop the full charge") }
    static func dischargeStart(_ upper: Int) -> String { String(localized: "Discharge to \(upper)%") }
    static var dischargeStop: String { String(localized: "Stop Discharging") }
    static var firstReading: String { String(localized: "—") }
    static var footerSettings: String { String(localized: "Settings…") }
    static var footerQuit: String { String(localized: "Quit Kombucha") }

    static func percent(_ value: Int) -> String { String(localized: "\(value)%") }
    static func sliderAccessibilityValue(_ value: Int) -> String { String(localized: "\(value) percent") }

    // MARK: Settings — Helper

    static var helperTab: String { String(localized: "Helper") }
    static var helperSection: String { String(localized: "Charge Helper") }
    static var checking: String { String(localized: "Checking…") }
    static var removeHelper: String { String(localized: "Remove helper") }
    static var removeNote: String {
        String(localized: "Removing the helper hands the charger back to macOS. The charge limit stops until it is installed again.")
    }

    // MARK: Settings — Battery

    static var batteryTab: String { String(localized: "Battery") }
    static var batterySection: String { String(localized: "Battery Health") }
    static var cycleCount: String { String(localized: "Cycle Count") }
    static var maximumCapacity: String { String(localized: "Maximum Capacity") }
    static var conditionLabel: String { String(localized: "Condition") }
    static var temperatureLabel: String { String(localized: "Temperature") }
    static var voltageLabel: String { String(localized: "Voltage") }
    static var reading: String { String(localized: "Reading…") }
    static var unavailable: String { String(localized: "This Mac published no battery reading.") }
    static var powerSection: String { String(localized: "Power") }
    static var systemRow: String { String(localized: "System") }
    static var adapterRow: String { String(localized: "Adapter") }
    static var adapterFallsShort: String { String(localized: "The adapter can't keep up, so the battery covers the rest.") }
    static var appsSection: String { String(localized: "Using the most energy") }
    static var measuring: String { String(localized: "Measuring…") }
    static var noApps: String { String(localized: "Nothing is using noticeable power.") }
    static var appsFooter: String { String(localized: "Apps you run. System processes are not shown.") }
    static var batteryRestLine: String {
        String(localized: "Between your Stop and Resume levels the battery rests: your Mac runs straight from the adapter and no current flows through the cell.")
    }

    static func watts(_ watts: Double?, locale: Locale = .current) -> String {
        guard let watts else { return firstReading }
        let value = watts.formatted(.number.precision(.fractionLength(1)).locale(locale))
        return String(localized: "\(value) W")
    }

    static func condition(_ condition: BatteryHealth.Condition) -> String {
        switch condition {
        case .normal: String(localized: "Normal")
        case .serviceRecommended: String(localized: "Service recommended")
        }
    }

    static func temperature(_ celsius: Double, locale: Locale = .current) -> String {
        let value = celsius.formatted(.number.precision(.fractionLength(1)).locale(locale))
        return String(localized: "\(value) °C")
    }

    static func voltage(_ volts: Double, locale: Locale = .current) -> String {
        let value = volts.formatted(.number.precision(.fractionLength(2)).locale(locale))
        return String(localized: "\(value) V")
    }

    // MARK: Settings — History

    static var historyTab: String { String(localized: "History") }
    static var rangeLabel: String { String(localized: "Time range") }
    static var rangeWeek: String { String(localized: "7 days") }
    static var rangeMonth: String { String(localized: "30 days") }
    static var levelSection: String { String(localized: "Charge level") }
    static var legendCharging: String { String(localized: "Charging") }
    static var legendResting: String { String(localized: "Battery Rest") }
    static var capacityTooFew: String { String(localized: "Not enough days recorded yet.") }
    static var historyEmpty: String {
        String(localized: "No history yet. Kombucha records the battery while it runs.")
    }
    static var historyFooter: String { String(localized: "Kept on this Mac for 30 days. It never leaves it.") }

    static var legendOnBattery: String { String(localized: "On battery") }
    static var legendNoData: String { String(localized: "No data") }
    static var historyHint: String { String(localized: "Hover or drag for details.") }
    static var historyRestLine: String {
        String(localized: "Battery Rest: your Mac runs straight from the adapter and no current flows through the cell.")
    }
    static var historyAwakeNote: String { String(localized: "Kombucha records while your Mac is awake.") }

    static func currentLimit(_ range: Thresholds) -> String {
        String(localized: "Current limit: \(range.lower)–\(range.upper)%")
    }

    static func historyNothingRecorded(days: Int) -> String {
        String(localized: "Nothing recorded in the last \(days) days")
    }

    static func historySummary(restedPercent: Int, recorded: TimeInterval) -> String {
        String(localized: "Battery Rest \(percent(restedPercent)) of \(duration(recorded)) recorded")
    }

    /// At most two units, the larger first: "6 d 16 h", "3 h 30 min", "15 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 0)
        let days = minutes / 1_440
        let hours = minutes % 1_440 / 60
        let rest = minutes % 60
        func d(_ value: Int) -> String { String(localized: "\(value) d") }
        func h(_ value: Int) -> String { String(localized: "\(value) h") }
        func m(_ value: Int) -> String { String(localized: "\(value) min") }
        if days > 0 { return hours > 0 ? "\(d(days)) \(h(hours))" : d(days) }
        if hours > 0 { return rest > 0 ? "\(h(hours)) \(m(rest))" : h(hours) }
        return m(rest)
    }

    static func laneName(_ lane: HistoryLane) -> String {
        switch lane {
        case .charging: legendCharging
        case .resting: legendResting
        case .onBattery: legendOnBattery
        }
    }

    static func peakTemperature(_ celsius: Double, locale: Locale = .current) -> String {
        String(localized: "Peak \(temperature(celsius, locale: locale))")
    }

    /// The pointer row: `time · level · states · Peak`, or `time · No data`.
    static func historyDetail(_ detail: HistoryDetail, in zone: TimeZone = .current,
                              locale: Locale = .current) -> String {
        var parts = [timestamp(detail.start, in: zone)]
        guard let level = detail.level else { return (parts + [legendNoData]).joined(separator: " · ") }
        parts.append(percent(level))
        if !detail.lanes.isEmpty { parts.append(detail.lanes.map(laneName).joined(separator: ", ")) }
        if let peak = detail.peakTemperatureCelsius { parts.append(peakTemperature(peak, locale: locale)) }
        return parts.joined(separator: " · ")
    }

    /// Not localized text: the house format for a moment is `yyyy-MM-dd HH:mm`.
    static func timestamp(_ date: Date, in zone: TimeZone = .current) -> String {
        formatted(date, pattern: "yyyy-MM-dd HH:mm", in: zone)
    }

    static func axisDay(_ date: Date, in zone: TimeZone = .current) -> String {
        formatted(date, pattern: "MM-dd", in: zone)
    }

    /// Axis label for a week: "Fri 15". Not in the catalog: the system names the day.
    static func axisWeekdayAndDay(_ date: Date, in zone: TimeZone = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: zone)
        return "\(date.formatted(style.weekday(.abbreviated))) \(date.formatted(style.day()))"
    }

    /// Axis label for a month: "Jan 15".
    static func axisMonthAndDay(_ date: Date, in zone: TimeZone = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: zone)
        return "\(date.formatted(style.month(.abbreviated))) \(date.formatted(style.day()))"
    }

    private static func formatted(_ date: Date, pattern: String, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: Settings — General

    static var generalTab: String { String(localized: "General") }
    static var launchAtLogin: String { String(localized: "Launch at Login") }
    static var launchAtLoginRefused: String {
        String(localized: "macOS will not confirm Kombucha as a login item while something for it is switched off under Login Items & Extensions. Turning it back on is something only you can do, there.")
    }
    static var openLoginItems: String { String(localized: "Open Login Items") }
    static var showPercentage: String { String(localized: "Show percentage in menu bar") }
    static var notificationsSection: String { String(localized: "Notifications") }
    static var notifyFullCharge: String { String(localized: "When a full charge finishes") }
    static var notifyProtectionChanges: String { String(localized: "When protection stops or resumes") }
    static var notifyBatteryAttention: String { String(localized: "When the battery needs attention") }
    static var notificationsNotAsked: String {
        String(localized: "Kombucha has not asked for permission to notify yet.")
    }
    static var allowNotifications: String { String(localized: "Allow Notifications") }
    static var notificationsDenied: String {
        String(localized: "Notifications for Kombucha are turned off in System Settings.")
    }
    static var openNotificationSettings: String { String(localized: "Open Notification Settings") }

    // MARK: Welcome window

    static var welcomeTitle: String { String(localized: "Welcome to Kombucha") }
    static var welcomeMenuBarTitle: String { String(localized: "Kombucha lives in the menu bar") }
    static var welcomeMenuBarBody: String {
        String(localized: "Click its battery symbol at the top of the screen to see the charge level and set the limit.")
    }
    static var welcomeHelperTitle: String { String(localized: "Install the charge helper") }
    static var welcomeLaunchBody: String {
        String(localized: "Kombucha protects the battery only while it is running.")
    }
    static var welcomeDone: String { String(localized: "Done") }
    static var welcomeClose: String { String(localized: "Close") }
    static var showWelcomeWindow: String { String(localized: "Show Welcome Window") }

    // MARK: Notifications

    static func notificationTitle(_ post: NotificationPost) -> String {
        switch post {
        case .fullyCharged: String(localized: "Fully charged")
        case .protectionStopped: String(localized: "Battery protection stopped")
        case .protectionResumed: String(localized: "Battery protection resumed")
        }
    }

    static func notificationBody(_ post: NotificationPost) -> String {
        switch post {
        case .fullyCharged(let range):
            String(localized: "Kombucha is back to your \(range.lower)–\(range.upper)% range.")
        case .protectionStopped(let state):
            // The gate's own heading, so the notification and the panel say the same thing.
            header(for: state).title ?? heading(.unknown)
        case .protectionResumed:
            String(localized: "Kombucha is holding your charge limit again.")
        }
    }

    static func alertTitle(_ alert: BatteryAlert) -> String {
        switch alert {
        case .healthDropped: String(localized: "Battery capacity dropped")
        case .overheating: String(localized: "Battery is hot")
        case .limitNotHeld: String(localized: "Charge limit is not holding")
        }
    }

    static func alertBody(_ alert: BatteryAlert, locale: Locale = .current) -> String {
        switch alert {
        case .healthDropped(let from, let to):
            String(localized: "Maximum capacity is now \(to)%, down from \(from)%.")
        case .overheating(let limit):
            String(localized: "The battery has stayed at \(temperature(limit, locale: locale)) or above for 5 minutes.")
        case .limitNotHeld(let range):
            String(localized: "The battery is still charging above your \(range.upper)% limit.")
        }
    }

    // MARK: System Settings doors

    /// The panes Task 0 of plan 5 confirmed on macOS 15.7.4.
    enum SystemSettings {
        static let loginItems = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        static let notifications = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
    }

    // MARK: Settings — About

    static var aboutTab: String { String(localized: "About") }
    static var tagline: String { String(localized: "Battery charge limiting for macOS") }
    static var reportIssue: String { String(localized: "Report an Issue") }
    static var documentation: String { String(localized: "Documentation") }
    static var sourceCode: String { String(localized: "Source Code") }
    static var license: String { String(localized: "License: MIT License") }

    static func version(_ version: String) -> String {
        String(localized: "Version \(version)")
    }

    // MARK: Settings — Language

    static var languageRow: String { String(localized: "Language") }
    static var languageSystemDefault: String { String(localized: "System default") }
    static var languageRestartNote: String { String(localized: "Kombucha uses the new language after it restarts.") }
    static var restartKombucha: String { String(localized: "Restart Kombucha") }

    // MARK: Updates

    static var updatesSection: String { String(localized: "Updates") }
    static var updateCheckDaily: String { String(localized: "Check for updates daily") }
    static var updateCheckDailyNote: String {
        String(localized: "Kombucha contacts GitHub once a day to look for a new release. Nothing else is sent.")
    }
    static var checkForUpdates: String { String(localized: "Check for Updates") }
    static var updateUpToDate: String { String(localized: "Kombucha is up to date.") }
    static func updateAvailable(_ version: AppVersion) -> String {
        String(localized: "Kombucha \(version.description) is available.")
    }
    static var viewRelease: String { String(localized: "View Release") }
    static var updateFailed: String { String(localized: "Couldn't check for updates.") }
    static var updateHomebrewHint: String {
        String(localized: "Installed with Homebrew? Run brew upgrade --cask kombucha.")
    }
    static func updateNotificationTitle(_ version: AppVersion) -> String {
        String(localized: "Kombucha \(version.description) is available")
    }
    static var updateNotificationBody: String { String(localized: "Open the release page to download it.") }

    // MARK: Intents

    static var intentNotReady: String { String(localized: "Kombucha is still starting. Try again in a moment.") }

    static func statusDialog(_ status: BatteryStatus) -> String {
        String(localized: "Battery at \(status.level)%. \(status.line)")
    }
}
