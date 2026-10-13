import KombuchaCore
import Testing

@Test(arguments: [
    (true, SMCProbeResult.ok, SupportVerdict.supported),
    (true, .serviceNotFound, .noSMCService),
    (true, .keyNotFound, .chargeKeyMissing),
    (true, .otherFailure, .smcUnusable),
    (false, .ok, .noBattery),
    (false, .serviceNotFound, .noSMCService),
    (false, .keyNotFound, .noBattery),
    (false, .otherFailure, .noBattery),
])
func theVerdictFollowsItsOrder(hasInternalBattery: Bool, probe: SMCProbeResult, expected: SupportVerdict) {
    #expect(SupportVerdict.verdict(hasInternalBattery: hasInternalBattery, probe: probe) == expected)
}

@Test func aMissingServiceOutranksAMissingBattery() {
    #expect(SupportVerdict.verdict(hasInternalBattery: false, probe: .serviceNotFound) == .noSMCService)
}

@Test func aMissingBatteryOutranksAMissingKey() {
    #expect(SupportVerdict.verdict(hasInternalBattery: false, probe: .keyNotFound) == .noBattery)
}
