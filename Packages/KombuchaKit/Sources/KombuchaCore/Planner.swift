public struct PowerReading: Equatable, Sendable {
    public var level: Double
    public var onAC: Bool
    public var charging: Bool
    /// The battery cell temperature in °C when the registry gave one; Heat Protection's only input.
    public var temperatureCelsius: Double?
    /// Whether an adapter is connected, also while Kombucha has it switched off; nil when the registry gave no answer.
    public var adapterPresent: Bool?

    public init(level: Double, onAC: Bool, charging: Bool, temperatureCelsius: Double? = nil, adapterPresent: Bool? = nil) {
        self.level = level
        self.onAC = onAC
        self.charging = charging
        self.temperatureCelsius = temperatureCelsius
        self.adapterPresent = adapterPresent
    }
}

public struct ChargeSettings: Equatable, Sendable {
    public var thresholds: Thresholds
    public var protection: Bool

    public init(thresholds: Thresholds, protection: Bool) {
        self.thresholds = thresholds
        self.protection = protection
    }
}

public struct Plan: Equatable, Sendable {
    public var step: Step
    public var command: ChargeCommand?
    /// The machine's reason when it sends; `.reassert` when only the reassert does.
    public var reason: CommandReason?
    public var snapshot: ChargeSnapshot

    init(step: Step, command: ChargeCommand?, reason: CommandReason?, snapshot: ChargeSnapshot) {
        self.step = step
        self.command = command
        self.reason = reason
        self.snapshot = snapshot
    }
}

public enum Planner {
    /// The snapshot carries `.unknown`; the engine attaches the write path and the discharge after the commands.
    public static func plan(state: MachineState,
                            reading: PowerReading,
                            settings: ChargeSettings,
                            reassert: Bool,
                            externalBatteryManager: ExternalBatteryManager?,
                            adapterSwitchReady: Bool = true) -> Plan {
        let input = MachineInput(level: reading.level,
                                 onAC: reading.onAC,
                                 protection: settings.protection,
                                 lower: settings.thresholds.lower,
                                 upper: settings.thresholds.upper,
                                 externalBatteryManagerRunning: externalBatteryManager != nil,
                                 temperatureCelsius: reading.temperatureCelsius,
                                 adapterPresent: reading.adapterPresent,
                                 adapterSwitchReady: adapterSwitchReady)
        let step = ChargeMachine.next(state, input)
        // As in the machine: while the adapter may be switched off, the cable says whether Kombucha is on AC.
        let onAC = state.dischargeActive || state.adapterDisabled ? input.adapterPresent : reading.onAC
        let command: ChargeCommand?
        let reason: CommandReason?
        if step.command != nil {
            // A reassert here would send the same command: it follows `holdsInhibit` after the step.
            command = step.command
            reason = step.reason
        } else if reassert, onAC, settings.protection, externalBatteryManager == nil {
            command = step.state.holdsInhibit ? .inhibit : .allow
            reason = .reassert
        } else {
            command = nil
            reason = nil
        }
        let snapshot = ChargeSnapshot(level: reading.level,
                                      onAC: onAC,
                                      charging: reading.charging,
                                      thresholds: settings.thresholds,
                                      protection: settings.protection,
                                      fullChargeActive: step.state.fullChargeActive,
                                      writePath: .unknown,
                                      externalBatteryManager: externalBatteryManager,
                                      heatHold: step.state.heatHold,
                                      dischargeActive: step.state.dischargeActive)
        return Plan(step: step, command: command, reason: reason, snapshot: snapshot)
    }
}
