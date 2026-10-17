import Foundation
import KombuchaCore
import Testing
@testable import Kombucha

private let range = Thresholds.standard

private func snapshot(level: Double = 78, onAC: Bool = true, charging: Bool = false, protection: Bool = true,
                      fullCharge: Bool = false) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: onAC, charging: charging, thresholds: range, protection: protection,
                   fullChargeActive: fullCharge, writePath: .ready)
}

@Test(arguments: [
    (Mode.protected, "Protected: Battery resting 75% – 80%",
     "Your Mac is running straight from the adapter — nothing is wrong with the charger. The battery rests until it reaches 75%."),
    (.charging, "Charging: Topping up to 80%",
     "Topping the battery back up to 80%, then it will run straight off the adapter again."),
    (.fullCharge, "Charging to 100%: reverts on unplug",
     "One-time full charge. Kombucha goes back to your 75–80% range at 100%, or as soon as you unplug."),
    (.protectionOff, "Protection off: charging to 100%",
     "Charging all the way to 100%. The battery sits at full voltage while plugged in."),
    (.onBattery, "On battery: protection resumes on AC",
     "Running on the battery. Protection resumes when you plug the adapter back in."),
    (.heatPaused, "Charging paused: battery is hot",
     "The battery is at 40 °C or more, so Kombucha holds the charge. It continues at 37 °C or less."),
    (.discharging, "Discharging: running on battery down to 80%",
     "The adapter stays connected but is switched off until the battery reaches 80%. Kombucha switches it back on then, before your Mac sleeps, or when you quit."),
])
func everyModeHasItsStatusLineAndExplanation(mode: Mode, status: String, explanation: String) {
    #expect(Copy.statusLine(mode, range) == status)
    #expect(Copy.explanation(mode, range) == explanation)
}

@Test(arguments: [
    (WritePath.notFound, "Kombucha has no helper yet", "Install helper"),
    (.notRegistered, "The helper was removed", "Reinstall helper"),
    (.requiresApproval, "macOS is waiting for your approval", "Open Login Items"),
    (.unknown, "macOS answered something this build does not know", "Open Login Items"),
    (.unreachable, "The helper stopped answering", "Start helper again"),
    (.ready, "Running — the charge limit is being held", "Reinstall helper"),
])
func everyWritePathHasItsHeadingAndAction(path: WritePath, heading: String, action: String) {
    #expect(Copy.heading(path) == heading)
    #expect(Copy.action(path) == action)
    #expect((Copy.reason(path) == nil) == (path == .ready))
}

@Test func aReasonIsCopiedWhole() {
    #expect(Copy.reason(.requiresApproval) == "The helper is installed and macOS will not start it until you allow it under Login Items & Extensions. Kombucha cannot grant that for you.")
}

@Test(arguments: [
    (SupportVerdict.noSMCService, "This Mac publishes no SMC service — a virtual machine has no battery to protect."),
    (.noBattery, "This Mac has no battery to protect."),
    (.chargeKeyMissing, "This Mac or this macOS version has no charge-inhibit key, so charging cannot be held at a threshold."),
    (.smcUnusable, "The SMC is here but would not answer, so charging cannot be held safely."),
])
func everyUnsupportedVerdictHasItsReason(verdict: SupportVerdict, reason: String) {
    #expect(Copy.unsupportedReason(verdict) == reason)
}

@Test(arguments: [
    (ActionFailure.chargerNotReached, "That did not reach the charger, so nothing was changed."),
    (.noAnswer, "Kombucha did not hear back from the charger. Open the panel again to see where things stand."),
    (.adapterRequired, "Plug in the adapter to charge to 100%."),
    (.helperNotInstalled, "macOS did not install the helper, so nothing is holding the charge limit."),
    (.helperNotRemoved, "macOS did not remove the helper, so it is still installed and running."),
])
func everyFailureHasItsSentence(failure: ActionFailure, sentence: String) {
    #expect(Copy.failure(failure) == sentence)
}

@Test func anExternalBatteryManagerIsNamed() {
    #expect(Copy.externalManagerHeading(.alDente) == "AlDente is running")
    let reason = Copy.externalManagerReason(.alDente)
    #expect(reason.hasPrefix("Two apps writing the same charge limit have no arbiter"))
    #expect(reason.contains("will not touch it while AlDente is running."))
}

