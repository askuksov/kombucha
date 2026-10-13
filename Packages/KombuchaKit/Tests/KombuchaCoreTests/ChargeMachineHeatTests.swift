import Testing
@testable import KombuchaCore

private func input(_ level: Double,
                   temperature: Double?,
                   onAC: Bool = true,
                   protection: Bool = true,
                   lower: Int = 75,
                   upper: Int = 80,
                   manager: Bool = false) -> MachineInput {
    MachineInput(level: level, onAC: onAC, protection: protection, lower: lower, upper: upper,
                 externalBatteryManagerRunning: manager, temperatureCelsius: temperature)
}

private func state(inhibitedAt: Int? = nil,
                   fullCharge: Bool = false,
                   heatHold: Bool = false,
                   heatInhibited: Bool = false) -> MachineState {
    MachineState(inhibitedAt: inhibitedAt, fullChargeActive: fullCharge, heatHold: heatHold, heatInhibited: heatInhibited)
}

/// A battery that is held off for heat and nothing else.
private let paused = state(heatHold: true, heatInhibited: true)

@Test func theHeatMarksAreFortyAndThirtySeven() {
    #expect(HeatPolicy.pauseCelsius == 40)
    #expect(HeatPolicy.resumeCelsius == 37)
}

@Test func aHotBatteryBelowTheStopLevelIsHeldOff() {
    let step = ChargeMachine.next(state(), input(70, temperature: 41))
    #expect(step.command == .inhibit)
    #expect(step.reason == .heatReached)
    #expect(step.state == paused)
    #expect(step.fullChargeEnded == nil)
}

@Test func theBoundariesBelongToTheHeatSide() {
    #expect(ChargeMachine.next(state(), input(70, temperature: 40)).command == .inhibit)
    #expect(ChargeMachine.next(state(), input(70, temperature: 39.9)).command == nil)
    #expect(ChargeMachine.next(paused, input(70, temperature: 37)).command == .allow)
    #expect(ChargeMachine.next(paused, input(70, temperature: 37.1)).command == nil)
}

@Test func theBandBetweenTheMarksKeepsTheLastState() {
    let held = ChargeMachine.next(paused, input(70, temperature: 38.5))
    #expect(held.command == nil)
    #expect(held.state == paused)
    let idle = ChargeMachine.next(state(), input(70, temperature: 38.5))
    #expect(idle.command == nil)
    #expect(idle.state == state())
}

@Test func aCooledBatteryIsAllowedAgain() {
    let step = ChargeMachine.next(paused, input(70, temperature: 36.9))
    #expect(step.command == .allow)
    #expect(step.reason == .cooledDown)
    #expect(step.state == state())
}

@Test func aTemperatureThatCannotBeUsedChangesNothing() {
    for bad in [nil, Double.nan, Double.infinity, -100, 400] as [Double?] {
        let hot = ChargeMachine.next(paused, input(70, temperature: bad))
        #expect(hot.command == nil)
        #expect(hot.state == paused)
        let idle = ChargeMachine.next(state(), input(70, temperature: bad))
        #expect(idle.command == nil)
        #expect(idle.state == state())
    }
}

@Test func flappingAroundFortyDegreesSendsExactlyOneInhibit() {
    var machine = state()
    var commands: [ChargeCommand] = []
    for temperature in [41.0, 39.0, 41.0, 38.0, 40.5, 39.5] {
        let step = ChargeMachine.next(machine, input(70, temperature: temperature))
        if let command = step.command { commands.append(command) }
        machine = step.state
    }
    #expect(commands == [.inhibit])
    #expect(machine == paused)
}

@Test func heatIsIgnoredWhenKombuchaIsNotManaging() {
    for notManaging in [input(70, temperature: 45, onAC: false),
                        input(70, temperature: 45, protection: false),
                        input(70, temperature: 45, manager: true)] {
        let step = ChargeMachine.next(state(), notManaging)
        #expect(step.command == nil)
        // The memory still follows the battery, so a later return finds the right state.
        #expect(step.state == state(heatHold: true))
    }
}

@Test func aHeldInhibitIsReleasedWhenTheAdapterGoesOutWhileHot() {
    let step = ChargeMachine.next(paused, input(70, temperature: 45, onAC: false))
    #expect(step.command == .allow)
    #expect(step.reason == .adapterOut)
    #expect(step.state == state(heatHold: true))
}

@Test func theAdapterComingBackWhileStillHotHoldsTheChargeAtOnce() {
    let unplugged = ChargeMachine.next(state(), input(70, temperature: 45, onAC: false)).state
    let step = ChargeMachine.next(unplugged, input(70, temperature: 44))
    #expect(step.command == .inhibit)
    #expect(step.reason == .heatReached)
}

@Test func theAdapterComingBackCoolFindsNothingHeld() {
    let unplugged = ChargeMachine.next(state(heatHold: true), input(70, temperature: 30, onAC: false)).state
    #expect(unplugged == state())
    let step = ChargeMachine.next(unplugged, input(70, temperature: 30))
    #expect(step.command == nil)
}

@Test func heatWinsOverARunningFullCharge() {
    let step = ChargeMachine.next(state(fullCharge: true), input(70, temperature: 42))
    #expect(step.command == .inhibit)
    #expect(step.reason == .heatReached)
    #expect(step.state == state(fullCharge: true, heatHold: true, heatInhibited: true))
    #expect(step.fullChargeEnded == nil)
}

@Test func aFullChargeContinuesWhenTheBatteryCools() {
    let step = ChargeMachine.next(state(fullCharge: true, heatHold: true, heatInhibited: true),
                                  input(70, temperature: 36))
    #expect(step.command == .allow)
    #expect(step.reason == .cooledDown)
    #expect(step.state == state(fullCharge: true))
}

@Test func aFullChargeThatReachesHundredWhileHotStillEndsAndTheHeatHoldStays() {
    let step = ChargeMachine.next(state(fullCharge: true, heatHold: true, heatInhibited: true),
                                  input(100, temperature: 42))
    #expect(step.fullChargeEnded == .reachedFull)
    #expect(step.command == nil)
    #expect(step.state == paused)
}

@Test func aStopThresholdInhibitIsKeptWhenTheBatteryGetsHot() {
    let step = ChargeMachine.next(state(inhibitedAt: 80), input(81, temperature: 42))
    #expect(step.command == nil)
    #expect(step.state == state(inhibitedAt: 80, heatHold: true))
}

@Test func coolingAtOrAboveTheStopLevelKeepsTheInhibitAsTheStopInhibit() {
    let step = ChargeMachine.next(paused, input(82, temperature: 36))
    #expect(step.command == nil)
    #expect(step.state == state(inhibitedAt: 80))
}

@Test func coolingInsideTheBandBelowStopReleases() {
    let step = ChargeMachine.next(paused, input(78, temperature: 30))
    #expect(step.command == .allow)
    #expect(step.reason == .cooledDown)
}

@Test func theStopThresholdStillWinsOverNothingHot() {
    let step = ChargeMachine.next(state(), input(80, temperature: 30))
    #expect(step.command == .inhibit)
    #expect(step.reason == .stopThresholdReached)
    #expect(step.state == state(inhibitedAt: 80))
}

@Test func aCommandThatDidNotLandKeepsTheChargerStateAndTheHeatMemory() {
    let planned = ChargeMachine.next(state(), input(70, temperature: 42)).state
    let kept = state().following(planned)
    #expect(kept == state(heatHold: true))
    // The next pass sees a hot battery with nothing held and sends the inhibit again.
    #expect(ChargeMachine.next(kept, input(70, temperature: 42)).command == .inhibit)
}
