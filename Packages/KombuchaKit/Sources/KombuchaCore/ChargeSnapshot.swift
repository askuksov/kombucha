/// What the UI and the notifications read. A producer that forgets the verdict shows the
/// blocked state, never protection.
public struct ChargeSnapshot: Equatable, Sendable {
    public let level: Double
    /// While the adapter may be switched off, whether the cable is in.
    public let onAC: Bool
    /// The battery's own "Is Charging", not Kombucha's intent.
    public let charging: Bool
    public let thresholds: Thresholds
    public let protection: Bool
    public let fullChargeActive: Bool
    public let writePath: WritePath
    public let externalBatteryManager: ExternalBatteryManager?
    /// Heat Protection's hold is in force (the machine's `heatHold`).
    public let heatHold: Bool
    /// A discharge on the adapter runs, after the pass's adapter commands.
    public let dischargeActive: Bool
    /// The helper can switch the adapter on this Mac and the cable can be read. Attached by the engine.
    public let adapterSwitchAvailable: Bool

    public init(level: Double,
                onAC: Bool,
                charging: Bool,
                thresholds: Thresholds,
                protection: Bool,
                fullChargeActive: Bool,
                writePath: WritePath = .unknown,
                externalBatteryManager: ExternalBatteryManager? = nil,
                heatHold: Bool = false,
                dischargeActive: Bool = false,
                adapterSwitchAvailable: Bool = false) {
        self.level = level.isFinite ? min(max(level, 0), 100) : 0
        self.onAC = onAC
        self.charging = charging
        self.thresholds = thresholds
        self.protection = protection
        self.fullChargeActive = fullChargeActive
        self.writePath = writePath
        self.externalBatteryManager = externalBatteryManager
        self.heatHold = heatHold
        self.dischargeActive = dischargeActive
        self.adapterSwitchAvailable = adapterSwitchAvailable
    }

    public var mode: Mode {
        Mode.derive(onAC: onAC, charging: charging, protection: protection, fullChargeActive: fullChargeActive,
                    heatHold: heatHold, dischargeActive: dischargeActive)
    }

    public var mayManage: Bool { writePath == .ready && externalBatteryManager == nil }

    public var displayLevel: Int { Int(level.rounded()) }

    public func withWritePath(_ path: WritePath) -> ChargeSnapshot {
        copy(writePath: path, dischargeActive: dischargeActive, adapterSwitchAvailable: adapterSwitchAvailable)
    }

    /// The engine's word after the pass's commands: a discharge whose `disable` did not land is not running.
    public func withDischarge(_ active: Bool, adapterSwitchAvailable available: Bool) -> ChargeSnapshot {
        copy(writePath: writePath, dischargeActive: active, adapterSwitchAvailable: available)
    }

    private func copy(writePath: WritePath, dischargeActive: Bool, adapterSwitchAvailable: Bool) -> ChargeSnapshot {
        ChargeSnapshot(level: level,
                       onAC: onAC,
                       charging: charging,
                       thresholds: thresholds,
                       protection: protection,
                       fullChargeActive: fullChargeActive,
                       writePath: writePath,
                       externalBatteryManager: externalBatteryManager,
                       heatHold: heatHold,
                       dischargeActive: dischargeActive,
                       adapterSwitchAvailable: adapterSwitchAvailable)
    }
}
