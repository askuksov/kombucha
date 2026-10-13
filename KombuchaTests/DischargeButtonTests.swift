import KombuchaCore
import Testing
@testable import Kombucha

private func snapshot(level: Double = 94,
                      onAC: Bool = true,
                      protection: Bool = true,
                      fullCharge: Bool = false,
                      discharging: Bool = false,
                      adapterSwitch: Bool = true,
                      writePath: WritePath = .ready) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: onAC, charging: false, thresholds: .standard, protection: protection,
                   fullChargeActive: fullCharge, writePath: writePath, dischargeActive: discharging,
                   adapterSwitchAvailable: adapterSwitch)
}

@Test func theStartButtonNamesTheStopLevel() {
    #expect(ControlsSection.dischargeButton(for: snapshot(), pending: nil) == .start(upper: 80))
}

@Test func aRunningDischargeShowsTheStopButton() {
    #expect(ControlsSection.dischargeButton(for: snapshot(discharging: true), pending: nil) == .stop)
}

@Test func noButtonWhenADischargeCannotStart() {
    for refused in [snapshot(level: 80), snapshot(protection: false), snapshot(onAC: false), snapshot(fullCharge: true),
                    snapshot(adapterSwitch: false), snapshot(writePath: .requiresApproval)] {
        #expect(ControlsSection.dischargeButton(for: refused, pending: nil) == nil)
    }
}

@Test func aPendingPressShowsWhereItIsGoing() {
    #expect(ControlsSection.dischargeButton(for: snapshot(), pending: true) == .stop)
    #expect(ControlsSection.dischargeButton(for: snapshot(discharging: true), pending: false) == .start(upper: 80))
}
