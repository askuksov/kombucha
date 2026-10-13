import Testing
@testable import KombuchaCore

private func holding(at threshold: Int, fullCharge: Bool = false) -> MachineState {
    MachineState(inhibitedAt: threshold, fullChargeActive: fullCharge)
}

private func idle(fullCharge: Bool = false) -> MachineState {
    MachineState(inhibitedAt: nil, fullChargeActive: fullCharge)
}

private func input(_ level: Double,
                   onAC: Bool = true,
                   protection: Bool = true,
                   lower: Int = 75,
                   upper: Int = 80,
                   externalBatteryManagerRunning: Bool = false) -> MachineInput {
    MachineInput(level: level, onAC: onAC, protection: protection, lower: lower, upper: upper,
                 externalBatteryManagerRunning: externalBatteryManagerRunning)
}

private struct Row: Sendable {
    let number: Int
    let before: MachineState
    let input: MachineInput
    let command: ChargeCommand?
    let reason: CommandReason?
    let after: MachineState
    let ended: FullChargeEnding?
}

private let decisionTable: [Row] = [
    Row(number: 1, before: idle(), input: input(79), command: nil, reason: nil, after: idle(), ended: nil),
    Row(number: 2, before: idle(), input: input(80), command: .inhibit, reason: .stopThresholdReached, after: holding(at: 80), ended: nil),
    Row(number: 3, before: holding(at: 80), input: input(81), command: nil, reason: nil, after: holding(at: 80), ended: nil),
    Row(number: 4, before: holding(at: 80), input: input(75), command: .allow, reason: .resumeThresholdReached, after: idle(), ended: nil),
    Row(number: 5, before: holding(at: 80), input: input(83, onAC: false), command: .allow, reason: .adapterOut, after: idle(), ended: nil),
    Row(number: 6, before: idle(), input: input(74, onAC: false), command: nil, reason: nil, after: idle(), ended: nil),
    Row(number: 7, before: holding(at: 82), input: input(82, lower: 65, upper: 82), command: nil, reason: nil, after: holding(at: 82), ended: nil),
    Row(number: 8, before: holding(at: 82), input: input(82, lower: 70, upper: 75), command: nil, reason: nil, after: holding(at: 75), ended: nil),
    Row(number: 9, before: holding(at: 75), input: input(82, lower: 70, upper: 85), command: .allow, reason: .rangeWidened, after: idle(), ended: nil),
    Row(number: 10, before: holding(at: 80), input: input(81, protection: false), command: .allow, reason: .protectionOff, after: idle(), ended: nil),
    Row(number: 11, before: holding(at: 80, fullCharge: true), input: input(85), command: .allow, reason: .fullCharge, after: idle(fullCharge: true), ended: nil),
    Row(number: 12, before: idle(fullCharge: true), input: input(100), command: .inhibit, reason: .stopThresholdReached, after: holding(at: 80), ended: .reachedFull),
    Row(number: 13, before: idle(fullCharge: true), input: input(90, externalBatteryManagerRunning: true), command: nil, reason: nil, after: idle(), ended: .externalBatteryManager),
    Row(number: 14, before: holding(at: 80), input: input(.nan), command: nil, reason: nil, after: holding(at: 80), ended: nil),
]

@Test(arguments: decisionTable)
private func theDecisionTableHolds(row: Row) {
    let step = ChargeMachine.next(row.before, row.input)
    #expect(step.command == row.command, "row \(row.number): command")
    #expect(step.reason == row.reason, "row \(row.number): reason")
    #expect(step.state == row.after, "row \(row.number): state")
    #expect(step.fullChargeEnded == row.ended, "row \(row.number): ending")
}

@Test func climbingFromSeventyFourToEightySendsExactlyOneInhibit() {
    var state = MachineState()
    var commands: [ChargeCommand] = []
    for level in stride(from: 74.0, through: 80.0, by: 1.0) {
        let step = ChargeMachine.next(state, input(level))
        state = step.state
        if let command = step.command { commands.append(command) }
    }
    #expect(commands == [.inhibit])
    #expect(state.inhibitedAt == 80)
}

@Test func unpluggingReleasesOnceAndThenSixtyReadingsSendNothing() {
    var state = holding(at: 80)
    let unplug = ChargeMachine.next(state, input(83, onAC: false))
    state = unplug.state
    #expect(unplug.command == .allow)

    var commands: [ChargeCommand] = []
    for step in 0..<60 {
        let level = 83.0 - Double(step)
        let next = ChargeMachine.next(state, input(level, onAC: false))
        state = next.state
        if let command = next.command { commands.append(command) }
    }
    #expect(commands.isEmpty)
    #expect(!state.holdsInhibit)
}

@Test func raisingTheStopThresholdAboveAHeldInhibitSendsOneAllow() {
    var state = holding(at: 82)

    let loweredResume = ChargeMachine.next(state, input(82, lower: 65, upper: 82))
    state = loweredResume.state
    #expect(loweredResume.command == nil)

    let loweredStop = ChargeMachine.next(state, input(82, lower: 65, upper: 75))
    state = loweredStop.state
    #expect(loweredStop.command == nil)
    #expect(state.inhibitedAt == 75)

    let raisedStop = ChargeMachine.next(state, input(82, lower: 65, upper: 85))
    state = raisedStop.state
    #expect(raisedStop.command == .allow)
    #expect(!state.holdsInhibit)

    let reachedTheNewStop = ChargeMachine.next(state, input(85, lower: 65, upper: 85))
    #expect(reachedTheNewStop.command == .inhibit)
    #expect(reachedTheNewStop.state.inhibitedAt == 85)
}

