import KombuchaCore
import Testing

private struct ModeCase: Sendable {
    let onAC: Bool
    let charging: Bool
    let protection: Bool
    let fullChargeActive: Bool
    let expected: Mode
}

private let modeCases: [ModeCase] = [
    ModeCase(onAC: false, charging: false, protection: false, fullChargeActive: false, expected: .onBattery),
    ModeCase(onAC: false, charging: false, protection: false, fullChargeActive: true, expected: .onBattery),
    ModeCase(onAC: false, charging: false, protection: true, fullChargeActive: false, expected: .onBattery),
    ModeCase(onAC: false, charging: false, protection: true, fullChargeActive: true, expected: .onBattery),
    ModeCase(onAC: false, charging: true, protection: false, fullChargeActive: false, expected: .onBattery),
    ModeCase(onAC: false, charging: true, protection: false, fullChargeActive: true, expected: .onBattery),
    ModeCase(onAC: false, charging: true, protection: true, fullChargeActive: false, expected: .onBattery),
    ModeCase(onAC: false, charging: true, protection: true, fullChargeActive: true, expected: .onBattery),
    ModeCase(onAC: true, charging: false, protection: false, fullChargeActive: false, expected: .protectionOff),
    ModeCase(onAC: true, charging: false, protection: false, fullChargeActive: true, expected: .fullCharge),
    ModeCase(onAC: true, charging: false, protection: true, fullChargeActive: false, expected: .protected),
    ModeCase(onAC: true, charging: false, protection: true, fullChargeActive: true, expected: .fullCharge),
    ModeCase(onAC: true, charging: true, protection: false, fullChargeActive: false, expected: .protectionOff),
    ModeCase(onAC: true, charging: true, protection: false, fullChargeActive: true, expected: .fullCharge),
    ModeCase(onAC: true, charging: true, protection: true, fullChargeActive: false, expected: .charging),
    ModeCase(onAC: true, charging: true, protection: true, fullChargeActive: true, expected: .fullCharge),
]

@Test(arguments: modeCases)
private func modeFollowsItsPrecedence(example: ModeCase) {
    let mode = Mode.derive(onAC: example.onAC,
                           charging: example.charging,
                           protection: example.protection,
                           fullChargeActive: example.fullChargeActive)
    #expect(mode == example.expected)
}

@Test func theTableCoversAllSixteenCombinations() {
    #expect(modeCases.count == 16)
}

@Test func heatPausesTheChargeOnlyWithProtectionOnAndTheAdapterIn() {
    #expect(Mode.derive(onAC: true, charging: false, protection: true, fullChargeActive: false, heatHold: true) == .heatPaused)
    #expect(Mode.derive(onAC: true, charging: true, protection: true, fullChargeActive: false, heatHold: true) == .heatPaused)
    // Heat outranks a running full charge.
    #expect(Mode.derive(onAC: true, charging: false, protection: true, fullChargeActive: true, heatHold: true) == .heatPaused)
    // No adapter and no protection are not heat's business.
    #expect(Mode.derive(onAC: false, charging: false, protection: true, fullChargeActive: false, heatHold: true) == .onBattery)
    #expect(Mode.derive(onAC: true, charging: false, protection: false, fullChargeActive: false, heatHold: true) == .protectionOff)
}

@Test func withoutAHeatHoldTheModeIsAsBefore() {
    #expect(Mode.derive(onAC: true, charging: true, protection: true, fullChargeActive: false, heatHold: false) == .charging)
    #expect(Mode.derive(onAC: true, charging: false, protection: true, fullChargeActive: true) == .fullCharge)
}

@Test func aDischargeShowsAsDischargingWheneverTheAdapterIsThere() {
    for charging in [true, false] {
        for protection in [true, false] {
            for fullCharge in [true, false] {
                for heat in [true, false] {
                    #expect(Mode.derive(onAC: true, charging: charging, protection: protection,
                                        fullChargeActive: fullCharge, heatHold: heat, dischargeActive: true) == .discharging)
                    #expect(Mode.derive(onAC: false, charging: charging, protection: protection,
                                        fullChargeActive: fullCharge, heatHold: heat, dischargeActive: true) == .onBattery)
                }
            }
        }
    }
}
