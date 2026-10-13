import KombuchaCore
import SMCKit

/// System and adapter watts from the SMC, read without privileges. A key that did not read is nil, and so is
/// every key when the SMC will not open.
enum PowerReader {
    static func read() -> PowerReadings {
        let values = (try? SMCSensor.readFloats([SMCSensor.systemPower, SMCSensor.adapterPower])) ?? [:]
        return PowerReadings.derive(system: values[SMCSensor.systemPower], adapter: values[SMCSensor.adapterPower])
    }
}
