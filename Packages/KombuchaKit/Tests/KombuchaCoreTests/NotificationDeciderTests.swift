import Foundation
import KombuchaCore
import Testing

private let range = Thresholds.standard
private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let both = NotificationGates(fullChargeFinished: true, protectionChanges: true)

private func snapshot(level: Double = 78,
                      protection: Bool = true,
                      fullCharge: Bool = false,
                      writePath: WritePath = .ready,
                      manager: ExternalBatteryManager? = nil) -> ChargeSnapshot {
    ChargeSnapshot(level: level, onAC: true, charging: false, thresholds: range, protection: protection,
                   fullChargeActive: fullCharge, writePath: writePath, externalBatteryManager: manager)
}

/// Feeds one snapshot and returns what the decider made of it.
private func decide(_ decider: inout NotificationDecider,
                    _ snapshot: ChargeSnapshot,
                    ending: FullChargeEnding? = nil,
                    gates: NotificationGates = both,
                    at moment: Date = start) -> NotificationDecision {
    decider.observe(snapshot, fullChargeEnded: ending, gates: gates, now: moment)
}

@Test func aFullChargeThatReachedFullIsAnnouncedWithTheRange() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot(level: 99, fullCharge: true))
    let decision = decide(&decider, snapshot(level: 100), ending: .reachedFull)
    #expect(decision.posts == [.fullyCharged(range)])
    #expect(decision.wakeAt == nil)
}

@Test func aFullChargeEndingIsSilentWithoutAPreviousActiveFullCharge() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot(level: 99))
    #expect(decide(&decider, snapshot(level: 100), ending: .reachedFull).posts.isEmpty)
}

@Test(arguments: [FullChargeEnding.unplugged, .protectionOff, .externalBatteryManager])
func theOtherEndingsAreSilent(ending: FullChargeEnding) {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot(level: 99, fullCharge: true))
    #expect(decide(&decider, snapshot(level: 99), ending: ending).posts.isEmpty)
}

@Test func aFullChargeIsSilentWhenItsSwitchIsOff() {
    var decider = NotificationDecider()
    let gates = NotificationGates(fullChargeFinished: false, protectionChanges: true)
    _ = decide(&decider, snapshot(level: 99, fullCharge: true), gates: gates)
    #expect(decide(&decider, snapshot(level: 100), ending: .reachedFull, gates: gates).posts.isEmpty)
}

@Test func aLostWritePathOnlyAsksToBeAskedAgain() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot())
    let decision = decide(&decider, snapshot(writePath: .notRegistered))
    #expect(decision.posts.isEmpty)
    #expect(decision.wakeAt == start.addingTimeInterval(NotificationDecider.interruptionGrace))
}

@Test func anInterruptionThatOutlivesTheGraceIsAnnouncedOnce() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot())
    _ = decide(&decider, snapshot(writePath: .notRegistered))
    let late = start.addingTimeInterval(NotificationDecider.interruptionGrace)
    let decision = decider.tick(gates: both, now: late)
    #expect(decision.posts == [.protectionStopped(.writePathBlocked(.notRegistered, level: 78))])
    #expect(decision.wakeAt == nil)
    #expect(decider.tick(gates: both, now: late.addingTimeInterval(60)).posts.isEmpty)
}

@Test func anInterruptionThatHealsInsideTheGraceIsSilent() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot())
    _ = decide(&decider, snapshot(writePath: .notRegistered))
    let back = start.addingTimeInterval(5)
    #expect(decide(&decider, snapshot(), at: back).posts.isEmpty)
    #expect(decider.tick(gates: both, now: start.addingTimeInterval(120)).posts.isEmpty)
}

@Test func aReturnAfterAnAnnouncedInterruptionIsAnnounced() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot())
    _ = decide(&decider, snapshot(writePath: .notRegistered))
    let late = start.addingTimeInterval(NotificationDecider.interruptionGrace)
    _ = decider.tick(gates: both, now: late)
    #expect(decide(&decider, snapshot(), at: late.addingTimeInterval(1)).posts == [.protectionResumed])
}

@Test func protectionSwitchedOffDuringAnInterruptionEndsItWithoutAWord() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot())
    _ = decide(&decider, snapshot(writePath: .notRegistered))
    let off = decide(&decider, snapshot(protection: false, writePath: .notRegistered), at: start.addingTimeInterval(2))
    #expect(off.posts.isEmpty)
    #expect(off.wakeAt == nil)
    #expect(decider.tick(gates: both, now: start.addingTimeInterval(120)).posts.isEmpty)
}

@Test func aSwitchThatWasOffAtTheStopAlsoSilencesTheReturn() {
    var decider = NotificationDecider()
    let gates = NotificationGates(fullChargeFinished: true, protectionChanges: false)
    _ = decide(&decider, snapshot(), gates: gates)
    _ = decide(&decider, snapshot(writePath: .notRegistered), gates: gates)
    let late = start.addingTimeInterval(NotificationDecider.interruptionGrace)
    #expect(decider.tick(gates: gates, now: late).posts.isEmpty)
    #expect(decide(&decider, snapshot(), gates: gates, at: late.addingTimeInterval(1)).posts.isEmpty)
}

@Test func theSameSnapshotTwiceDoesNotStartASecondInterruption() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot())
    let lost = snapshot(writePath: .notRegistered)
    _ = decide(&decider, lost)
    let repeated = decide(&decider, lost, at: start.addingTimeInterval(10))
    #expect(repeated.posts.isEmpty)
    // The grace is counted from the first sighting, not from the repeat.
    #expect(repeated.wakeAt == start.addingTimeInterval(NotificationDecider.interruptionGrace))
}

@Test func theFirstSnapshotNeverAnnouncesAnything() {
    var decider = NotificationDecider()
    let decision = decide(&decider, snapshot(writePath: .notRegistered))
    #expect(decision.posts.isEmpty)
    #expect(decision.wakeAt == nil)
    #expect(decider.tick(gates: both, now: start.addingTimeInterval(600)).posts.isEmpty)
}

@Test func anExternalBatteryManagerIsTheBodyOfItsOwnInterruption() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot())
    _ = decide(&decider, snapshot(manager: .kombuchaFloat))
    let late = start.addingTimeInterval(NotificationDecider.interruptionGrace)
    #expect(decider.tick(gates: both, now: late).posts
        == [.protectionStopped(.externalBatteryManager(.kombuchaFloat, level: 78))])
}

@Test func anOrdinaryThresholdCrossingIsSilent() {
    var decider = NotificationDecider()
    _ = decide(&decider, snapshot(level: 79))
    let crossed = decide(&decider, snapshot(level: 80), at: start.addingTimeInterval(60))
    #expect(crossed.posts.isEmpty)
    #expect(crossed.wakeAt == nil)
}

@Test func aTickWithoutASnapshotIsSilent() {
    var decider = NotificationDecider()
    #expect(decider.tick(gates: both, now: start).posts.isEmpty)
}
