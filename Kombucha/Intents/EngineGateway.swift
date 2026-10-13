import KombuchaCore

/// What an intent asks of Kombucha. The app registers the live one at launch; tests hand intents a fake.
protocol EngineGateway: Sendable {
    func status() async throws -> BatteryStatus
    func setProtection(_ on: Bool) async throws -> Bool
    func startFullCharge() async throws
    func stopFullCharge() async throws
    func setThresholds(stop: Int, resume: Int) async throws -> Thresholds
}

/// Get Battery Status's answer. `line` is the dialog's second sentence: the status line, or the gate's heading
/// while Kombucha cannot manage.
struct BatteryStatus: Equatable, Sendable {
    let level: Int
    let mode: Mode
    let thresholds: Thresholds
    let protection: Bool
    let holdingLimit: Bool
    let line: String
}
