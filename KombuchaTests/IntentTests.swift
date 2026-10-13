import AppIntents
import KombuchaCore
import Testing
@testable import Kombucha

private func text(_ resource: LocalizedStringResource) -> String { String(localized: resource) }

@Test func getBatteryStatusAnswersWithTheEntityAndTheDialog() async throws {
    let gateway = FakeGateway()
    let (entity, dialog) = try await GetBatteryStatusIntent.run(gateway)
    #expect(gateway.calls == ["status"])
    #expect(entity.level == 78)
    #expect(entity.mode == .protected)
    #expect(entity.stopAt == 80)
    #expect(entity.resumeAt == 75)
    #expect(entity.protection == true)
    #expect(entity.holdingLimit == true)
    #expect(dialog == "Battery at 78%. Protected: Battery resting 75% – 80%")
}

@Test func getBatteryStatusPassesTheGatewayErrorOn() async {
    let gateway = FakeGateway()
    gateway.fail(with: .notReady)
    await #expect(throws: GatewayError.notReady) { _ = try await GetBatteryStatusIntent.run(gateway) }
}

@Test(arguments: [
    (Mode.protected, BatteryModeOption.protected, "Protected"),
    (.charging, .charging, "Charging"),
    (.fullCharge, .fullCharge, "Charging to 100%"),
    (.protectionOff, .protectionOff, "Protection off"),
    (.onBattery, .onBattery, "On battery"),
    (.heatPaused, .heatPaused, "Charging paused"),
    (.discharging, .discharging, "Discharging"),
])
func everyModeHasAnOptionAndAName(mode: Mode, option: BatteryModeOption, name: String) throws {
    #expect(BatteryModeOption(mode) == option)
    let representation = try #require(BatteryModeOption.caseDisplayRepresentations[option])
    #expect(text(representation.title) == name)
}

@Test func theValuesUseTheSpecificationsWords() {
    #expect(text(BatteryStatusEntity.typeDisplayRepresentation.name) == "Battery Status")
    #expect(text(ChargeLimitEntity.typeDisplayRepresentation.name) == "Charge Limit")
    #expect(text(BatteryModeOption.typeDisplayRepresentation.name) == "Mode")
    let status = BatteryStatusEntity(BatteryStatus(level: 64, mode: .charging, thresholds: .standard,
                                                   protection: true, holdingLimit: true, line: ""))
    #expect(text(status.displayRepresentation.title) == "Battery at 64%")
    let limit = ChargeLimitEntity(.normalized(lower: 55, upper: 60))
    #expect(limit.stopAt == 60)
    #expect(limit.resumeAt == 55)
    #expect(text(limit.displayRepresentation.title) == "55–60%")
    #expect(text(GetBatteryStatusIntent.title) == "Get Battery Status")
}

@Test func everyIntentValueStringIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["Get Battery Status", "Battery Status", "Battery at %lld%%", "Charge Limit", "%lld–%lld%%",
                "Level", "Mode", "Stop charging at", "Resume charging at", "Battery Protection",
                "Holding the limit", "Protected", "Charging", "Charging to 100%", "Protection off",
                "On battery", "Charging paused"] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}

@Test func fullChargeStartsForTrueAndStopsForFalse() async throws {
    let gateway = FakeGateway()
    try await SetFullChargeIntent.apply(true, through: gateway)
    try await SetFullChargeIntent.apply(false, through: gateway)
    #expect(gateway.calls == ["start", "stop"])
}

@Test func fullChargeIsHiddenFromShortcuts() {
    #expect(SetFullChargeIntent.isDiscoverable == false)
    #expect(GetBatteryStatusIntent.isDiscoverable == true)
}

@Test func everyIntentHasTheSpecificationsTitle() {
    #expect(text(GetBatteryStatusIntent.title) == "Get Battery Status")
    #expect(text(SetBatteryProtectionIntent.title) == "Set Battery Protection")
    #expect(text(SetChargeLimitIntent.title) == "Set Charge Limit")
    #expect(text(StartFullChargeIntent.title) == "Start Full Charge")
    #expect(text(StopFullChargeIntent.title) == "Stop Full Charge")
    #expect(text(SetFullChargeIntent.title) == "Full Charge")
}

@Test func theAppShortcutsAreStartFullChargeAndBatteryStatus() {
    let shortcuts = KombuchaShortcuts.appShortcuts
    #expect(shortcuts.count == 2)
}

@Test func everyIntentTitleIsInTheCatalog() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Kombucha/Resources/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let strings = try #require(catalog?["strings"] as? [String: Any])
    for key in ["Set Battery Protection", "Set Charge Limit", "Start Full Charge", "Stop Full Charge", "Full Charge"] {
        #expect(strings[key] != nil, "missing from the catalog: \(key)")
    }
}
