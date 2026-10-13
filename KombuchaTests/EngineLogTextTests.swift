import KombuchaCore
import Testing
@testable import Kombucha

private let machineReasons: [(CommandReason, String)] = [
    (.stopThresholdReached, "stop threshold reached"),
    (.resumeThresholdReached, "resume threshold reached"),
    (.rangeWidened, "range widened"),
    (.externalBatteryManager, "external battery manager running"),
    (.adapterOut, "adapter out"),
    (.protectionOff, "protection off"),
    (.fullCharge, "full charge"),
    (.discharging, "discharging"),
]

private let reassertCauses: [(ReassertCause?, String)] = [
    (.start, "reassert at start"),
    (.wake, "reassert after wake"),
    (.reconnection, "reassert after reconnection"),
    (nil, "reassert"),
]

// The cause is passed on purpose: only a reassert may read it.
@Test(arguments: machineReasons)
func everyMachineReasonHasItsWords(reason: CommandReason, words: String) {
    #expect(EngineLogText.words(reason, cause: .wake) == words)
}

@Test(arguments: reassertCauses)
func theReassertNamesItsCause(cause: ReassertCause?, words: String) {
    #expect(EngineLogText.words(.reassert, cause: cause) == words)
}

@Test func aCommandLineCarriesTheLevelAndTheRange() {
    #expect(EngineLogText.because(.rangeWidened, cause: nil, level: 83, thresholds: .normalized(lower: 75, upper: 84))
            == "range widened (level 83%, range 75–84%)")
    #expect(EngineLogText.because(.reassert, cause: .wake, level: 78, thresholds: .standard)
            == "reassert after wake (level 78%, range 75–80%)")
    #expect(EngineLogText.because(nil, cause: nil, level: 50, thresholds: .standard)
            == "no reason recorded (level 50%, range 75–80%)")
}

@Test func theSettingsLineNamesProtectionAndTheRange() {
    #expect(EngineLogText.settings(ChargeSettings(thresholds: .standard, protection: true))
            == "settings: protection on, range 75–80%")
    #expect(EngineLogText.settings(ChargeSettings(thresholds: .normalized(lower: 70, upper: 84), protection: false))
            == "settings: protection off, range 70–84%")
}

@Test func theAdapterLineSaysWhichWayItWent() {
    #expect(EngineLogText.adapter(attached: true, level: 83) == "adapter: attached (level 83%)")
    #expect(EngineLogText.adapter(attached: false, level: 83) == "adapter: removed (level 83%)")
}

@Test func theFullChargeStartCarriesTheLevel() {
    #expect(EngineLogText.fullChargeStarted(level: 78) == "full charge: started (level 78%)")
}

private let fullChargeEndings: [(FullChargeEnding?, String)] = [
    (.reachedFull, "full charge: ended: reached 100% (level 100%)"),
    (.unplugged, "full charge: ended: adapter out (level 100%)"),
    (.protectionOff, "full charge: ended: protection off (level 100%)"),
    (.externalBatteryManager, "full charge: ended: external battery manager running (level 100%)"),
    (nil, "full charge: ended: stopped (level 100%)"),
]

@Test(arguments: fullChargeEndings)
func theFullChargeEndSaysHow(ending: FullChargeEnding?, line: String) {
    #expect(EngineLogText.fullChargeEnded(ending, level: 100) == line)
}

@Test func aCommandNotSentNamesTheHelper() {
    #expect(EngineLogText.notSent(.inhibit, why: "stop threshold reached (level 81%, range 75–80%)")
            == "inhibit not sent: the helper is not enabled (stop threshold reached (level 81%, range 75–80%))")
    #expect(EngineLogText.notSent(.allow, why: "adapter out (level 70%, range 75–80%)")
            == "allow not sent: the helper is not enabled (adapter out (level 70%, range 75–80%))")
}

@Test func theDischargeStartCarriesTheLevel() {
    #expect(EngineLogText.dischargeStarted(level: 94) == "discharge: started (level 94%)")
}

private let dischargeEndings: [(DischargeEnding, String)] = [
    (.reachedStop, "discharge: ended: reached Stop (level 80%)"),
    (.unplugged, "discharge: ended: adapter out (level 80%)"),
    (.protectionOff, "discharge: ended: protection off (level 80%)"),
    (.fullCharge, "discharge: ended: full charge started (level 80%)"),
    (.externalBatteryManager, "discharge: ended: external battery manager running (level 80%)"),
    (.stopped, "discharge: ended: stopped (level 80%)"),
    (.sleep, "discharge: ended: the Mac is going to sleep (level 80%)"),
    (.shutdown, "discharge: ended: Kombucha is quitting (level 80%)"),
    (.blocked, "discharge: ended: the helper cannot switch the adapter (level 80%)"),
]

@Test(arguments: dischargeEndings)
func theDischargeEndSaysHow(ending: DischargeEnding, line: String) {
    #expect(EngineLogText.dischargeEnded(ending, level: 80) == line)
}

@Test func theAdapterLinesNameTheCommand() {
    #expect(EngineLogText.adapterWords(.disable(leaseSeconds: 180)) == "adapter off (lease 180 s)")
    #expect(EngineLogText.adapterWords(.renew(leaseSeconds: 180)) == "adapter lease renewal (180 s)")
    #expect(EngineLogText.adapterWords(.enable) == "adapter on")
    #expect(EngineLogText.adapterNotSent(.enable) == "adapter on not sent: the helper cannot switch the adapter")
}

@Test func aRefusedStartSaysWhy() {
    #expect(EngineLogText.dischargeRefused(.notAboveStop) == "discharge: not started: the level is not above Stop")
    #expect(EngineLogText.dischargeRefused(.gateClosed) == "discharge: not started: Kombucha cannot manage the charger")
}
