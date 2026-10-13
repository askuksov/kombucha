public enum MenuBarSymbol: Equatable, Sendable {
    case resting, charging, fullCharge, onBattery, blocked, heatPaused

    /// Full charge and protection off keep their symbol when Kombucha cannot manage:
    /// charging to 100% is what an unmanaged Mac does anyway.
    public static func symbol(snapshot: ChargeSnapshot?, supported: Bool) -> MenuBarSymbol {
        guard supported, let snapshot else { return .blocked }
        switch snapshot.mode {
        case .protected: return snapshot.mayManage ? .resting : .blocked
        case .charging: return snapshot.mayManage ? .charging : .blocked
        case .fullCharge, .protectionOff: return .fullCharge
        case .onBattery: return .onBattery
        case .heatPaused: return snapshot.mayManage ? .heatPaused : .blocked
        case .discharging: return snapshot.mayManage ? .onBattery : .blocked
        }
    }
}
