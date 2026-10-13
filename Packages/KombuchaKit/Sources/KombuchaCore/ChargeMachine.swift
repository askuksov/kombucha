public enum ChargeCommand: Equatable, Sendable {
    case allow, inhibit
}

/// Why the machine or the planner sends a command.
public enum CommandReason: Equatable, Sendable {
    case stopThresholdReached
    case resumeThresholdReached
    case rangeWidened
    case externalBatteryManager
    case adapterOut
    case protectionOff
    case fullCharge
    /// The battery reached `HeatPolicy.pauseCelsius`.
    case heatReached
    /// The battery fell to `HeatPolicy.resumeCelsius` and the heat inhibit is released.
    case cooledDown
    /// A discharge holds the charge, so the battery does not charge the moment the adapter is back on.
    case discharging
    /// The planner's only reason: the command comes from the reassert alone.
    case reassert
}

public struct MachineState: Equatable, Sendable {
    /// The stop threshold in force when the inhibit was taken.
    public private(set) var inhibitedAt: Int?
    public private(set) var fullChargeActive: Bool
    /// Heat Protection's memory: set at `HeatPolicy.pauseCelsius`, cleared at `resumeCelsius`, kept in between.
    public private(set) var heatHold: Bool
    /// The inhibit now held was taken for heat, not for the stop threshold.
    public private(set) var heatInhibited: Bool
    /// A discharge on the adapter is wanted.
    public private(set) var dischargeActive: Bool
    /// The adapter may be switched off: an `enable` is owed until one lands.
    public private(set) var adapterDisabled: Bool

    public init() {
        self.init(inhibitedAt: nil, fullChargeActive: false)
    }

    init(inhibitedAt: Int?, fullChargeActive: Bool, heatHold: Bool = false, heatInhibited: Bool = false,
         dischargeActive: Bool = false, adapterDisabled: Bool = false) {
        self.inhibitedAt = inhibitedAt
        self.fullChargeActive = fullChargeActive
        self.heatHold = heatHold
        self.heatInhibited = heatInhibited
        self.dischargeActive = dischargeActive
        self.adapterDisabled = adapterDisabled
    }

    public var holdsInhibit: Bool { inhibitedAt != nil || heatInhibited }

    public func withFullCharge(_ active: Bool) -> MachineState {
        var next = self
        next.fullChargeActive = active
        return next
    }

    public func withDischarge(_ active: Bool) -> MachineState {
        var next = self
        next.dischargeActive = active
        return next
    }

    /// The adapter may be off with no discharge to show for it (found so at start): the next pass sends `enable`.
    public func owingAdapterEnable() -> MachineState {
        var next = self
        next.adapterDisabled = true
        return next
    }

    /// An `enable` landed outside a pass: nothing is owed and no discharge runs.
    public func adapterSwitchedOn() -> MachineState {
        var next = self
        next.dischargeActive = false
        next.adapterDisabled = false
        return next
    }

    /// An adapter command did not land or could not be sent: the discharge is over and an `enable` is owed.
    public func endingDischargeAfterFailure() -> MachineState {
        var next = self
        next.dischargeActive = false
        next.adapterDisabled = true
        return next
    }

    /// What a charge command that did not land changes: the charger keeps what it held, so the inhibit fields
    /// stay; everything else is bookkeeping that does not depend on that write and follows the plan.
    public func following(_ planned: MachineState) -> MachineState {
        var next = planned
        next.inhibitedAt = inhibitedAt
        next.heatInhibited = heatInhibited
        return next
    }

    /// The hysteresis of Heat Protection. A reading that is missing or not a battery temperature changes nothing.
    func updatingHeat(_ temperature: Double?) -> MachineState {
        guard let temperature, HeatPolicy.plausible.contains(temperature) else { return self }
        var next = self
        if temperature >= HeatPolicy.pauseCelsius {
            next.heatHold = true
        } else if temperature <= HeatPolicy.resumeCelsius {
            next.heatHold = false
        }
        return next
    }

