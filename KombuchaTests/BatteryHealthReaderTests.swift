import KombuchaCore
import Testing
@testable import Kombucha

@Test func theRegistryKeysGiveTheHealthSystemSettingsShows() {
    // F-HLT-1, with the two keys that are not health left in.
    let properties: [String: Any] = ["CycleCount": 297, "DesignCapacity": 8579, "NominalChargeCapacity": 7964,
                                     "AppleRawMaxCapacity": 7720, "MaxCapacity": 100,
                                     "PermanentFailureStatus": 0, "Temperature": 3013, "Voltage": 12651]
    let health = BatteryHealth.derive(BatteryHealthReader.values(from: properties))
    #expect(health?.maximumCapacityPercent == 92)
    #expect(health?.cycleCount == 297)
    #expect(health?.condition == .normal)
}

@Test func aValueOfAnotherTypeCountsAsMissing() {
    let values = BatteryHealthReader.values(from: ["CycleCount": "297", "DesignCapacity": 8579])
    #expect(values.cycleCount == nil)
    #expect(values.designCapacity == 8579)
}

@Test func theTemperatureIsHundredthsOfADegree() {
    #expect(BatteryHealthReader.temperatureCelsius(from: ["Temperature": 3062]) == 30.62)
}

@Test func aMissingOrUselessTemperatureIsNil() {
    #expect(BatteryHealthReader.temperatureCelsius(from: [:]) == nil)
    #expect(BatteryHealthReader.temperatureCelsius(from: ["Temperature": 0]) == nil)
    #expect(BatteryHealthReader.temperatureCelsius(from: ["Temperature": "hot"]) == nil)
}

@Test func aConnectedAdapterHasWatts() {
    #expect(BatteryHealthReader.adapterPresent(from: ["AdapterDetails": ["Watts": 140, "FamilyCode": 1]]) == true)
}

@Test func aPulledCableLeavesOnlyTheFamilyCode() {
    #expect(BatteryHealthReader.adapterPresent(from: ["AdapterDetails": ["FamilyCode": 0]]) == false)
    #expect(BatteryHealthReader.adapterPresent(from: ["AdapterDetails": ["Watts": 0]]) == false)
}

@Test func withoutAdapterDetailsTheCableIsUnknown() {
    #expect(BatteryHealthReader.adapterPresent(from: [:]) == nil)
    #expect(BatteryHealthReader.adapterPresent(from: ["AdapterDetails": "140 W"]) == nil)
}
