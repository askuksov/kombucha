import HelperProtocol
import KombuchaCore
import Synchronization
@testable import Kombucha

/// One ordered record of what the fakes were asked to do.
final class Journal: Sendable {
    private let lines = Mutex<[String]>([])
    var entries: [String] { lines.withLock { $0 } }
    func note(_ line: String) { lines.withLock { $0.append(line) } }
}

final class FakePower: PowerSource {
    let hasInternalBattery: Bool
    private let reading: Mutex<PowerReading?>
    private let readCount = Mutex(0)

    init(_ reading: PowerReading?, hasInternalBattery: Bool = true) {
        self.reading = Mutex(reading)
        self.hasInternalBattery = hasInternalBattery
    }

    var reads: Int { readCount.withLock { $0 } }

    func set(_ value: PowerReading?) { reading.withLock { $0 = value } }

    func read() -> PowerReading? {
        readCount.withLock { $0 += 1 }
        return reading.withLock { $0 }
    }
}

struct FakeSMC: SMCProbing {
    var result: SMCProbeResult = .ok
    var adapterSwitch = true
    func probe() -> SMCProbeResult { result }
    func probeAdapterSwitch() -> Bool { adapterSwitch }
}

final class FakeProcesses: ProcessListing {
    private let paths = Mutex<[String]>([])
    func set(_ value: [String]) { paths.withLock { $0 = value } }
    func executablePaths() -> [String] { paths.withLock { $0 } }
}

final class FakeHelper: HelperConnecting {
    /// One `setAdapter` as the engine sent it.
    struct AdapterCall: Equatable, Sendable {
        let enabled: Bool
        let leaseSeconds: Int
        static let on = AdapterCall(enabled: true, leaseSeconds: 0)
        /// A disable and a renew are the same call.
        static let off = AdapterCall(enabled: false, leaseSeconds: DischargePolicy.leaseSeconds)
    }

    private struct State {
        var pingReplies: [Result<Int, HelperCallError>] = []
        var chargeReplies: [Result<ChargeReply, HelperCallError>] = []
        var adapterReplies: [Result<ChargeReply, HelperCallError>] = []
        var pings = 0
        var drops = 0
        var commands: [Bool] = []
        var arrivedCommands: [Bool] = []
        var adapterCalls: [AdapterCall] = []
        var commandDelay: Duration = .zero
        var pingDelay: Duration = .zero
        var adapterDelay: Duration = .zero
        var pingVersion = HelperIdentity.protocolVersion
    }

    private let state = Mutex(State())
    private let journal: Journal

    init(journal: Journal) { self.journal = journal }

    var pings: Int { state.withLock { $0.pings } }
    var drops: Int { state.withLock { $0.drops } }
    /// `true` is allow, `false` is inhibit, in the order they were sent.
    var commands: [Bool] { state.withLock { $0.commands } }
    /// Charge commands as they arrive, before any delay; `commands` holds them once answered.
    var arrivedCommands: [Bool] { state.withLock { $0.arrivedCommands } }
    var adapterCalls: [AdapterCall] { state.withLock { $0.adapterCalls } }

    /// Replies used once each, in order; afterwards every ping answers.
    func scriptPings(_ replies: Result<Int, HelperCallError>...) {
        state.withLock { $0.pingReplies.append(contentsOf: replies) }
    }

    /// Replies used once each, in order; afterwards every command lands.
    func scriptCommands(_ replies: Result<ChargeReply, HelperCallError>...) {
        state.withLock { $0.chargeReplies.append(contentsOf: replies) }
    }

    /// Replies used once each, in order; afterwards every adapter command lands.
    func scriptAdapter(_ replies: Result<ChargeReply, HelperCallError>...) {
        state.withLock { $0.adapterReplies.append(contentsOf: replies) }
    }

    /// Holds every later charge command this long before it answers, so a test can press twice meanwhile.
    func delayCommands(by delay: Duration) { state.withLock { $0.commandDelay = delay } }

    /// Holds every later ping this long before it answers.
    func delayPings(by delay: Duration) { state.withLock { $0.pingDelay = delay } }

    /// Holds every later adapter command this long before it answers.
    func delayAdapter(by delay: Duration) { state.withLock { $0.adapterDelay = delay } }

    /// Every later unscripted ping answers with this protocol version.
    func answerPings(with version: Int) { state.withLock { $0.pingVersion = version } }

