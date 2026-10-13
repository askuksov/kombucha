import KombuchaCore

/// The gateway the app registers. It exists before the engine, so an intent that launches Kombucha always finds
/// it; until the engine is attached and has published a snapshot it waits, at most `readinessLimit`.
@MainActor
final class LiveEngineGateway: EngineGateway {
    private let model: AppModel
    private let readinessLimit: Duration
    private let pollInterval: Duration
    private var engine: Engine?
    private var settings: (any SettingsStoring)?

    init(model: AppModel, readinessLimit: Duration = .seconds(10), pollInterval: Duration = .milliseconds(100)) {
        self.model = model
        self.readinessLimit = readinessLimit
        self.pollInterval = pollInterval
    }

    func attach(engine: Engine, settings: any SettingsStoring) {
        self.engine = engine
        self.settings = settings
    }

    func status() async throws -> BatteryStatus {
        let snapshot = try await ready().snapshot
        let state = PanelState.make(snapshot: snapshot, verdict: model.verdict)
        let line = if case .controls = state { Copy.statusLine(snapshot.mode, snapshot.thresholds) }
                   else { Self.heading(state) }
        return BatteryStatus(level: snapshot.displayLevel,
                             mode: snapshot.mode,
                             thresholds: snapshot.thresholds,
                             protection: snapshot.protection,
                             holdingLimit: snapshot.mayManage && snapshot.protection && snapshot.onAC && !snapshot.fullChargeActive,
                             line: line)
    }

    func setProtection(_ on: Bool) async throws -> Bool {
        let engine = try await openGate()
        try Self.check(await engine.setProtection(on))
        return on
    }

    func startFullCharge() async throws {
        let engine = try await openGate()
        try Self.check(await engine.setFullCharge(true))
    }

    /// The flag is cleared either way. Behind a closed gate the charger cannot be reached, and the gate says so.
    func stopFullCharge() async throws {
        let (snapshot, engine) = try await ready()
        let result = await engine.setFullCharge(false)
        if case .failed(.chargerNotReached) = result, closedGate(snapshot) != nil { return }
        try Self.check(result)
    }

    /// Stored in every state, like the sliders; nobody waits for the engine.
    func setThresholds(stop: Int, resume: Int) async throws -> Thresholds {
        let settings = try await attachedSettings()
        let pair = Thresholds.normalized(lower: resume, upper: stop)
        settings.setThresholds(lower: pair.lower, upper: pair.upper)
        return pair
    }

    /// An unsupported Mac fails at once: its engine never publishes a snapshot.
    private func ready() async throws -> (snapshot: ChargeSnapshot, engine: Engine) {
        let deadline = ContinuousClock.now + readinessLimit
        while true {
            if let verdict = model.verdict, verdict != .supported { throw GatewayError.unsupported }
            if let engine, let snapshot = model.snapshot { return (snapshot, engine) }
            guard ContinuousClock.now < deadline else { throw GatewayError.notReady }
            try await Task.sleep(for: pollInterval)
        }
    }

    private func attachedSettings() async throws -> any SettingsStoring {
        let deadline = ContinuousClock.now + readinessLimit
        while true {
            if let settings { return settings }
            guard ContinuousClock.now < deadline else { throw GatewayError.notReady }
            try await Task.sleep(for: pollInterval)
        }
    }

    private func openGate() async throws -> Engine {
        let (snapshot, engine) = try await ready()
        if let heading = closedGate(snapshot) { throw GatewayError.gate(heading) }
        return engine
    }

    /// The panel's heading when a gate keeps the controls closed, nil while they are open.
    private func closedGate(_ snapshot: ChargeSnapshot) -> String? {
        let state = PanelState.make(snapshot: snapshot, verdict: model.verdict)
        if case .controls = state { return nil }
        return Self.heading(state)
    }

    /// The panel's own heading, so Shortcuts and the panel say the same thing.
    private static func heading(_ state: PanelState) -> String {
        Copy.header(for: state).title ?? Copy.heading(.unknown)
    }

    private static func check(_ result: ActionResult) throws {
        if case .failed(let failure) = result { throw GatewayError.failed(failure) }
    }
}
