import AppIntents
import KombuchaCore

/// What Get Battery Status hands to Shortcuts. Labels reuse the panel's words where it has them.
struct BatteryStatusEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Battery Status"

    @Property(title: "Level") var level: Int
    @Property(title: "Mode") var mode: BatteryModeOption
    @Property(title: "Stop charging at") var stopAt: Int
    @Property(title: "Resume charging at") var resumeAt: Int
    @Property(title: "Battery Protection") var protection: Bool
    @Property(title: "Holding the limit") var holdingLimit: Bool

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Battery at \(level)%") }

    init() {}

    init(_ status: BatteryStatus) {
        level = status.level
        mode = BatteryModeOption(status.mode)
        stopAt = status.thresholds.upper
        resumeAt = status.thresholds.lower
        protection = status.protection
        holdingLimit = status.holdingLimit
    }
}

/// The pair Set Charge Limit stored, after normalization.
struct ChargeLimitEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Charge Limit"

    @Property(title: "Stop charging at") var stopAt: Int
    @Property(title: "Resume charging at") var resumeAt: Int

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(resumeAt)–\(stopAt)%") }

    init() {}

    init(_ pair: Thresholds) {
        stopAt = pair.upper
        resumeAt = pair.lower
    }
}

/// One case per mode, so an automation can branch on it without matching a sentence. The names are the
/// status lines' first words.
enum BatteryModeOption: String, AppEnum {
    case protected, charging, fullCharge, protectionOff, onBattery, heatPaused, discharging

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"
    static let caseDisplayRepresentations: [BatteryModeOption: DisplayRepresentation] = [
        .protected: "Protected",
        .charging: "Charging",
        .fullCharge: "Charging to 100%",
        .protectionOff: "Protection off",
        .onBattery: "On battery",
        .heatPaused: "Charging paused",
        .discharging: "Discharging",
    ]

    init(_ mode: Mode) {
        switch mode {
        case .protected: self = .protected
        case .charging: self = .charging
        case .fullCharge: self = .fullCharge
        case .protectionOff: self = .protectionOff
        case .onBattery: self = .onBattery
        case .heatPaused: self = .heatPaused
        case .discharging: self = .discharging
        }
    }
}
