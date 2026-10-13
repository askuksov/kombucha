import KombuchaCore
import Testing

private func snapshot(mode protection: Bool = true,
                      onAC: Bool = true,
                      writePath: WritePath = .ready,
                      manager: ExternalBatteryManager? = nil,
                      heatHold: Bool = false) -> ChargeSnapshot {
    ChargeSnapshot(level: 78, onAC: onAC, charging: false, thresholds: .standard, protection: protection,
                   fullChargeActive: false, writePath: writePath, externalBatteryManager: manager,
                   heatHold: heatHold)
}

@Test(arguments: [SupportVerdict.noSMCService, .noBattery, .chargeKeyMissing, .smcUnusable])
func anUnsupportedMacShowsItsReasonWhateverTheSnapshot(verdict: SupportVerdict) {
    #expect(PanelState.make(snapshot: nil, verdict: verdict) == .unsupported(verdict))
    #expect(PanelState.make(snapshot: snapshot(), verdict: verdict) == .unsupported(verdict))
}

@Test func withoutASnapshotThePanelWaitsForTheFirstReading() {
    #expect(PanelState.make(snapshot: nil, verdict: .supported) == .firstReading)
    #expect(PanelState.make(snapshot: nil, verdict: nil) == .firstReading)
}

@Test(arguments: [WritePath.unreachable, .requiresApproval, .notRegistered, .notFound, .unknown])
func aBlockedWritePathOutranksTheMode(path: WritePath) {
    #expect(PanelState.make(snapshot: snapshot(mode: false, writePath: path), verdict: .supported)
        == .writePathBlocked(path, level: 78))
}

@Test func aBlockedWritePathOutranksAnExternalBatteryManager() {
    let both = snapshot(writePath: .notRegistered, manager: .kombuchaFloat)
    #expect(PanelState.make(snapshot: both, verdict: .supported) == .writePathBlocked(.notRegistered, level: 78))
}

@Test func anExternalBatteryManagerOutranksTheMode() {
    // Stepped back for Kombucha Float at 78 % in a 75–80 range: the mode says protected, the panel must not.
    let steppedBack = snapshot(manager: .kombuchaFloat)
    #expect(steppedBack.mode == .protected)
    #expect(PanelState.make(snapshot: steppedBack, verdict: .supported) == .externalBatteryManager(.kombuchaFloat, level: 78))
}

@Test func aGateOutranksTheHeatPause() {
    // G-3: the mode says heatPaused, but a blocked write path or an external battery manager shows its gate.
    let blocked = snapshot(writePath: .notRegistered, heatHold: true)
    #expect(blocked.mode == .heatPaused)
    #expect(PanelState.make(snapshot: blocked, verdict: .supported) == .writePathBlocked(.notRegistered, level: 78))
    let managed = snapshot(manager: .kombuchaFloat, heatHold: true)
    #expect(managed.mode == .heatPaused)
    #expect(PanelState.make(snapshot: managed, verdict: .supported) == .externalBatteryManager(.kombuchaFloat, level: 78))
}

@Test func aReadyPathWithNoManagerShowsTheControls() {
    let ready = snapshot()
    #expect(PanelState.make(snapshot: ready, verdict: .supported) == .controls(ready))
}

@Test func aSnapshotBeforeTheVerdictIsShown() {
    let ready = snapshot(onAC: false)
    #expect(PanelState.make(snapshot: ready, verdict: nil) == .controls(ready))
}

@Test func aGateOutranksADischarge() {
    let blocked = ChargeSnapshot(level: 90, onAC: true, charging: false, thresholds: .standard, protection: true,
                                 fullChargeActive: false, writePath: .unreachable, dischargeActive: true)
    #expect(blocked.mode == .discharging)
    #expect(PanelState.make(snapshot: blocked, verdict: .supported) == .writePathBlocked(.unreachable, level: 90))
}
