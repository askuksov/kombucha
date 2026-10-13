/// One process's cumulative energy, as `proc_pid_rusage` reports it.
public struct EnergySample: Equatable, Sendable {
    public let pid: Int32
    public let executablePath: String
    public let energyNanojoules: UInt64

    public init(pid: Int32, executablePath: String, energyNanojoules: UInt64) {
        self.pid = pid
        self.executablePath = executablePath
        self.energyNanojoules = energyNanojoules
    }
}

/// Every readable process at one moment. `seconds` is a monotonic clock reading, so two readings give the
/// interval between them.
public struct EnergyReading: Equatable, Sendable {
    public let samples: [EnergySample]
    public let seconds: Double

    public init(samples: [EnergySample], seconds: Double) {
        self.samples = samples
        self.seconds = seconds
    }
}

public struct AppEnergy: Equatable, Sendable {
    public let name: String
    public let watts: Double

    public init(name: String, watts: Double) {
        self.name = name
        self.watts = watts
    }
}

public enum EnergyRanking {
    /// An app below this is idle for a person's purposes: under 0.05 W a one-decimal display would print 0.0 W.
    private static let floorWatts = 0.05

    /// System executables are not "apps you run"; leaving them out keeps the Battery tab footer true.
    /// `/System/Applications/` and `/usr/bin/` are deliberately not listed: Mail, Notes and `yes` are user-run.
    private static let systemPrefixes = [
        "/System/Library/", "/System/Volumes/Preboot/Cryptexes/OS/", "/usr/libexec/", "/usr/sbin/", "/sbin/",
    ]

    public static func top(_ count: Int, previous: EnergyReading, current: EnergyReading) -> [AppEnergy] {
        let interval = current.seconds - previous.seconds
        guard count > 0, interval > 0 else { return [] }
        let before = Dictionary(previous.samples.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
        var byApp: [String: Double] = [:]
        for sample in current.samples {
            // A pid that now runs another program, or a counter that went backwards, has no honest delta.
            guard let old = before[sample.pid], old.executablePath == sample.executablePath,
                  sample.energyNanojoules >= old.energyNanojoules,
                  !systemPrefixes.contains(where: sample.executablePath.hasPrefix),
                  let name = appName(of: sample.executablePath) else { continue }
            byApp[name, default: 0] += Double(sample.energyNanojoules - old.energyNanojoules) / 1e9 / interval
        }
        let ranked = byApp
            .filter { $0.value >= floorWatts }
            .map { AppEnergy(name: $0.key, watts: $0.value) }
            .sorted { $0.watts != $1.watts ? $0.watts > $1.watts : $0.name < $1.name }
        return Array(ranked.prefix(count))
    }

    /// The first `*.app` component without its suffix, so a browser's helpers count as the browser; a path with
    /// no such component is named by its last component. Nil for a path with no name at all.
    public static func appName(of path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if let bundle = parts.first(where: { $0.hasSuffix(".app") && $0.count > 4 }) {
            return String(bundle.dropLast(4))
        }
        return parts.last.map(String.init)
    }
}
