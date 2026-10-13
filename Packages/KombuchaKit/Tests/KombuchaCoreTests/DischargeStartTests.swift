import KombuchaCore
import Testing

private func snapshot(level: Double = 94,
                      onAC: Bool = true,
                      protection: Bool = true,
                      fullCharge: Bool = false,
                      writePath: WritePath = .ready,
                      manager: ExternalBatteryManager? = nil,
                      adapterSwitch: Bool = true) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: onAC, charging: false, thresholds: .standard, protection: protection,
                   fullChargeActive: fullCharge, writePath: writePath, externalBatteryManager: manager,
                   adapterSwitchAvailable: adapterSwitch)
}

@Test func aBatteryAboveStopOnTheAdapterMayDischarge() {
    #expect(DischargeStart.refusal(snapshot()) == nil)
    #expect(DischargeStart.refusal(snapshot(level: 80.6)) == nil)
}

@Test func eachConditionRefusesWithItsOwnReason() {
    #expect(DischargeStart.refusal(nil) == .noReading)
    #expect(DischargeStart.refusal(snapshot(writePath: .requiresApproval)) == .gateClosed)
    #expect(DischargeStart.refusal(snapshot(manager: .batt)) == .gateClosed)
    #expect(DischargeStart.refusal(snapshot(adapterSwitch: false)) == .adapterSwitchUnavailable)
    #expect(DischargeStart.refusal(snapshot(protection: false)) == .protectionOff)
    #expect(DischargeStart.refusal(snapshot(onAC: false)) == .adapterAbsent)
    #expect(DischargeStart.refusal(snapshot(fullCharge: true)) == .fullChargeActive)
}

@Test func aLevelThatShowsAsStopOrLowerIsRefused() {
    #expect(DischargeStart.refusal(snapshot(level: 80)) == .notAboveStop)
    #expect(DischargeStart.refusal(snapshot(level: 80.4)) == .notAboveStop)
    #expect(DischargeStart.refusal(snapshot(level: 60)) == .notAboveStop)
}

@Test func aGateOutranksEveryOtherReason() {
    #expect(DischargeStart.refusal(snapshot(level: 60, onAC: false, protection: false, writePath: .unreachable)) == .gateClosed)
}
