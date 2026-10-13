import Testing
@testable import KombuchaCore

/// On the adapter while it is switched off: the power source says battery, the cable is in.
private func input(_ level: Double,
                   onAC: Bool = false,
                   adapterPresent: Bool? = true,
                   protection: Bool = true,
                   upper: Int = 80,
                   manager: Bool = false,
                   switchReady: Bool = true,
                   temperature: Double? = nil) -> MachineInput {
    MachineInput(level: level, onAC: onAC, protection: protection, lower: 75, upper: upper,
                 externalBatteryManagerRunning: manager, temperatureCelsius: temperature,
                 adapterPresent: adapterPresent, adapterSwitchReady: switchReady)
}

/// A discharge that has switched the adapter off and holds the charge at 80.
private func discharging(fullCharge: Bool = false) -> MachineState {
    MachineState(inhibitedAt: 80, fullChargeActive: fullCharge, dischargeActive: true, adapterDisabled: true)
}

/// What an ending at or above Stop leaves: the charge held at 80, the adapter on.
private let restingAtStop = MachineState(inhibitedAt: 80, fullChargeActive: false)

private let lease = DischargePolicy.leaseSeconds

@Test func theLeaseIsThreeMinutes() {
    #expect(DischargePolicy.leaseSeconds == 180)
    #expect(AdapterCommand.disable(leaseSeconds: 180).leaseSeconds == 180)
    #expect(!AdapterCommand.renew(leaseSeconds: 180).enabled)
    #expect(AdapterCommand.enable.enabled)
    #expect(AdapterCommand.enable.leaseSeconds == 0)
}

@Test func aDischargeSwitchesTheAdapterOffAndTakesTheInhibit() {
    let step = ChargeMachine.next(MachineState().withDischarge(true), input(94, onAC: true))
    #expect(step.adapterCommand == .disable(leaseSeconds: lease))
    #expect(step.command == .inhibit)
    #expect(step.reason == .discharging)
    #expect(step.state == discharging())
    #expect(step.dischargeEnded == nil)
}

@Test func anInhibitAlreadyHeldIsKeptWithoutACommand() {
    let start = MachineState(inhibitedAt: 80, fullChargeActive: false).withDischarge(true)
    let step = ChargeMachine.next(start, input(94, onAC: true))
    #expect(step.adapterCommand == .disable(leaseSeconds: lease))
    #expect(step.command == nil)
    #expect(step.state == discharging())
}

@Test func everyLaterPassRenewsTheLease() {
    let step = ChargeMachine.next(discharging(), input(90))
    #expect(step.adapterCommand == .renew(leaseSeconds: lease))
    #expect(step.command == nil)
    #expect(step.state == discharging())
}

@Test func theAdapterNotThePowerSourceSaysOnAC() {
    // Read from the power source, this would release the charge for "adapter out".
    let step = ChargeMachine.next(discharging(), input(90, onAC: false, adapterPresent: true))
    #expect(step.command == nil)
    #expect(step.dischargeEnded == nil)
}

@Test func reachingStopEndsTheDischargeAndKeepsTheInhibit() {
    let step = ChargeMachine.next(discharging(), input(80))
    #expect(step.dischargeEnded == .reachedStop)
    #expect(step.adapterCommand == .enable)
    #expect(step.command == nil)
    #expect(step.state == restingAtStop)
}

@Test func aLevelThatSkippedPastStopStillEndsAndRestsHeld() {
    let step = ChargeMachine.next(discharging(), input(79.4))
    #expect(step.dischargeEnded == .reachedStop)
    #expect(step.command == nil)
    #expect(step.state == restingAtStop)
}

@Test func aNaNLevelEndsTheDischarge() {
    let step = ChargeMachine.next(discharging(), input(.nan))
    #expect(step.dischargeEnded == .reachedStop)
    #expect(step.adapterCommand == .enable)
}

@Test func aDischargeStartedAtStopEndsBeforeItSwitchesAnything() {
    let step = ChargeMachine.next(MachineState().withDischarge(true), input(80, onAC: true))
    #expect(step.dischargeEnded == .reachedStop)
    #expect(step.adapterCommand == nil)
    #expect(step.command == .inhibit)
    #expect(step.reason == .stopThresholdReached)
    #expect(step.state == restingAtStop)
}

@Test func pullingTheCableEndsItAndReleasesTheCharge() {
    let step = ChargeMachine.next(discharging(), input(85, adapterPresent: false))
    #expect(step.dischargeEnded == .unplugged)
    #expect(step.adapterCommand == .enable)
    #expect(step.command == .allow)
    #expect(step.reason == .adapterOut)
    #expect(step.state == MachineState())
}

@Test func anAdapterThatCannotBeReadCountsAsPulled() {
    let step = ChargeMachine.next(discharging(), input(85, onAC: false, adapterPresent: nil))
    #expect(step.dischargeEnded == .unplugged)
    #expect(step.adapterCommand == .enable)
}

@Test func protectionOffEndsItAndHandsTheChargerBack() {
    let step = ChargeMachine.next(discharging(), input(85, protection: false))
    #expect(step.dischargeEnded == .protectionOff)
    #expect(step.adapterCommand == .enable)
    #expect(step.command == .allow)
    #expect(step.reason == .protectionOff)
}