    func ping() async -> Result<Int, HelperCallError> {
        let delay = state.withLock { $0.pingDelay }
        if delay > .zero { try? await Task.sleep(for: delay) }
        journal.note("ping")
        return state.withLock { state in
            state.pings += 1
            return state.pingReplies.isEmpty ? .success(state.pingVersion) : state.pingReplies.removeFirst()
        }
    }

    func setCharging(allow: Bool) async -> Result<ChargeReply, HelperCallError> {
        let delay = state.withLock { state in
            state.arrivedCommands.append(allow)
            return state.commandDelay
        }
        if delay > .zero { try? await Task.sleep(for: delay) }
        journal.note(allow ? "allow" : "inhibit")
        return state.withLock { state in
            state.commands.append(allow)
            return state.chargeReplies.isEmpty ? .success(.landed) : state.chargeReplies.removeFirst()
        }
    }

    func setAdapter(enabled: Bool, leaseSeconds: Int) async -> Result<ChargeReply, HelperCallError> {
        let delay = state.withLock { $0.adapterDelay }
        if delay > .zero { try? await Task.sleep(for: delay) }
        journal.note(enabled ? "adapter on" : "adapter off")
        return state.withLock { state in
            state.adapterCalls.append(AdapterCall(enabled: enabled, leaseSeconds: leaseSeconds))
            return state.adapterReplies.isEmpty ? .success(.landed) : state.adapterReplies.removeFirst()
        }
    }

    func dropConnection() {
        state.withLock { $0.drops += 1 }
    }
}

extension ChargeReply {
    static let landed = ChargeReply(result: .done, detail: "done")
    static let refused = ChargeReply(result: .failed, detail: "the SMC refused")
}

final class FakeRegistrar: HelperRegistering {
    private struct State {
        var registration: HelperRegistration
        var afterRegister: HelperRegistration?
        var afterUnregister: HelperRegistration = .notRegistered
        var registers = 0
    }

    private let state: Mutex<State>
    private let journal: Journal

    init(_ registration: HelperRegistration, journal: Journal) {
        state = Mutex(State(registration: registration))
        self.journal = journal
    }

    var registration: HelperRegistration { state.withLock { $0.registration } }
    var registers: Int { state.withLock { $0.registers } }

    func set(_ value: HelperRegistration) { state.withLock { $0.registration = value } }
    func whenRegistered(becomes value: HelperRegistration) { state.withLock { $0.afterRegister = value } }
    func whenUnregistered(becomes value: HelperRegistration) { state.withLock { $0.afterUnregister = value } }

    func registerHelper() -> HelperRegistration {
        journal.note("register")
        return state.withLock { state in
            state.registers += 1
            if let next = state.afterRegister { state.registration = next }
            return state.registration
        }
    }

    func unregisterHelper() -> HelperRegistration {
        journal.note("unregister")
        return state.withLock { state in
            state.registration = state.afterUnregister
            return state.registration
        }
    }
}

final class FakeSettings: SettingsStoring {
    private let settings: Mutex<ChargeSettings>
    private let normalized = Mutex(0)
    private let writes = Mutex(0)

    init(_ settings: ChargeSettings) { self.settings = Mutex(settings) }

    var chargeSettings: ChargeSettings { settings.withLock { $0 } }
    var normalizations: Int { normalized.withLock { $0 } }
    var thresholdWrites: Int { writes.withLock { $0 } }

    func set(_ value: ChargeSettings) { settings.withLock { $0 = value } }
    func setThresholds(lower: Int, upper: Int) {
        settings.withLock { $0.thresholds = .normalized(lower: lower, upper: upper) }
        writes.withLock { $0 += 1 }
    }
    func setBatteryProtection(_ on: Bool) { settings.withLock { $0.protection = on } }
    func normalizeStoredThresholds() { normalized.withLock { $0 += 1 } }
}

final class FakeEventSource: EventSource {
    let name: String
    private let startSucceeds: Bool
    private let journal: Journal

    init(name: String, startSucceeds: Bool = true, journal: Journal) {
        self.name = name
        self.startSucceeds = startSucceeds
        self.journal = journal
    }

    func start() -> Bool {
        journal.note("start \(name)")
        return startSucceeds
    }

    func stop() { journal.note("stop \(name)") }
}

final class RecordingObserver: ChargeObserving {
    private let endings = Mutex<[FullChargeEnding]>([])
    private let seen = Mutex<[ChargeSnapshot]>([])
    var fullChargeEndings: [FullChargeEnding] { endings.withLock { $0 } }
    /// Every pass's snapshot, synchronously, so a test can tell what a pass had produced at a given moment.
    var snapshots: [ChargeSnapshot] { seen.withLock { $0 } }

