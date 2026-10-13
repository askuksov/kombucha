import KombuchaCore

/// Why the engine owes a write the machine did not ask for.
enum ReassertCause: Equatable, Sendable {
    case start, wake, reconnection
}

/// The engine's log sentences, kept pure so tests can read them.
enum EngineLogText {
    /// `range widened (level 83%, range 75–84%)`
    static func because(_ reason: CommandReason?, cause: ReassertCause?, level: Int, thresholds: Thresholds) -> String {
        "\(words(reason, cause: cause)) (level \(level)%, \(range(thresholds)))"
    }

    static func words(_ reason: CommandReason?, cause: ReassertCause?) -> String {
        switch reason {
        case .stopThresholdReached: "stop threshold reached"
        case .resumeThresholdReached: "resume threshold reached"
        case .rangeWidened: "range widened"
        case .externalBatteryManager: "external battery manager running"
        case .adapterOut: "adapter out"
        case .protectionOff: "protection off"
        case .fullCharge: "full charge"
        case .heatReached: "battery hot"
        case .cooledDown: "battery cooled down"
        case .discharging: "discharging"
        case .reassert:
            switch cause {
            case .start: "reassert at start"
            case .wake: "reassert after wake"
            case .reconnection: "reassert after reconnection"
            case nil: "reassert"
            }
        case nil: "no reason recorded"
        }
    }

    static func settings(_ settings: ChargeSettings) -> String {
        "settings: protection \(settings.protection ? "on" : "off"), \(range(settings.thresholds))"
    }

    static func adapter(attached: Bool, level: Int) -> String {
        "adapter: \(attached ? "attached" : "removed") (level \(level)%)"
    }

    static func fullChargeStarted(level: Int) -> String {
        "full charge: started (level \(level)%)"
    }

    /// No ending means the full charge was stopped from the panel.
    static func fullChargeEnded(_ ending: FullChargeEnding?, level: Int) -> String {
        let how = switch ending {
        case .reachedFull: "reached 100%"
        case .unplugged: "adapter out"
        case .protectionOff: "protection off"
        case .externalBatteryManager: "external battery manager running"
        case nil: "stopped"
        }
        return "full charge: ended: \(how) (level \(level)%)"
    }

    static func dischargeStarted(level: Int) -> String {
        "discharge: started (level \(level)%)"
    }

    static func dischargeEnded(_ ending: DischargeEnding, level: Int) -> String {
        let how = switch ending {
        case .reachedStop: "reached Stop"
        case .unplugged: "adapter out"
        case .protectionOff: "protection off"
        case .fullCharge: "full charge started"
        case .externalBatteryManager: "external battery manager running"
        case .stopped: "stopped"
        case .sleep: "the Mac is going to sleep"
        case .shutdown: "Kombucha is quitting"
        case .blocked: "the helper cannot switch the adapter"
        }
        return "discharge: ended: \(how) (level \(level)%)"
    }

    static func dischargeRefused(_ refusal: DischargeRefusal) -> String {
        let why = switch refusal {
        case .noReading: "no reading yet"
        case .gateClosed: "Kombucha cannot manage the charger"
        case .adapterSwitchUnavailable: "the helper cannot switch the adapter"
        case .protectionOff: "protection off"
        case .adapterAbsent: "adapter out"
        case .fullChargeActive: "a full charge is running"
        case .notAboveStop: "the level is not above Stop"
        }
        return "discharge: not started: \(why)"
    }

    static func adapterWords(_ command: AdapterCommand) -> String {
        switch command {
        case .disable(let seconds): "adapter off (lease \(seconds) s)"
        case .renew(let seconds): "adapter lease renewal (\(seconds) s)"
        case .enable: "adapter on"
        }
    }

    static func adapterNotSent(_ command: AdapterCommand) -> String {
        "\(adapterWords(command)) not sent: the helper cannot switch the adapter"
    }

    static func notSent(_ command: ChargeCommand, why: String) -> String {
        "\(command == .allow ? "allow" : "inhibit") not sent: the helper is not enabled (\(why))"
    }

    private static func range(_ thresholds: Thresholds) -> String {
        "range \(thresholds.lower)–\(thresholds.upper)%"
    }
}
