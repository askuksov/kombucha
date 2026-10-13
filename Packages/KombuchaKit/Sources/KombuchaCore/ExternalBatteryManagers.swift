public enum ExternalBatteryManager: Equatable, CaseIterable, Sendable {
    case battOpt, alDente, batFi, batt, kombuchaFloat

    public var displayName: String {
        switch self {
        case .battOpt: "BattOpt"
        case .alDente: "AlDente"
        case .batFi: "BatFi"
        case .batt: "batt"
        case .kombuchaFloat: "Kombucha Float"
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
        // The app only: its helper writes nothing on its own and outlives the app.
        ExternalBatteryManagerRow(externalBatteryManager: .kombuchaFloat, identities: [
            .fileName("kombucha-float"),
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
