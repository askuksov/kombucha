#if DEBUG
import Foundation

/// Lets the live check provoke the temperature and capacity alerts without heating the Mac. Debug builds only:
/// `KOMBUCHA_FAKE_TEMP` (°C) and `KOMBUCHA_FAKE_CAPACITY` (percent of design capacity) replace what the registry says.
enum DebugOverrides {
    static func apply(to properties: inout [String: Any], environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let text = environment["KOMBUCHA_FAKE_TEMP"], let celsius = Double(text) {
            properties["Temperature"] = Int(celsius * 100)
        }
        if let text = environment["KOMBUCHA_FAKE_CAPACITY"], let percent = Int(text),
           let design = properties["DesignCapacity"] as? Int {
            properties["NominalChargeCapacity"] = design * percent / 100
        }
    }
}
#endif