@Test(arguments: [
    (FullChargeEnding.externalBatteryManager, true, true, true, 90.0),
    (FullChargeEnding.unplugged, false, true, false, 90.0),
    (FullChargeEnding.protectionOff, true, false, false, 90.0),
    (FullChargeEnding.reachedFull, true, true, false, 100.0),
])
func eachFullChargeEndingClearsTheFlag(expected: FullChargeEnding, onAC: Bool, protection: Bool, externalBatteryManagerRunning: Bool, level: Double) {
    let step = ChargeMachine.next(idle(fullCharge: true),
                                  input(level, onAC: onAC, protection: protection, externalBatteryManagerRunning: externalBatteryManagerRunning))
    #expect(step.fullChargeEnded == expected)
    #expect(!step.state.fullChargeActive)
}

@Test func theFirstEndingInOrderIsTheOneReported() {
    let step = ChargeMachine.next(idle(fullCharge: true),
                                  input(100, onAC: false, protection: false, externalBatteryManagerRunning: true))
    #expect(step.fullChargeEnded == .externalBatteryManager)
}

@Test func aFullChargeSendsNoCommandBetweenSeventyEightAndOneHundred() {
    var state = idle(fullCharge: true)
    var commands: [ChargeCommand] = []
    for tenth in 780...999 {
        let step = ChargeMachine.next(state, input(Double(tenth) / 10))
        state = step.state
        if let command = step.command { commands.append(command) }
        #expect(step.fullChargeEnded == nil)
    }
    #expect(commands.isEmpty)
    #expect(state.fullChargeActive)
}

@Test func aNotANumberLevelSendsNothing() {
    for level in [Double.nan, .signalingNaN] {
        let fromIdle = ChargeMachine.next(idle(), input(level))
        #expect(fromIdle.command == nil)
        #expect(fromIdle.state == idle())

        let held = ChargeMachine.next(holding(at: 80), input(level))
        #expect(held.command == nil)
        #expect(held.state == holding(at: 80))
    }
}

// An infinite level still compares, so the machine errs the safe way in both directions.
@Test func anInfiniteLevelErrsTowardNotOvercharging() {
    let high = ChargeMachine.next(idle(), input(.infinity))
    #expect(high.command == .inhibit)
    #expect(high.state.inhibitedAt == 80)

    let low = ChargeMachine.next(holding(at: 80), input(-.infinity))
    #expect(low.command == .allow)
    #expect(!low.state.holdsInhibit)
}

@Test func aSecondInhibitAtTheSameThresholdSendsNothing() {
    let first = ChargeMachine.next(idle(), input(81))
    #expect(first.command == .inhibit)
    let second = ChargeMachine.next(first.state, input(81))
    #expect(second.command == nil)
    #expect(second.state == first.state)
}

@Test func aSecondReleaseSendsNothing() {
    let first = ChargeMachine.next(holding(at: 80), input(70))
    #expect(first.command == .allow)
    let second = ChargeMachine.next(first.state, input(70))
    #expect(second.command == nil)
}

@Test func aReasonComesWithEveryCommandAndOnlyThen() {
    var violations: [String] = []
    for held in [nil, 70, 80, 90] as [Int?] {
        for fullCharge in [false, true] {
            for (lower, upper) in [(75, 80), (70, 90)] {
                for onAC in [false, true] {
                    for protection in [false, true] {
                        for external in [false, true] {
                            for level in stride(from: 60.0, through: 100.0, by: 2.5) {
                                let state = MachineState(inhibitedAt: held, fullChargeActive: fullCharge)
                                let step = ChargeMachine.next(state, input(level, onAC: onAC, protection: protection,
                                                                           lower: lower, upper: upper,
                                                                           externalBatteryManagerRunning: external))
                                let inhibitHasItsReason = step.command != .inhibit || step.reason == .stopThresholdReached
                                if (step.command == nil) != (step.reason == nil) || !inhibitHasItsReason || step.reason == .reassert {
                                    violations.append("\(state) \(level) \(lower)–\(upper) ac \(onAC) protection \(protection) external \(external)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    #expect(violations.isEmpty)
}

@Test func theFirstReasonForNotManagingIsTheOneNamed() {
    func reason(_ input: MachineInput, fullCharge: Bool = false) -> CommandReason? {
        ChargeMachine.next(holding(at: 80, fullCharge: fullCharge), input).reason
    }
    #expect(reason(input(85, onAC: false, protection: false, externalBatteryManagerRunning: true), fullCharge: true) == .externalBatteryManager)
    #expect(reason(input(85, onAC: false, protection: false), fullCharge: true) == .adapterOut)
    #expect(reason(input(85, protection: false), fullCharge: true) == .protectionOff)
    #expect(reason(input(85), fullCharge: true) == .fullCharge)
}
