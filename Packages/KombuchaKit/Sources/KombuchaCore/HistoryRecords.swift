import Foundation

/// One moment of the battery as the history keeps it.
public struct HistoryPoint: Equatable, Sendable {
    public let time: Date
    /// A whole percent: the history compares and draws whole percents only.
    public let level: Int
    public let onAC: Bool
    public let charging: Bool
    /// Battery Rest: on the adapter, protection on, Kombucha is holding the charger off.
    public let resting: Bool
    public let temperatureCelsius: Double?

    public init(time: Date, level: Int, onAC: Bool, charging: Bool, resting: Bool, temperatureCelsius: Double?) {
        self.time = time
        self.level = min(max(level, 0), 100)
        self.onAC = onAC
        self.charging = charging
        self.resting = resting
        self.temperatureCelsius = temperatureCelsius
    }

    public init(snapshot: ChargeSnapshot, temperatureCelsius: Double?, at time: Date) {
        self.init(time: time,
                  level: snapshot.displayLevel,
                  onAC: snapshot.onAC,
                  // The battery's flag can lag behind the adapter being switched off.
                  charging: snapshot.charging && !snapshot.dischargeActive,
                  resting: snapshot.mode == .protected && snapshot.mayManage,
                  temperatureCelsius: temperatureCelsius.flatMap { HistoryPoint.rounded($0) })
    }

    /// The nearest half degree; a value that is not a plausible battery temperature is dropped.
    public static func rounded(_ celsius: Double) -> Double? {
        guard celsius.isFinite, (-40.0...150.0).contains(celsius) else { return nil }
        return (celsius * 2).rounded() / 2
    }

    /// Everything but the time: the cursor writes a point only when this differs from the last one.
    func sameState(as other: HistoryPoint) -> Bool {
        level == other.level && onAC == other.onAC && charging == other.charging
            && resting == other.resting && temperatureCelsius == other.temperatureCelsius
    }
}

/// The battery's capacity on one local day.
public struct HealthPoint: Equatable, Sendable {
    /// The start of the local day.
    public let day: Date
    public let maximumCapacityPercent: Int
    public let cycleCount: Int

    public init(day: Date, maximumCapacityPercent: Int, cycleCount: Int) {
        self.day = day
        self.maximumCapacityPercent = maximumCapacityPercent
        self.cycleCount = cycleCount
    }
}

/// One line of the history file.
public enum HistoryRecord: Equatable, Sendable {
    case point(HistoryPoint)
    case health(HealthPoint)
    /// The capacity the health alert compares with.
    case baseline(Int)
}

extension HistoryRecord: Codable {
    private enum Key: String, CodingKey {
        case kind = "k", time = "t", level = "l", onAC = "ac", charging = "ch", resting = "rs", temperature = "tc"
        case day = "d", capacity = "mc", cycles = "cy", baseline = "v"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "p":
            let seconds = try container.decode(Double.self, forKey: .time)
            self = .point(HistoryPoint(time: Date(timeIntervalSince1970: seconds),
                                       level: try container.decode(Int.self, forKey: .level),
                                       onAC: try container.decode(Bool.self, forKey: .onAC),
                                       charging: try container.decode(Bool.self, forKey: .charging),
                                       resting: try container.decode(Bool.self, forKey: .resting),
                                       temperatureCelsius: try container.decodeIfPresent(Double.self, forKey: .temperature)))
        case "h":
            let seconds = try container.decode(Double.self, forKey: .day)
            self = .health(HealthPoint(day: Date(timeIntervalSince1970: seconds),
                                       maximumCapacityPercent: try container.decode(Int.self, forKey: .capacity),
                                       cycleCount: try container.decode(Int.self, forKey: .cycles)))
        case "b":
            self = .baseline(try container.decode(Int.self, forKey: .baseline))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown record kind")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .point(let point):
            try container.encode("p", forKey: .kind)
            try container.encode(point.time.timeIntervalSince1970, forKey: .time)
            try container.encode(point.level, forKey: .level)
            try container.encode(point.onAC, forKey: .onAC)
            try container.encode(point.charging, forKey: .charging)
            try container.encode(point.resting, forKey: .resting)
            try container.encodeIfPresent(point.temperatureCelsius, forKey: .temperature)
        case .health(let health):
            try container.encode("h", forKey: .kind)
            try container.encode(health.day.timeIntervalSince1970, forKey: .day)
            try container.encode(health.maximumCapacityPercent, forKey: .capacity)
            try container.encode(health.cycleCount, forKey: .cycles)
        case .baseline(let value):
            try container.encode("b", forKey: .kind)
            try container.encode(value, forKey: .baseline)
        }
    }
}