@Test func theHeaderFollowsThePanelState() {
    #expect(Copy.header(for: .firstReading) == PanelHeader(level: "—", title: nil, detail: nil, note: nil))
    #expect(Copy.header(for: .unsupported(.noBattery)) == PanelHeader(
        level: nil, title: "This Mac isn't supported", detail: "This Mac has no battery to protect.",
        note: "Kombucha will not change charging on this Mac."))
    let controls = Copy.header(for: .controls(snapshot()))
    #expect(controls.level == "78%")
    #expect(controls.title == "Protected: Battery resting 75% – 80%")
    let gate = Copy.header(for: .writePathBlocked(.notRegistered, level: 78))
    #expect(gate.level == "78%")
    #expect(gate.title == "The helper was removed")
    #expect(Copy.header(for: .externalBatteryManager(.battOpt, level: 78)).title == "BattOpt is running")
}

@Test func slidersReadAsPercent() {
    #expect(Copy.percent(80) == "80%")
    #expect(Copy.sliderAccessibilityValue(80) == "80 percent")
}

@Test func theMenuBarLabelReadsLevelAndStatus() {
    #expect(Copy.menuBarAccessibilityLabel(.controls(snapshot()))
        == "Kombucha, 78%, Protected: Battery resting 75% – 80%")
    #expect(Copy.menuBarAccessibilityLabel(.writePathBlocked(.notRegistered, level: 78))
        == "Kombucha, 78%, The helper was removed")
    #expect(Copy.menuBarAccessibilityLabel(.unsupported(.noBattery)) == "Kombucha, This Mac isn't supported")
    #expect(Copy.menuBarAccessibilityLabel(.firstReading) == "Kombucha")
}

@Test func healthValuesKeepTheirDecimals() {
    let posix = Locale(identifier: "en_US_POSIX")
    #expect(Copy.temperature(30.13, locale: posix) == "30.1 °C")
    #expect(Copy.voltage(12.651, locale: posix) == "12.65 V")
    #expect(Copy.condition(.normal) == "Normal")
    #expect(Copy.condition(.serviceRecommended) == "Service recommended")
}

@Test func theVersionLineNamesTheVersionOnly() {
    #expect(Copy.version("1.0.0") == "Version 1.0.0")
}

@Test func theGeneralTabNamesEveryRow() {
    #expect(Copy.generalTab == "General")
    #expect(Copy.launchAtLogin == "Launch at Login")
    #expect(Copy.launchAtLoginRefused == "macOS will not confirm Kombucha as a login item while something for it is switched off under Login Items & Extensions. Turning it back on is something only you can do, there.")
    #expect(Copy.openLoginItems == "Open Login Items")
    #expect(Copy.showPercentage == "Show percentage in menu bar")
    #expect(Copy.notificationsSection == "Notifications")
    #expect(Copy.notifyFullCharge == "When a full charge finishes")
    #expect(Copy.notifyProtectionChanges == "When protection stops or resumes")
    #expect(Copy.notificationsNotAsked == "Kombucha has not asked for permission to notify yet.")
    #expect(Copy.allowNotifications == "Allow Notifications")
    #expect(Copy.notificationsDenied == "Notifications for Kombucha are turned off in System Settings.")
    #expect(Copy.openNotificationSettings == "Open Notification Settings")
}

@Test func theWelcomeWindowNamesEveryStep() {
    #expect(Copy.welcomeTitle == "Welcome to Kombucha")
    #expect(Copy.welcomeMenuBarTitle == "Kombucha lives in the menu bar")
    #expect(Copy.welcomeMenuBarBody
        == "Click its battery symbol at the top of the screen to see the charge level and set the limit.")
    #expect(Copy.welcomeHelperTitle == "Install the charge helper")
    #expect(Copy.welcomeLaunchBody == "Kombucha protects the battery only while it is running.")
    #expect(Copy.welcomeDone == "Done")
    #expect(Copy.welcomeClose == "Close")
    #expect(Copy.showWelcomeWindow == "Show Welcome Window")
}

