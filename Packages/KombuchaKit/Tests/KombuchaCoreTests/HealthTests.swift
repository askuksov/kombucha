import KombuchaCore
import Testing

private func values(cycleCount: Int? = 142,
                    designCapacity: Int? = 8579,
                    nominalChargeCapacity: Int? = 7964,
                    permanentFailureStatus: Int? = 0,
                    temperature: Int? = 3012,
                    voltage: Int? = 12634) -> BatteryRegistryValues {
    BatteryRegistryValues(cycleCount: cycleCount,
                          designCapacity: designCapacity,
                          nominalChargeCapacity: nominalChargeCapacity,
                          permanentFailureStatus: permanentFailureStatus,
                          temperature: temperature,
                          voltage: voltage)
}

@Test func aCompleteReadingIsDerived() throws {
    let health = try #require(BatteryHealth.derive(values()))
    #expect(health.cycleCount == 142)
    #expect(health.maximumCapacityPercent == 92)
    #expect(health.condition == .normal)
    #expect(health.temperatureCelsius == 30.12)
    #expect(health.voltageVolts == 12.634)
}

@Test(arguments: [(8579, 7964, 92), (8579, 8579, 100), (8579, 8578, 99), (100, 1, 1), (100, 0, 0)])
func theCapacityPercentFloors(designCapacity: Int, nominal: Int, expected: Int) throws {
    let health = try #require(BatteryHealth.derive(values(designCapacity: designCapacity, nominalChargeCapacity: nominal)))
    #expect(health.maximumCapacityPercent == expected)
}

@Test func aPermanentFailureRecommendsService() throws {
    let normal = try #require(BatteryHealth.derive(values(permanentFailureStatus: 0)))
    #expect(normal.condition == .normal)
    let failed = try #require(BatteryHealth.derive(values(permanentFailureStatus: 1)))
    #expect(failed.condition == .serviceRecommended)
}

@Test func aMissingKeyGivesNoReading() {
    #expect(BatteryHealth.derive(values(cycleCount: nil)) == nil)
    #expect(BatteryHealth.derive(values(designCapacity: nil)) == nil)
    #expect(BatteryHealth.derive(values(nominalChargeCapacity: nil)) == nil)
    #expect(BatteryHealth.derive(values(permanentFailureStatus: nil)) == nil)
    #expect(BatteryHealth.derive(values(temperature: nil)) == nil)
    #expect(BatteryHealth.derive(values(voltage: nil)) == nil)
    #expect(BatteryHealth.derive(BatteryRegistryValues()) == nil)
}

@Test func aNegativeValueGivesNoReading() {
    #expect(BatteryHealth.derive(values(cycleCount: -1)) == nil)
    #expect(BatteryHealth.derive(values(designCapacity: -8579)) == nil)
    #expect(BatteryHealth.derive(values(nominalChargeCapacity: -1)) == nil)
    #expect(BatteryHealth.derive(values(permanentFailureStatus: -1)) == nil)
    #expect(BatteryHealth.derive(values(temperature: -1)) == nil)
    #expect(BatteryHealth.derive(values(voltage: -1)) == nil)
}

@Test func aZeroDesignCapacityGivesNoReadingRatherThanZeroPercent() {
    #expect(BatteryHealth.derive(values(designCapacity: 0)) == nil)
}

@Test func theUnitsAreScaled() throws {
    let health = try #require(BatteryHealth.derive(values(temperature: 0, voltage: 0)))
    #expect(health.temperatureCelsius == 0)
    #expect(health.voltageVolts == 0)
    let warm = try #require(BatteryHealth.derive(values(temperature: 4150, voltage: 8500)))
    #expect(warm.temperatureCelsius == 41.5)
    #expect(warm.voltageVolts == 8.5)
}