@Test func aFullChargeEndsItAndStartsAtOnce() {
    let step = ChargeMachine.next(discharging(fullCharge: true), input(85))
    #expect(step.dischargeEnded == .fullCharge)
    #expect(step.adapterCommand == .enable)
    #expect(step.command == .allow)
    #expect(step.reason == .fullCharge)
    #expect(step.state == MachineState().withFullCharge(true))
}

@Test func anExternalBatteryManagerEndsItAndKombuchaStepsBack() {
    let step = ChargeMachine.next(discharging(), input(85, manager: true))
    #expect(step.dischargeEnded == .externalBatteryManager)
    #expect(step.adapterCommand == .enable)
    #expect(step.command == .allow)
    #expect(step.reason == .externalBatteryManager)
}

@Test func aSwitchThatCannotBeReachedEndsIt() {
    let step = ChargeMachine.next(discharging(), input(85, switchReady: false))
    #expect(step.dischargeEnded == .blocked)
    #expect(step.adapterCommand == .enable)
}

@Test func theFirstEndingThatHoldsIsReported() {
    #expect(ChargeMachine.next(discharging(), input(70, adapterPresent: false, manager: true)).dischargeEnded == .externalBatteryManager)
    #expect(ChargeMachine.next(discharging(), input(70, adapterPresent: false, protection: false)).dischargeEnded == .unplugged)
    #expect(ChargeMachine.next(discharging(fullCharge: true), input(70, protection: false)).dischargeEnded == .protectionOff)
    #expect(ChargeMachine.next(discharging(fullCharge: true), input(70, switchReady: false)).dischargeEnded == .fullCharge)
    #expect(ChargeMachine.next(discharging(), input(70, switchReady: false)).dischargeEnded == .blocked)
}

@Test func anOwedEnableIsSentWhateverElseHolds() {
    for owing in [input(78, onAC: true), input(78, adapterPresent: false), input(78, protection: false),
                  input(78, manager: true), input(78, switchReady: false)] {
        let step = ChargeMachine.next(MachineState().owingAdapterEnable(), owing)
        #expect(step.adapterCommand == .enable)
        #expect(step.dischargeEnded == nil)
        #expect(!step.state.adapterDisabled)
    }
}

@Test func anAdapterFoundOffAtStartReadsOnACFromTheCable() {
    // The power source says battery because the adapter is off; the stop threshold still holds the charge.
    let step = ChargeMachine.next(MachineState().owingAdapterEnable(), input(85))
    #expect(step.adapterCommand == .enable)
    #expect(step.command == .inhibit)
    #expect(step.reason == .stopThresholdReached)
}

@Test func aReplugBetweenTwoPassesKeepsTheDischarge() {
    // The power source may say AC for a moment after a replug; the renew switches the adapter off again.
    let step = ChargeMachine.next(discharging(), input(90, onAC: true, adapterPresent: true))
    #expect(step.dischargeEnded == nil)
    #expect(step.adapterCommand == .renew(leaseSeconds: lease))
    #expect(step.command == nil)
}

@Test func heatDuringADischargeOnlyMovesTheMemory() {
    let step = ChargeMachine.next(discharging(), input(90, temperature: 45))
    #expect(step.command == nil)
    #expect(step.adapterCommand == .renew(leaseSeconds: lease))
    #expect(step.state.heatHold)
    #expect(step.state.dischargeActive)
}

@Test func anAdapterCommandThatDidNotLandEndsTheDischargeAndOwesAnEnable() {
    let failed = discharging().endingDischargeAfterFailure()
    #expect(!failed.dischargeActive)
    #expect(failed.adapterDisabled)
    #expect(failed.inhibitedAt == 80)
    let next = ChargeMachine.next(failed, input(85))
    #expect(next.adapterCommand == .enable)
    #expect(next.command == nil)
    #expect(next.dischargeEnded == nil)
}

@Test func anEnableThatLandedOutsideAPassOwesNothing() {
    let state = discharging().adapterSwitchedOn()
    #expect(!state.dischargeActive)
    #expect(!state.adapterDisabled)
    #expect(state.inhibitedAt == 80)
}

@Test func aChargeCommandThatDidNotLandLeavesTheDischargeToThePlan() {
    let planned = ChargeMachine.next(MachineState().withDischarge(true), input(94, onAC: true)).state
    let kept = MachineState().withDischarge(true).following(planned)
    #expect(kept.dischargeActive)
    #expect(kept.adapterDisabled)
    #expect(kept.inhibitedAt == nil)
}

@Test func withoutADischargeTheAdapterInputsChangeNoStep() {
    for level in stride(from: 70.0, through: 90.0, by: 0.5) {
        for onAC in [true, false] {
            for protection in [true, false] {
                for manager in [true, false] {
                    for held in [nil, 80] as [Int?] {
                        let before = MachineState(inhibitedAt: held, fullChargeActive: false)
                        let plain = MachineInput(level: level, onAC: onAC, protection: protection, lower: 75, upper: 80,
                                                 externalBatteryManagerRunning: manager)
                        let plainStep = ChargeMachine.next(before, plain)
                        #expect(plainStep.adapterCommand == nil)
                        #expect(plainStep.dischargeEnded == nil)
                        for present in [true, false] {
                            for ready in [true, false] {
                                var other = plain
                                other.adapterPresent = present
                                other.adapterSwitchReady = ready
                                #expect(ChargeMachine.next(before, other) == plainStep)
                            }
                        }
                    }
                }
            }
        }
    }
}