    func observe(_ snapshot: ChargeSnapshot, fullChargeEnded: FullChargeEnding?) {
        seen.withLock { $0.append(snapshot) }
        if let fullChargeEnded { endings.withLock { $0.append(fullChargeEnded) } }
    }
}

/// Everything the engine published, in order.
final class SnapshotLog: Sendable {
    private let snapshots = Mutex<[ChargeSnapshot]>([])
    var all: [ChargeSnapshot] { snapshots.withLock { $0 } }
    func append(_ snapshot: ChargeSnapshot) { snapshots.withLock { $0.append(snapshot) } }
}

final class Flag: Sendable {
    private let raised = Mutex(false)
    var isRaised: Bool { raised.withLock { $0 } }
    func raise() { raised.withLock { $0 = true } }
}

/// Waits for a condition without ever hanging a test: false once the limit passes. Runs on the caller's actor,
/// so a main-actor test can wait on main-actor state.
func eventually(isolation: isolated (any Actor)? = #isolation,
                within limit: Duration = .seconds(2),
                _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + limit
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

/// An engine wired to fakes: on the adapter, protection on, range 75–80, helper enabled.
struct EngineHarness {
    let journal = Journal()
    let inbox = EngineInbox()
    let power: FakePower
    let processes = FakeProcesses()
    let helper: FakeHelper
    let registrar: FakeRegistrar
    let settings: FakeSettings
    let observer = RecordingObserver()
    let published = SnapshotLog()
    /// Raised when the engine ends its snapshot stream; only a subscribed harness raises it.
    let snapshotsEnded = Flag()
    let engine: Engine

    init(level: Double = 78,
         onAC: Bool = true,
         adapterPresent: Bool? = nil,
         thresholds: Thresholds = .standard,
         protection: Bool = true,
         registration: HelperRegistration = .enabled,
         hasInternalBattery: Bool = true,
         smc: SMCProbeResult = .ok,
         adapterSwitch: Bool = true,
         sourceStarts: Bool = true,
         timing: Engine.Timing = Engine.Timing(),
         snapshotBuffer: AsyncStream<ChargeSnapshot>.Continuation.BufferingPolicy = .unbounded,
         subscribe: Bool = true) {
        power = FakePower(PowerReading(level: level, onAC: onAC, charging: false, adapterPresent: adapterPresent),
                          hasInternalBattery: hasInternalBattery)
        helper = FakeHelper(journal: journal)
        registrar = FakeRegistrar(registration, journal: journal)
        settings = FakeSettings(ChargeSettings(thresholds: thresholds, protection: protection))
        let ports = EnginePorts(power: power,
                                smc: FakeSMC(result: smc, adapterSwitch: adapterSwitch),
                                processes: processes,
                                helper: helper,
                                registrar: registrar,
                                settings: settings,
                                observer: observer,
                                eventSources: [FakeEventSource(name: "power", startSucceeds: sourceStarts, journal: journal),
                                               FakeEventSource(name: "wake", journal: journal)],
                                ownBundlePath: "/Applications/Kombucha.app")
        engine = Engine(inbox: inbox, ports: ports, timing: timing, snapshotBuffer: snapshotBuffer)
        if subscribe {
            Task { [engine, published, snapshotsEnded] in
                for await snapshot in engine.snapshots {
                    published.append(snapshot)
                }
                snapshotsEnded.raise()
            }
        }
    }

    /// The published snapshots once there are at least `count` of them, or what there is after 2 s.
    func snapshots(_ count: Int) async -> [ChargeSnapshot] {
        _ = await eventually { published.all.count >= count }
        return published.all
    }

    /// Runs the loop; the flag rises when it returns. A loop a failed test left running is shut down after 10 s.
    func runLoop() -> Flag {
        let ended = Flag()
        Task { [engine] in
            await engine.run()
            ended.raise()
        }
        Task { [engine] in
            try? await Task.sleep(for: .seconds(10))
            _ = await engine.shutdown(waitingAtMost: .seconds(1))
        }
        return ended
    }

    func reading(_ level: Double, onAC: Bool = true, temperature: Double? = nil, adapterPresent: Bool? = nil) -> PowerReading {
        PowerReading(level: level, onAC: onAC, charging: false, temperatureCelsius: temperature, adapterPresent: adapterPresent)
    }

    /// Posts an event that waits for an answer and returns it once the engine has handled it.
    func answer(_ event: (Answer) -> EngineEvent) async -> ActionResult {
        let answer = Answer()
        _ = await engine.handle(event(answer))
        return await answer.value(waitingAtMost: .zero)
    }
}
