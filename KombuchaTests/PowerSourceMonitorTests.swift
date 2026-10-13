import KombuchaCore
import Testing
@testable import Kombucha

private func battery(current: Int? = 78,
                     maximum: Int? = 100,
                     state: String = "AC Power",
                     charging: Bool? = false) -> [String: Any] {
    var description: [String: Any] = ["Type": "InternalBattery", "Power Source State": state]
    if let current { description["Current Capacity"] = current }
    if let maximum { description["Max Capacity"] = maximum }
    if let charging { description["Is Charging"] = charging }
    return description
}

@Test func aDescriptionGivesTheLevelTheAdapterAndTheChargingFlag() {
    #expect(PowerSourceMonitor.reading(from: battery(current: 78, maximum: 100, charging: true))
            == PowerReading(level: 78, onAC: true, charging: true))
}

@Test func theLevelIsAShareOfTheMaximum() {
    #expect(PowerSourceMonitor.reading(from: battery(current: 40, maximum: 80))?.level == 50)
}

@Test func aMaximumOfZeroOrLessIsNoReading() {
    #expect(PowerSourceMonitor.reading(from: battery(maximum: 0)) == nil)
    #expect(PowerSourceMonitor.reading(from: battery(maximum: -5)) == nil)
}

@Test func aMissingCapacityIsNoReading() {
    #expect(PowerSourceMonitor.reading(from: battery(current: nil)) == nil)
    #expect(PowerSourceMonitor.reading(from: battery(maximum: nil)) == nil)
}

@Test func aCurrentAboveTheMaximumReadsAsFull() {
    #expect(PowerSourceMonitor.reading(from: battery(current: 105, maximum: 100))?.level == 100)
}

@Test func batteryPowerIsNotTheAdapterAndAMissingChargingFlagIsFalse() {
    let reading = PowerSourceMonitor.reading(from: battery(state: "Battery Power", charging: nil))
    #expect(reading?.onAC == false)
    #expect(reading?.charging == false)
}

@Test func theInternalBatteryIsChosenAmongTheSources() {
    let ups: [String: Any] = ["Type": "UPS", "Current Capacity": 10, "Max Capacity": 100]
    let chosen = PowerSourceMonitor.internalBattery(in: [ups, battery(current: 61)])
    #expect(chosen.flatMap(PowerSourceMonitor.reading(from:))?.level == 61)
    #expect(PowerSourceMonitor.internalBattery(in: [ups]) == nil)
}

@Test func aSecondStartIsRefusedAndStopIsSafeToRepeat() {
    let monitor = PowerSourceMonitor(inbox: EngineInbox())
    #expect(monitor.start())
    #expect(!monitor.start())
    monitor.stop()
    monitor.stop()
    #expect(monitor.start())
    monitor.stop()
}
