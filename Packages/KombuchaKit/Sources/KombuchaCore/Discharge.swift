/// What the engine asks of the adapter switch. An intent: the helper decides the key and the byte.
public enum AdapterCommand: Equatable, Sendable {
    /// Switch the adapter off and arm the helper's lease.
    case disable(leaseSeconds: Int)
    /// Keep it off: the same request again, which restarts the lease.
    case renew(leaseSeconds: Int)
    case enable

    /// The first of the two values the helper's `setAdapter` takes.
    public var enabled: Bool {
        if case .enable = self { return true }
        return false
    }

    public var leaseSeconds: Int {
        switch self {
        case .disable(let seconds), .renew(let seconds): seconds
        case .enable: 0
        }
    }
}

/// Why a discharge ended. The machine decides all but stopped, sleep and shutdown; those are the engine's.
public enum DischargeEnding: Equatable, Sendable {
    case reachedStop, unplugged, protectionOff, fullCharge, externalBatteryManager, stopped, sleep, shutdown, blocked
}

public enum DischargePolicy {
    /// The helper switches the adapter back on unless a pass renews within this time.
    public static let leaseSeconds = 180
}

/// Why a discharge may not start now.
public enum DischargeRefusal: Equatable, Sendable {
    case noReading, gateClosed, adapterSwitchUnavailable, protectionOff, adapterAbsent, fullChargeActive, notAboveStop
}

public enum DischargeStart {
    /// Nil when a discharge may start. The panel shows the button exactly then; the engine checks again.
    public static func refusal(_ snapshot: ChargeSnapshot?) -> DischargeRefusal? {
        guard let snapshot else { return .noReading }
        if !snapshot.mayManage { return .gateClosed }
        if !snapshot.adapterSwitchAvailable { return .adapterSwitchUnavailable }
        if !snapshot.protection { return .protectionOff }
        if !snapshot.onAC { return .adapterAbsent }
        if snapshot.fullChargeActive { return .fullChargeActive }
        if snapshot.displayLevel <= snapshot.thresholds.upper { return .notAboveStop }
        return nil
    }
}