    func holding(at threshold: Int) -> MachineState {
        var next = self
        next.inhibitedAt = threshold
        next.heatInhibited = false
        return next
    }

    func holdingForHeat(taken: Bool) -> MachineState {
        var next = self
        next.heatHold = true
        next.heatInhibited = taken || heatInhibited
        return next
    }

    /// A discharge takes the inhibit at Stop when nothing is held and keeps whatever is.
    func holdingForDischarge(at threshold: Int) -> MachineState {
        var next = self
        if !holdsInhibit { next.inhibitedAt = threshold }
        return next
    }

    func released() -> MachineState {
        var next = self
        next.inhibitedAt = nil
        next.heatInhibited = false
        return next
    }

    func withAdapterDisabled(_ disabled: Bool) -> MachineState {
        var next = self
        next.adapterDisabled = disabled
        return next
    }
}

public struct MachineInput: Equatable, Sendable {
    /// Not sanitized here: NaN fails every comparison and moves nothing by itself (it ends a discharge); ±∞
    /// compares and errs toward inhibit (+∞) or release (−∞).
    public var level: Double
    public var onAC: Bool
    public var protection: Bool
    public var lower: Int
    public var upper: Int
    public var externalBatteryManagerRunning: Bool
    /// Nil when the battery temperature could not be read.
    public var temperatureCelsius: Double?
    /// The adapter is connected, also while it is switched off. Without a reading it is `onAC`.
    public var adapterPresent: Bool
    /// The helper can switch the adapter now: write path ready, protocol 2 or later, the key on this Mac.
    public var adapterSwitchReady: Bool

    public init(level: Double, onAC: Bool, protection: Bool, lower: Int, upper: Int,
                externalBatteryManagerRunning: Bool, temperatureCelsius: Double? = nil,
                adapterPresent: Bool? = nil, adapterSwitchReady: Bool = true) {
        self.level = level
        self.onAC = onAC
        self.protection = protection
        self.lower = lower
        self.upper = upper
        self.externalBatteryManagerRunning = externalBatteryManagerRunning
        self.temperatureCelsius = temperatureCelsius
        self.adapterPresent = adapterPresent ?? onAC
        self.adapterSwitchReady = adapterSwitchReady
    }
}

public enum FullChargeEnding: Equatable, Sendable {
    case externalBatteryManager, unplugged, protectionOff, reachedFull
}

public struct Step: Equatable, Sendable {
    public var state: MachineState
    public var command: ChargeCommand?
    /// Set exactly when `command` is.
    public var reason: CommandReason?
    public var fullChargeEnded: FullChargeEnding?
    /// `enable` goes before the charge command, `disable` and `renew` after it.
    public var adapterCommand: AdapterCommand?
    public var dischargeEnded: DischargeEnding?

    init(state: MachineState, command: ChargeCommand?, reason: CommandReason?, fullChargeEnded: FullChargeEnding?,
         adapterCommand: AdapterCommand? = nil, dischargeEnded: DischargeEnding? = nil) {
        self.state = state
        self.command = command
        self.reason = reason
        self.fullChargeEnded = fullChargeEnded
        self.adapterCommand = adapterCommand
        self.dischargeEnded = dischargeEnded
    }
}

