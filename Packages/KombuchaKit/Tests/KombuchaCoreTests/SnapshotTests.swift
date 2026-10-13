import KombuchaCore
import Testing

private func snapshot(level: Double = 78,
                      onAC: Bool = true,
                      charging: Bool = false,
                      protection: Bool = true,
                      fullChargeActive: Bool = false,
                      writePath: WritePath = .ready,
                      externalBatteryManager: ExternalBatteryManager? = nil) -> ChargeSnapshot {
    ChargeSnapshot(level: level,
                   onAC: onAC,
                   charging: charging,
                   thresholds: .standard,
                   protection: protection,
                   fullChargeActive: fullChargeActive,
                   writePath: writePath,
                   externalBatteryManager: externalBatteryManager)
}

@Test(arguments: [
    (Double.nan, 0.0),
    (.signalingNaN, 0.0),
    (.infinity, 0.0),
    (-.infinity, 0.0),
    (-5.0, 0.0),
    (150.0, 100.0),
    (0.0, 0.0),
    (78.4, 78.4),
    (100.0, 100.0),
])
func theLevelIsSanitized(level: Double, expected: Double) {
    // A non-finite level becomes 0 before the clamp, so an infinite reading never shows as full.
    #expect(snapshot(level: level).level == expected)
}

@Test(arguments: [(41.4, 41), (41.5, 42), (0.4, 0), (99.6, 100)])
func theDisplayLevelRounds(level: Double, expected: Int) {
    #expect(snapshot(level: level).displayLevel == expected)
}

@Test func aSnapshotWithoutAVerdictCarriesUnknownAndCannotManage() {
    let fresh = ChargeSnapshot(level: 78,
                               onAC: true,
                               charging: false,
                               thresholds: .standard,
                               protection: true,
                               fullChargeActive: false)
    #expect(fresh.writePath == .unknown)
    #expect(!fresh.mayManage)
    #expect(fresh.externalBatteryManager == nil)
}

@Test func mayManageOnlyWithAReadyPathAndNoExternalBatteryManager() {
    let paths: [WritePath] = [.ready, .unreachable, .requiresApproval, .notRegistered, .notFound, .unknown]
    let externalBatteryManagers: [ExternalBatteryManager?] = [nil] + ExternalBatteryManager.allCases.map { Optional($0) }
    var violations: [String] = []
    for path in paths {
        for externalBatteryManager in externalBatteryManagers {
            let expected = path == .ready && externalBatteryManager == nil
            if snapshot(writePath: path, externalBatteryManager: externalBatteryManager).mayManage != expected {
                violations.append("\(path) × \(String(describing: externalBatteryManager))")
            }
        }
    }
    #expect(violations.isEmpty)
    #expect(snapshot(writePath: .ready).mayManage)
    #expect(!snapshot(writePath: .ready, externalBatteryManager: .batt).mayManage)
    #expect(!snapshot(writePath: .unreachable).mayManage)
}

@Test func theModeIsDerivedAndNeverStored() {
    #expect(snapshot(onAC: false).mode == .onBattery)
    #expect(snapshot(charging: true).mode == .charging)
    #expect(snapshot(protection: false).mode == .protectionOff)
    #expect(snapshot(fullChargeActive: true).mode == .fullCharge)
    #expect(snapshot().mode == .protected)
}

@Test func attachingAWritePathChangesNothingElse() {
    let original = snapshot(level: 61, charging: true, writePath: .unknown, externalBatteryManager: .batFi)
    let attached = original.withWritePath(.ready)
    #expect(attached.writePath == .ready)
    #expect(attached.level == original.level)
    #expect(attached.charging == original.charging)
    #expect(attached.thresholds == original.thresholds)
    #expect(attached.protection == original.protection)
    #expect(attached.fullChargeActive == original.fullChargeActive)
    #expect(attached.externalBatteryManager == original.externalBatteryManager)
    #expect(attached.mode == original.mode)
}

@Test func theEngineAttachesTheDischargeAndTheWritePathKeepsIt() {
    let planned = ChargeSnapshot(level: 90, onAC: true, charging: false, thresholds: .standard, protection: true,
                                 fullChargeActive: false, dischargeActive: true)
    #expect(planned.mode == .discharging)
    #expect(!planned.adapterSwitchAvailable)
    #expect(planned.withWritePath(.ready).dischargeActive)
    let attached = planned.withDischarge(false, adapterSwitchAvailable: true).withWritePath(.ready)
    #expect(!attached.dischargeActive)
    #expect(attached.adapterSwitchAvailable)
    #expect(attached.writePath == .ready)
    #expect(attached.mode == .protected)
}