@Test func everyNotificationHasATitleAndABody() {
    #expect(Copy.notificationTitle(.fullyCharged(range)) == "Fully charged")
    #expect(Copy.notificationBody(.fullyCharged(range)) == "Kombucha is back to your 75–80% range.")
    let blocked = PanelState.writePathBlocked(.notRegistered, level: 78)
    #expect(Copy.notificationTitle(.protectionStopped(blocked)) == "Battery protection stopped")
    #expect(Copy.notificationBody(.protectionStopped(blocked)) == Copy.heading(.notRegistered))
    let manager = PanelState.externalBatteryManager(.alDente, level: 78)
    #expect(Copy.notificationBody(.protectionStopped(manager)) == Copy.externalManagerHeading(.alDente))
    #expect(Copy.notificationTitle(.protectionResumed) == "Battery protection resumed")
    #expect(Copy.notificationBody(.protectionResumed) == "Kombucha is holding your charge limit again.")
}

@Test func theCatalogIsCompiledIntoTheApp() {
    // The test host is the app, so its main bundle carries the compiled catalog.
    let missing = "missing-from-the-catalog"
    #expect(Bundle.main.localizedString(forKey: "Battery Protection", value: missing, table: nil) == "Battery Protection")
}

@Test func theCatalogHoldsNoStaleString() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: [String: Any]])
    #expect(strings.count >= 60)
    let stale = strings.filter { $0.value["extractionState"] as? String == "stale" }.map(\.key)
    #expect(stale.isEmpty, "stale: \(stale)")
}

@Test func wattsKeepOneDecimalAndAMissingValueIsADash() {
    let posix = Locale(identifier: "en_US_POSIX")
    #expect(Copy.watts(5.282, locale: posix) == "5.3 W")
    #expect(Copy.watts(0, locale: posix) == "0.0 W")
    #expect(Copy.watts(nil, locale: posix) == "—")
}

@Test func theBatteryTabNamesItsPowerRows() {
    #expect(Copy.powerSection == "Power")
    #expect(Copy.systemRow == "System")
    #expect(Copy.adapterRow == "Adapter")
    #expect(Copy.appsSection == "Using the most energy")
    #expect(Copy.measuring == "Measuring…")
    #expect(Copy.noApps == "Nothing is using noticeable power.")
    #expect(Copy.appsFooter == "Apps you run. System processes are not shown.")
    #expect(Copy.adapterFallsShort == "The adapter can't keep up, so the battery covers the rest.")
}

@Test func batteryRestIsExplainedInTheGlossarysWords() {
    #expect(Copy.batteryRestLine == "Between your Stop and Resume levels the battery rests: your Mac runs straight from the adapter and no current flows through the cell.")
}

@Test func everyPowerStringIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["Power", "System", "Adapter", "%@ W", "Using the most energy", "Measuring…",
                "Nothing is using noticeable power.", "Apps you run. System processes are not shown.",
                Copy.batteryRestLine, Copy.adapterFallsShort] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}

@Test func theHistoryTabNamesItsParts() {
    #expect(Copy.historyTab == "History")
    #expect(Copy.rangeLabel == "Time range")
    #expect(Copy.rangeWeek == "7 days")
    #expect(Copy.rangeMonth == "30 days")
    #expect(Copy.levelSection == "Charge level")
    #expect(Copy.legendCharging == "Charging")
    #expect(Copy.legendResting == "Battery Rest")
    #expect(Copy.capacityTooFew == "Not enough days recorded yet.")
    #expect(Copy.historyEmpty == "No history yet. Kombucha records the battery while it runs.")
    #expect(Copy.historyFooter == "Kept on this Mac for 30 days. It never leaves it.")
    #expect(Copy.notifyBatteryAttention == "When the battery needs attention")
}

@Test func everyBatteryAlertHasATitleAndABody() {
    let posix = Locale(identifier: "en_US_POSIX")
    let dropped = BatteryAlert.healthDropped(from: 92, to: 91)
    #expect(Copy.alertTitle(dropped) == "Battery capacity dropped")
    #expect(Copy.alertBody(dropped) == "Maximum capacity is now 91%, down from 92%.")
    let hot = BatteryAlert.overheating(limitCelsius: 40)
    #expect(Copy.alertTitle(hot) == "Battery is hot")
    #expect(Copy.alertBody(hot, locale: posix) == "The battery has stayed at 40.0 °C or above for 5 minutes.")
    let limit = BatteryAlert.limitNotHeld(.standard)
    #expect(Copy.alertTitle(limit) == "Charge limit is not holding")
    #expect(Copy.alertBody(limit) == "The battery is still charging above your 80% limit.")
}

