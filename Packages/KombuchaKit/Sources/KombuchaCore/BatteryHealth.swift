/// Raw values read from the `AppleSmartBattery` registry node.
public struct BatteryRegistryValues: Sendable {
    public var cycleCount: Int?
    public var designCapacity: Int?
    public var nominalChargeCapacity: Int?
    public var permanentFailureStatus: Int?
    public var temperature: Int?
    public var voltage: Int?
    /// Cells in series, counted from `BatteryData` → `CellVoltage`.
    public var cellCount: Int?

    public init(cycleCount: Int? = nil,
                designCapacity: Int? = nil,
                nominalChargeCapacity: Int? = nil,
                permanentFailureStatus: Int? = nil,
                temperature: Int? = nil,
                voltage: Int? = nil,
                cellCount: Int? = nil) {
        self.cycleCount = cycleCount
        self.designCapacity = designCapacity
        self.nominalChargeCapacity = nominalChargeCapacity
        self.permanentFailureStatus = permanentFailureStatus
        self.temperature = temperature
        self.voltage = voltage
        self.cellCount = cellCount
    }
}

public struct BatteryHealth: Equatable, Sendable {
    public enum Condition: Equatable, Sendable {
        case normal, serviceRecommended
    }

    public let cycleCount: Int
    public let maximumCapacityPercent: Int
    public let condition: Condition
    public let temperatureCelsius: Double
    public let voltageVolts: Double
    public let fullChargeCapacityMAh: Int
    public let designCapacityMAh: Int
    public let cellCount: Int?

    /// The registry publishes no nominal pack voltage; a typical Li-ion cell nominal stands in, so Wh is an estimate.
    static let nominalCellVolts = 3.85

    init(cycleCount: Int,
         maximumCapacityPercent: Int,
         condition: Condition,
         temperatureCelsius: Double,
         voltageVolts: Double,
         fullChargeCapacityMAh: Int,
         designCapacityMAh: Int,
         cellCount: Int?) {
        self.cycleCount = cycleCount
        self.maximumCapacityPercent = maximumCapacityPercent
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.voltageVolts = voltageVolts
        self.fullChargeCapacityMAh = fullChargeCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.cellCount = cellCount
    }

    public var fullChargeEnergyWh: Int? { energyWh(fullChargeCapacityMAh) }
    public var designEnergyWh: Int? { energyWh(designCapacityMAh) }

    /// Whole watt-hours, or nil when the cell count is unknown.
    private func energyWh(_ milliampHours: Int) -> Int? {
        guard let cellCount, cellCount > 0 else { return nil }
        return Int((Double(milliampHours) * Double(cellCount) * Self.nominalCellVolts / 1000).rounded())
    }

    /// A missing key, a negative value or a zero design capacity yields nil, never a zero;
    /// so does a nominal capacity large enough to overflow the ×100 multiplication.
    public static func derive(_ values: BatteryRegistryValues) -> BatteryHealth? {
        guard let cycleCount = values.cycleCount, cycleCount >= 0,
              let designCapacity = values.designCapacity, designCapacity > 0,
              let nominal = values.nominalChargeCapacity, nominal >= 0, nominal <= Int.max / 100,
              let failure = values.permanentFailureStatus, failure >= 0,
              let temperature = values.temperature, temperature >= 0,
              let voltage = values.voltage, voltage >= 0
        else { return nil }
        return BatteryHealth(cycleCount: cycleCount,
                             maximumCapacityPercent: nominal * 100 / designCapacity,
                             condition: failure == 0 ? .normal : .serviceRecommended,
                             temperatureCelsius: Double(temperature) / 100,
                             voltageVolts: Double(voltage) / 1000,
                             fullChargeCapacityMAh: nominal,
                             designCapacityMAh: designCapacity,
                             cellCount: values.cellCount)
    }
}
