public enum Mode: Equatable, Sendable {
    case protected, charging, fullCharge, protectionOff, onBattery, heatPaused, discharging

    /// A discharge comes right after "no adapter": while it runs nothing else is true of the battery. Heat
    /// Protection holds the charge while the battery is hot and Battery Protection is on; it outranks a running
    /// full charge and says nothing when there is no adapter or no protection.
    public static func derive(onAC: Bool, charging: Bool, protection: Bool, fullChargeActive: Bool,
                              heatHold: Bool = false, dischargeActive: Bool = false) -> Mode {
        if !onAC { return .onBattery }
        if dischargeActive { return .discharging }
        if heatHold, protection { return .heatPaused }
        if fullChargeActive { return .fullCharge }
        if !protection { return .protectionOff }
        return charging ? .charging : .protected
    }
}