@Test func timesUseTheHouseFormat() {
    let utc = TimeZone(identifier: "UTC")!
    let moment = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(Copy.timestamp(moment, in: utc) == "2027-01-15 08:00")
    #expect(Copy.axisDay(moment, in: utc) == "01-15")
}

@Test func everyHistoryStringIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["History", "Time range", "7 days", "30 days", "Charge level", "Charging", "Battery Rest",
                "Not enough days recorded yet.",
                "No history yet. Kombucha records the battery while it runs.",
                "Kept on this Mac for 30 days. It never leaves it.",
                "When the battery needs attention",
                "Battery capacity dropped", "Maximum capacity is now %lld%%, down from %lld%%.",
                "Battery is hot", "The battery has stayed at %@ or above for 5 minutes.",
                "Charge limit is not holding", "The battery is still charging above your %lld%% limit.",
                "On battery", "No data", "Current limit: %lld–%lld%%", "Hover or drag for details.",
                "Battery Rest: your Mac runs straight from the adapter and no current flows through the cell.",
                "Nothing recorded in the last %lld days", "Kombucha records while your Mac is awake.",
                "Battery Rest %@ of %@ recorded", "Peak %@", "%lld d", "%lld h", "%lld min"] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}

@Test func everyHeatStringIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["Charging paused: battery is hot",
                "The battery is at %lld °C or more, so Kombucha holds the charge. It continues at %lld °C or less."] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}

@Test func theStatusDialogNamesTheLevelAndTheLine() {
    let status = BatteryStatus(level: 78, mode: .protected, thresholds: .standard, protection: true,
                               holdingLimit: true, line: Copy.statusLine(.protected, .standard))
    #expect(Copy.statusDialog(status) == "Battery at 78%. Protected: Battery resting 75% – 80%")
    #expect(Copy.intentNotReady == "Kombucha is still starting. Try again in a moment.")
}

@Test func everyIntentCopyStringIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["Kombucha is still starting. Try again in a moment.", "Battery at %lld%%. %@"] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}

@Test func theDischargeButtonsNameTheStopLevel() {
    #expect(Copy.dischargeStart(80) == "Discharge to 80%")
    #expect(Copy.dischargeStop == "Stop Discharging")
}

@Test func theMenuBarLabelSaysDischarging() {
    let discharging = ChargeSnapshot(level: 90, onAC: true, charging: false, thresholds: range, protection: true,
                                     fullChargeActive: false, writePath: .ready, dischargeActive: true)
    #expect(Copy.menuBarAccessibilityLabel(.controls(discharging))
            == "Kombucha, 90%, Discharging: running on battery down to 80%")
}

@Test func everyDischargeStringIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["Discharging: running on battery down to %lld%%",
                "The adapter stays connected but is switched off until the battery reaches %lld%%. Kombucha switches it back on then, before your Mac sleeps, or when you quit.",
                "Discharge to %lld%%",
                "Stop Discharging",
                "Discharging"] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}

@Test func theHistoryChartSpeaksInTheDesignsWords() {
    #expect(Copy.legendOnBattery == "On battery")
    #expect(Copy.legendNoData == "No data")
    #expect(Copy.historyHint == "Hover or drag for details.")
    #expect(Copy.historyRestLine == "Battery Rest: your Mac runs straight from the adapter and no current flows through the cell.")
    #expect(Copy.currentLimit(Thresholds.normalized(lower: 70, upper: 80)) == "Current limit: 70–80%")
    #expect(Copy.historyNothingRecorded(days: 7) == "Nothing recorded in the last 7 days")
    #expect(Copy.historyAwakeNote == "Kombucha records while your Mac is awake.")
}