public enum ChargeMachine {
    public static func next(_ state: MachineState, _ input: MachineInput) -> Step {
        // The heat memory follows the battery on every pass, also while Kombucha is not managing.
        var state = state.updatingHeat(input.temperatureCelsius)
        var input = input
        // While the adapter may be switched off the power source says battery; the cable decides instead, also
        // for the rules that run after a discharge ended in this pass.
        if state.dischargeActive || state.adapterDisabled { input.onAC = input.adapterPresent }

        let dischargeEnded = dischargeEnding(state, input)
        if dischargeEnded != nil { state = state.withDischarge(false) }
        let adapterCommand: AdapterCommand?
        if state.dischargeActive {
            adapterCommand = state.adapterDisabled
                ? .renew(leaseSeconds: DischargePolicy.leaseSeconds)
                : .disable(leaseSeconds: DischargePolicy.leaseSeconds)
            state = state.withAdapterDisabled(true)
        } else if state.adapterDisabled {
            // Every ending, and an adapter found off, puts it back on before anything else.
            adapterCommand = .enable
            state = state.withAdapterDisabled(false)
        } else {
            adapterCommand = nil
        }

        let ended = ending(state, input)
        if ended != nil {
            state = state.withFullCharge(false)
        }

        func step(_ next: MachineState, _ command: ChargeCommand?, _ reason: CommandReason?) -> Step {
            Step(state: next, command: command, reason: reason, fullChargeEnded: ended,
                 adapterCommand: adapterCommand, dischargeEnded: dischargeEnded)
        }

        func inhibit(at threshold: Int) -> Step {
            let sends = !state.holdsInhibit
            return step(state.holding(at: threshold), sends ? .inhibit : nil, sends ? .stopThresholdReached : nil)
        }

        func holdForHeat() -> Step {
            let sends = !state.holdsInhibit
            return step(state.holdingForHeat(taken: sends), sends ? .inhibit : nil, sends ? .heatReached : nil)
        }

        func release(_ reason: CommandReason) -> Step {
            guard state.holdsInhibit else { return step(state, nil, nil) }
            return step(state.released(), .allow, reason)
        }

        if state.dischargeActive {
            // The charge stays held, so the battery does not charge the moment the adapter is back on.
            let sends = !state.holdsInhibit
            return step(state.holdingForDischarge(at: input.upper), sends ? .inhibit : nil, sends ? .discharging : nil)
        }
        if let notManaging = notManaging(input) { return release(notManaging) }
        // Heat is decided before a running full charge: heat wins.
        if state.heatHold { return holdForHeat() }
        // The heat is over. A heat inhibit is released unless the level calls for the stop-threshold inhibit.
        if state.heatInhibited, state.fullChargeActive || input.level < Double(input.upper) { return release(.cooledDown) }
        if state.fullChargeActive { return release(.fullCharge) }
        // The stop threshold is tested first, so a broken pair errs toward not overcharging.
        if input.level >= Double(input.upper) { return inhibit(at: input.upper) }
        if input.level <= Double(input.lower) { return release(.resumeThresholdReached) }
        if let held = state.inhibitedAt, input.upper > held, input.level < Double(input.upper) { return release(.rangeWidened) }
        return step(state, nil, nil)
    }

    private static func ending(_ state: MachineState, _ input: MachineInput) -> FullChargeEnding? {
        guard state.fullChargeActive else { return nil }
        if input.externalBatteryManagerRunning { return .externalBatteryManager }
        if !input.onAC { return .unplugged }
        if !input.protection { return .protectionOff }
        if input.level >= 100 { return .reachedFull }
        return nil
    }

    /// The first ending that holds, in this order; nil when no discharge runs or it goes on.
    private static func dischargeEnding(_ state: MachineState, _ input: MachineInput) -> DischargeEnding? {
        guard state.dischargeActive else { return nil }
        if input.externalBatteryManagerRunning { return .externalBatteryManager }
        if !input.adapterPresent { return .unplugged }
        if !input.protection { return .protectionOff }
        if state.fullChargeActive { return .fullCharge }
        if !input.adapterSwitchReady { return .blocked }
        // Written so that a NaN level ends it too.
        if !(input.level > Double(input.upper)) { return .reachedStop }
        return nil
    }

    /// Kombucha steps back. A running full charge is not part of this any more: it is decided after the heat.
    private static func notManaging(_ input: MachineInput) -> CommandReason? {
        if input.externalBatteryManagerRunning { return .externalBatteryManager }
        if !input.onAC { return .adapterOut }
        if !input.protection { return .protectionOff }
        return nil
    }
}
