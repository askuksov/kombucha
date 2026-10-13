import IOKit
import KombuchaCore

/// Battery health from the top level of the `AppleSmartBattery` registry node.
enum BatteryHealthReader {
    static func read() -> BatteryHealth? {
        properties().flatMap { BatteryHealth.derive(values(from: $0)) }
    }

    /// The battery cell temperature in °C: Heat Protection's signal. Nil when the registry gives none; a raw value
    /// of 0 or below is treated as no reading.
    static func temperatureCelsius(from properties: [String: Any]) -> Double? {
        guard let raw = properties["Temperature"] as? Int, raw > 0 else { return nil }
        return Double(raw) / 100
    }

    /// The temperature and the cable from one registry read, for the engine's pass.
    static func registryReading() -> (temperatureCelsius: Double?, adapterPresent: Bool?) {
        guard let properties = properties() else { return (nil, nil) }
        return (temperatureCelsius(from: properties), adapterPresent(from: properties))
    }

    /// `AdapterDetails` names the adapter also while Kombucha has it switched off; a pulled cable leaves
    /// `{FamilyCode = 0}` without `Watts`. Nil when the registry has no `AdapterDetails` at all.
    static func adapterPresent(from properties: [String: Any]) -> Bool? {
        guard let details = properties["AdapterDetails"] as? [String: Any] else { return nil }
        guard let watts = details["Watts"] as? Int else { return false }
        return watts > 0
    }

    static func values(from properties: [String: Any]) -> BatteryRegistryValues {
        BatteryRegistryValues(cycleCount: properties["CycleCount"] as? Int,
                              designCapacity: properties["DesignCapacity"] as? Int,
                              nominalChargeCapacity: properties["NominalChargeCapacity"] as? Int,
                              permanentFailureStatus: properties["PermanentFailureStatus"] as? Int,
                              temperature: properties["Temperature"] as? Int,
                              voltage: properties["Voltage"] as? Int)
    }

    /// The registry node's top level. In Debug builds the live-check overrides apply here, so the health rows, the
    /// history and Heat Protection all see the same injected value.
    private static func properties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        #if DEBUG
        var overridden = dictionary
        DebugOverrides.apply(to: &overridden)
        return overridden
        #else
        return dictionary
        #endif
    }
}