@Test func aDurationShowsAtMostTwoUnits() {
    #expect(Copy.duration(6 * 86_400 + 16 * 3_600) == "6 d 16 h")
    #expect(Copy.duration(86_400) == "1 d")
    #expect(Copy.duration(2 * 86_400 + 5 * 60) == "2 d")
    #expect(Copy.duration(3 * 3_600 + 30 * 60) == "3 h 30 min")
    #expect(Copy.duration(3 * 3_600) == "3 h")
    #expect(Copy.duration(900) == "15 min")
    #expect(Copy.duration(0) == "0 min")
}

@Test func theSummaryNamesTheShareAndTheRecordedTime() {
    #expect(Copy.historySummary(restedPercent: 73, recorded: 6 * 86_400 + 16 * 3_600) == "Battery Rest 73% of 6 d 16 h recorded")
    #expect(Copy.historySummary(restedPercent: 100, recorded: 900) == "Battery Rest 100% of 15 min recorded")
}

@Test func theDetailRowFollowsTheDesign() {
    let utc = TimeZone(identifier: "UTC")!
    let posix = Locale(identifier: "en_US_POSIX")
    let moment = Date(timeIntervalSince1970: 1_800_000_000)
    let full = HistoryDetail(start: moment, level: 83, lanes: [.charging, .onBattery], peakTemperatureCelsius: 31.5)
    #expect(Copy.historyDetail(full, in: utc, locale: posix) == "2027-01-15 08:00 · 83% · Charging, On battery · Peak 31.5 °C")
    let bare = HistoryDetail(start: moment, level: 70, lanes: [], peakTemperatureCelsius: nil)
    #expect(Copy.historyDetail(bare, in: utc, locale: posix) == "2027-01-15 08:00 · 70%")
    let gap = HistoryDetail(start: moment, level: nil, lanes: [], peakTemperatureCelsius: nil)
    #expect(Copy.historyDetail(gap, in: utc, locale: posix) == "2027-01-15 08:00 · No data")
}

@Test func theAxisNamesTheDay() {
    let utc = TimeZone(identifier: "UTC")!
    let posix = Locale(identifier: "en_US_POSIX")
    let moment = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(Copy.axisWeekdayAndDay(moment, in: utc, locale: posix) == "Fri 15")
    #expect(Copy.axisMonthAndDay(moment, in: utc, locale: posix) == "Jan 15")
    #expect(Copy.axisDay(moment, in: utc) == "01-15")
}

@Test func theUpdateStringsAreCopiedWhole() {
    #expect(Copy.updatesSection == "Updates")
    #expect(Copy.updateCheckDaily == "Check for updates daily")
    #expect(Copy.updateCheckDailyNote == "Kombucha contacts GitHub once a day to look for a new release. Nothing else is sent.")
    #expect(Copy.checkForUpdates == "Check for Updates")
    #expect(Copy.checking == "Checking…")
    #expect(Copy.updateUpToDate == "Kombucha is up to date.")
    #expect(Copy.viewRelease == "View Release")
    #expect(Copy.updateFailed == "Couldn't check for updates.")
    #expect(Copy.updateHomebrewHint == "Installed with Homebrew? Run brew upgrade --cask kombucha.")
    #expect(Copy.updateNotificationBody == "Open the release page to download it.")
}

@Test func theUpdateSentencesNameTheVersion() {
    let version = AppVersion(0, 2, 0)
    #expect(Copy.updateAvailable(version) == "Kombucha 0.2.0 is available.")
    #expect(Copy.updateNotificationTitle(version) == "Kombucha 0.2.0 is available")
}

@Test func everyUpdateStringIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["Updates", "Check for updates daily", Copy.updateCheckDailyNote, "Check for Updates",
                "Kombucha is up to date.", "Kombucha %@ is available.", "View Release",
                "Couldn't check for updates.", Copy.updateHomebrewHint, "Kombucha %@ is available",
                Copy.updateNotificationBody] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}

@Test func theLanguageRowSpeaksPlainly() {
    #expect(Copy.languageRow == "Language")
    #expect(Copy.languageSystemDefault == "System default")
    #expect(Copy.languageRestartNote == "Kombucha uses the new language after it restarts.")
    #expect(Copy.restartKombucha == "Restart Kombucha")
}
