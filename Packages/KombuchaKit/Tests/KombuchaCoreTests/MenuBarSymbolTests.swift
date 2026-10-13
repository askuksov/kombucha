import KombuchaCore
import Testing

private struct SymbolCase: Sendable {
    let mode: Mode
    let mayManage: Bool
    let supported: Bool
    let expected: MenuBarSymbol
}

private func snapshot(mode: Mode, mayManage: Bool) -> ChargeSnapshot {
    let onAC = mode != .onBattery
    let charging = mode == .charging
    let protection = mode != .protectionOff
    let fullCharge = mode == .fullCharge
    let heat = mode == .heatPaused
    let discharging = mode == .discharging
    return ChargeSnapshot(level: 78,
                          onAC: onAC,
                          charging: charging,
                          thresholds: .standard,
                          protection: protection,
                          fullChargeActive: fullCharge,
                          writePath: mayManage ? .ready : .unreachable,
                          externalBatteryManager: nil,
                          heatHold: heat,
                          dischargeActive: discharging)
}

private let allModes: [Mode] = [.protected, .charging, .fullCharge, .protectionOff, .onBattery, .heatPaused, .discharging]

/// Written from the spec table, not from `MenuBarSymbol.symbol`.
private func expectedSymbol(mode: Mode, mayManage: Bool, supported: Bool) -> MenuBarSymbol {
    guard supported else { return .blocked }
    switch mode {
    case .protected: return mayManage ? .resting : .blocked
    case .charging: return mayManage ? .charging : .blocked
    case .fullCharge, .protectionOff: return .fullCharge
    case .onBattery: return .onBattery
    case .heatPaused: return mayManage ? .heatPaused : .blocked
    case .discharging: return mayManage ? .onBattery : .blocked
    }
}

// Every mode × mayManage × supported.
private let symbolCases: [SymbolCase] = allModes.flatMap { mode in
    [true, false].flatMap { mayManage in
        [true, false].map { supported in
            SymbolCase(mode: mode, mayManage: mayManage, supported: supported,
                       expected: expectedSymbol(mode: mode, mayManage: mayManage, supported: supported))
        }
    }
}

@Test(arguments: symbolCases)
private func everyModeHasItsSymbol(example: SymbolCase) {
    let snapshot = snapshot(mode: example.mode, mayManage: example.mayManage)
    #expect(snapshot.mode == example.mode)
    #expect(snapshot.mayManage == example.mayManage)
    #expect(MenuBarSymbol.symbol(snapshot: snapshot, supported: example.supported) == example.expected)
}

@Test func noSnapshotYetIsBlocked() {
    #expect(MenuBarSymbol.symbol(snapshot: nil, supported: true) == .blocked)
    #expect(MenuBarSymbol.symbol(snapshot: nil, supported: false) == .blocked)
}

@Test func anExternalBatteryManagerAlsoBlocksTheRestingAndChargingSymbols() {
    let blocked = ChargeSnapshot(level: 78,
                                 onAC: true,
                                 charging: false,
                                 thresholds: .standard,
                                 protection: true,
                                 fullChargeActive: false,
                                 writePath: .ready,
                                 externalBatteryManager: .alDente)
    #expect(MenuBarSymbol.symbol(snapshot: blocked, supported: true) == .blocked)
}
