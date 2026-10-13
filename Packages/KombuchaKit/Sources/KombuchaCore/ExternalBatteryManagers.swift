public enum ExternalBatteryManager: Equatable, CaseIterable, Sendable {
    case battOpt, alDente, batFi, batt, juicy, energiza, batteryToolkit

    public var displayName: String {
        switch self {
        case .battOpt: "BattOpt"
        case .alDente: "AlDente"
        case .batFi: "BatFi"
        case .batt: "batt"
        case .juicy: "Juicy"
        case .energiza: "Energiza"
        case .batteryToolkit: "Battery Toolkit"
        }
    }
}

public enum ProcessIdentity: Equatable, Sendable {
    /// The executable path equals the identity.
    case executable(String)
    /// The executable path starts with the identity followed by `/Contents/`.
    case bundle(String)
    /// The last path component equals the identity.
    case fileName(String)
}

public struct ExternalBatteryManagerRow: Sendable {
    public let externalBatteryManager: ExternalBatteryManager
    public let identities: [ProcessIdentity]

    init(externalBatteryManager: ExternalBatteryManager, identities: [ProcessIdentity]) {
        self.externalBatteryManager = externalBatteryManager
        self.identities = identities
    }
}

public enum ExternalBatteryManagers {
    /// A row is added only with evidence: a measured path, a Homebrew cask or formula, or a source repository.
    public static let table: [ExternalBatteryManagerRow] = [
        ExternalBatteryManagerRow(externalBatteryManager: .battOpt, identities: [
            .bundle("/Applications/BattOpt.app"),
            .executable("/Library/Application Support/battopt/battopt"),
        ]),
        ExternalBatteryManagerRow(externalBatteryManager: .alDente, identities: [
            .bundle("/Applications/AlDente.app"),
            .executable("/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper"),
        ]),
        ExternalBatteryManagerRow(externalBatteryManager: .batFi, identities: [
            .bundle("/Applications/BatFi.app"),
        ]),
        ExternalBatteryManagerRow(externalBatteryManager: .batt, identities: [
            .fileName("batt"),
        ]),
        // Homebrew cask `juicy`.
        ExternalBatteryManagerRow(externalBatteryManager: .juicy, identities: [
            .bundle("/Applications/Juicy.app"),
        ]),
        // Homebrew cask `energiza`.
        ExternalBatteryManagerRow(externalBatteryManager: .energiza, identities: [
            .bundle("/Applications/Energiza.app"),
        ]),
        // Homebrew cask `battery-toolkit` (tap mhaeuser/mhaeuser), source repository mhaeuser/Battery-Toolkit.
        ExternalBatteryManagerRow(externalBatteryManager: .batteryToolkit, identities: [
            .bundle("/Applications/Battery Toolkit.app"),
        ]),
    ]

    public static func verdict(executablePaths: [String],
                               ownBundlePath: String,
                               table: [ExternalBatteryManagerRow]) -> ExternalBatteryManager? {
        let own = ownBundlePath + "/Contents/"
        let paths = executablePaths.filter { !$0.hasPrefix(own) }
        for row in table where row.identities.contains(where: { identity in paths.contains(where: identity.matches) }) {
            return row.externalBatteryManager
        }
        return nil
    }
}

extension ProcessIdentity {
    func matches(_ path: String) -> Bool {
        switch self {
        case .executable(let value): path == value
        case .bundle(let value): path.hasPrefix(value + "/Contents/")
        case .fileName(let value): path.split(separator: "/").last.map(String.init) == value
        }
    }
}
