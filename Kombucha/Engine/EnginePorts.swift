import KombuchaCore

protocol PowerSource: Sendable {
    var hasInternalBattery: Bool { get }
    /// Nil when the battery could not be read.
    func read() -> PowerReading?
}

protocol SMCProbing: Sendable {
    func probe() -> SMCProbeResult
    /// Whether this Mac has the adapter key. Reads only.
    func probeAdapterSwitch() -> Bool
}

protocol ProcessListing: Sendable {
    func executablePaths() -> [String]
}

/// A producer of engine events, such as the power source notification or the wake monitor.
protocol EventSource: Sendable {
    var name: String { get }
    /// False when the source could not start; the engine logs it and carries on.
    func start() -> Bool
    func stop()
}

/// Sees every pass's snapshot, published or not; notifications will observe through it.
protocol ChargeObserving: Sendable {
    func observe(_ snapshot: ChargeSnapshot, fullChargeEnded: FullChargeEnding?)
}

struct SilentObserver: ChargeObserving {
    func observe(_ snapshot: ChargeSnapshot, fullChargeEnded: FullChargeEnding?) {}
}

struct EnginePorts: Sendable {
    var power: any PowerSource
    var smc: any SMCProbing
    var processes: any ProcessListing
    var helper: any HelperConnecting
    var registrar: any HelperRegistering
    var settings: any SettingsStoring
    var observer: any ChargeObserving
    var eventSources: [any EventSource]
    var ownBundlePath: String
}
