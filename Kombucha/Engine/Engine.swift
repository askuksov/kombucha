import HelperProtocol
import KombuchaCore

/// The only sender of charge and adapter commands and the only publisher of snapshots.
actor Engine {
    struct Timing: Sendable {
        var tick: Duration = .seconds(60)
        var callerWait: Duration = .seconds(5)
        /// How long a helper action may take to settle the write path before its registration result is given as is.
        var settleWait: Duration = .seconds(3)
        /// How long an adapter `enable` outside a pass may take; on the way out also no longer than `shutdownBudget` allows.
        var adapterOnWait: Duration = .seconds(2)
        /// Everything quitting waits for, the `enable` then the `allow`; under the app's 2.5 s wait for the answer.
        var shutdownBudget: Duration = .milliseconds(2300)
    }

    nonisolated let snapshots: AsyncStream<ChargeSnapshot>
    private nonisolated let publish: AsyncStream<ChargeSnapshot>.Continuation
    private let inbox: EngineInbox
    private let ports: EnginePorts
    private let timing: Timing

    private var state = MachineState()
    private var reassertCause: ReassertCause? = .start
    private var reachable = false
    private var repaired = false
    private var lastSnapshot: ChargeSnapshot?
    private var lastExternalBatteryManager: ExternalBatteryManager?
    private var lastWritePath: WritePath?
    private var lastSettings: ChargeSettings?
    /// The last pass's "on AC": the cable while the adapter may be switched off, the power source otherwise.
    private var lastOnAC: Bool?
    private var lastFullChargeActive = false
    private var lastDischargeActive = false
    private var lastNotSent: NotSent?
    private var lastAdapterNotSent: AdapterCommand?
    /// Why the engine itself ended a discharge (stopped, sleep); the pass that follows logs it.
    private var dischargeEndingAsked: DischargeEnding?
    /// The first pass after a start looks for an adapter left switched off.
    private var strandedAdapterCheckOwed = false
    private var adapterKeyPresent = false
    private var tickTask: Task<Void, Never>?
    private var running = false
    private var batteryUnreadable = false
    private var helperVersion: Int?

    /// A helper that speaks protocol 2 or later, on a Mac with the adapter key.
    private var adapterSwitchAvailable: Bool {
        adapterKeyPresent && (helperVersion ?? 0) >= HelperIdentity.adapterSwitchVersion
    }

    /// The UI needs only the newest snapshot; a test that reads every one passes `.unbounded`.
    init(inbox: EngineInbox,
         ports: EnginePorts,
         timing: Timing = Timing(),
         snapshotBuffer: AsyncStream<ChargeSnapshot>.Continuation.BufferingPolicy = .bufferingNewest(1)) {
        self.inbox = inbox
        self.ports = ports
        self.timing = timing
        (snapshots, publish) = AsyncStream.makeStream(bufferingPolicy: snapshotBuffer)
    }

    // MARK: Callers

    nonisolated func probe() async -> ActionResult {
        await ask { .probe($0) }
    }

    nonisolated func setProtection(_ on: Bool) async -> ActionResult {
        await ask { .setProtection(on, $0) }
    }

    nonisolated func setFullCharge(_ on: Bool) async -> ActionResult {
        await ask { .setFullCharge(on, $0) }
    }

    nonisolated func setDischarge(_ on: Bool) async -> ActionResult {
        await ask { .setDischarge(on, $0) }
    }

    nonisolated func installHelper() async -> ActionResult {
        await ask { .installHelper($0) }
    }

    nonisolated func removeHelper() async -> ActionResult {
        await ask { .removeHelper($0) }
    }

    nonisolated func shutdown(waitingAtMost limit: Duration) async -> ActionResult {
        await ask(waitingAtMost: limit) { .shutdown($0) }
    }

    private nonisolated func ask(waitingAtMost limit: Duration? = nil,
                                 _ event: (Answer) -> EngineEvent) async -> ActionResult {
        let answer = Answer()
        // A loop that has ended will never answer.
        guard inbox.post(event(answer)) else { return .failed(.noAnswer) }
        return await answer.value(waitingAtMost: limit ?? timing.callerWait)
    }

    // MARK: Startup and loop

    /// Only a supported Mac gets the helper, the event sources and a first pass; on any other both streams end.
    func start() async -> SupportVerdict {
        lastSnapshot = nil
        lastExternalBatteryManager = nil
        lastWritePath = nil
        lastSettings = nil
        lastOnAC = nil
        lastFullChargeActive = false
        lastDischargeActive = false
        lastNotSent = nil
        lastAdapterNotSent = nil
        dischargeEndingAsked = nil
        let verdict = SupportVerdict.verdict(hasInternalBattery: ports.power.hasInternalBattery,
                                             probe: ports.smc.probe())
        guard verdict == .supported else {
            AppLog.engine.error("not supported: \(String(describing: verdict), privacy: .public)")
            end()
            return verdict
        }
        adapterKeyPresent = ports.smc.probeAdapterSwitch()
        let key = adapterKeyPresent ? "present" : "absent"
        AppLog.engine.notice("adapter switch key: \(key, privacy: .public)")
        ports.settings.normalizeStoredThresholds()
        _ = ports.registrar.registerHelper()
        state = MachineState()
        reassertCause = .start
        reachable = false
        repaired = false
        strandedAdapterCheckOwed = true
        for source in ports.eventSources where !source.start() {
            AppLog.engine.error("\(source.name, privacy: .public) did not start")
        }
        await probeWritePath()
        _ = await pass(nil)
        return verdict
    }

    /// Takes events one at a time until `shutdown`; 60 s without one runs a pass. Runs once per engine.
    func run() async {
        guard !running else {
            AppLog.engine.fault("the loop is already running")
            return
        }
        running = true
        defer {
            tickTask?.cancel()
            end()
        }
        scheduleTick()
        for await event in inbox.events {
            tickTask?.cancel()
            guard await handle(event) else { return }
            scheduleTick()
        }
    }

    /// From here on a caller fails at once and a snapshot subscriber sees the stream end.
    private func end() {
        inbox.finish()
        publish.finish()
    }

    private func scheduleTick() {
        let inbox = inbox
        let interval = timing.tick
        tickTask = Task {
            guard (try? await Task.sleep(for: interval)) != nil else { return }
            inbox.post(.tick)
        }
    }

    /// Handles one event; false ends the loop.
    func handle(_ event: EngineEvent) async -> Bool {
        switch event {
        case .powerChanged(let reading):
            _ = await pass(reading)
        case .settingsChanged, .tick:
            _ = await pass(nil)
        case .systemWoke:
            reassertCause = .wake
            _ = await pass(nil)
        case .helperConnectionLost:
            // The app's own drops and failed pings report the same loss.
            guard reachable else { return true }
            await probeWritePath()
            _ = await pass(nil)
        case .probe(let answer):
            await probeWritePath()
            answer.resolve(Self.result(await pass(nil), failure: .chargerNotReached))
        case .setProtection(let on, let answer):
            await setProtection(on, answer)
        case .setFullCharge(let on, let answer):
            await setFullCharge(on, answer)
        case .setDischarge(let on, let answer):
            await setDischarge(on, answer)
        case .willSleep(let answer):
            await willSleep(answer)
        case .installHelper(let answer):
            await installHelper(answer)
        case .removeHelper(let answer):
            await removeHelper(answer)
        case .shutdown(let answer):
            await shutdown(answer)
            return false
        }
        return true
    }

    // MARK: Pass

    private func pass(_ fresh: PowerReading?) async -> Outcome {
        let settings = ports.settings.chargeSettings
        if settings != lastSettings {
            AppLog.engine.notice("\(EngineLogText.settings(settings), privacy: .public)")
            lastSettings = settings
        }
        guard let reading = fresh ?? ports.power.read() else {
            if !batteryUnreadable {
                batteryUnreadable = true
                AppLog.engine.error("the battery could not be read")
            }
            return .failed("the battery could not be read")
        }
        if batteryUnreadable {
            batteryUnreadable = false
            AppLog.engine.notice("the battery reads again")
        }
        let externalBatteryManager = ExternalBatteryManagers.verdict(executablePaths: ports.processes.executablePaths(),
                                                                      ownBundlePath: ports.ownBundlePath,
                                                                      table: ExternalBatteryManagers.table)
        if externalBatteryManager != lastExternalBatteryManager {
            AppLog.engine.notice("external battery manager: \(externalBatteryManager?.displayName ?? "none", privacy: .public)")
            lastExternalBatteryManager = externalBatteryManager
        }
        if strandedAdapterCheckOwed {
            strandedAdapterCheckOwed = false
            // The cable is in and the power source says battery: a key left off by a crash, a kill or a restart.
            // A running manager may have switched it off itself, so it is left alone.
            if adapterSwitchAvailable, externalBatteryManager == nil, reading.adapterPresent == true, !reading.onAC,
               !state.dischargeActive {
                AppLog.engine.notice("the adapter is connected and switched off — switching it on")
                state = state.owingAdapterEnable()
            }
        }
        let registration = ports.registrar.registration
        let plan = Planner.plan(state: state, reading: reading, settings: settings,
                                reassert: reassertCause != nil, externalBatteryManager: externalBatteryManager,
                                adapterSwitchReady: registration == .enabled && reachable && adapterSwitchAvailable)
        let level = plan.snapshot.displayLevel
        // While the adapter may be switched off this follows the cable, not the power source.
        if plan.snapshot.onAC != lastOnAC {
            AppLog.engine.notice("\(EngineLogText.adapter(attached: plan.snapshot.onAC, level: level), privacy: .public)")
            lastOnAC = plan.snapshot.onAC
        }

        var planned = plan.step.state
        var dischargeEnded = plan.step.dischargeEnded
        var adapterFailure: String?
        // The adapter goes back on before any other command.
        if plan.step.adapterCommand == .enable,
           let problem = await sendAdapter(.enable, registration: registration, level: level) {
            planned = planned.owingAdapterEnable()
            adapterFailure = problem
        }

        let outcome: Outcome
        if let command = plan.command, registration == .enabled {
            let name = command == .allow ? "allow" : "inhibit"
            let why = EngineLogText.because(plan.reason, cause: reassertCause, level: level,
                                            thresholds: settings.thresholds)
            lastNotSent = nil
            switch await ports.helper.setCharging(allow: command == .allow) {
            case .success(let reply) where reply.result == .done:
                AppLog.engine.notice("\(name, privacy: .public) landed: \(why, privacy: .public)")
                state = planned
                reassertCause = nil
                setReachable(true)
                outcome = .wrote
            case .success(let reply):
                AppLog.engine.error("\(name, privacy: .public) refused: \(why, privacy: .public): \(reply.detail, privacy: .public)")
                // The charger holds what it held; the bookkeeping follows the plan.
                state = state.following(planned)
                setReachable(true)
                outcome = .failed(reply.detail)
            case .failure(let error):
                AppLog.engine.error("\(name, privacy: .public) not answered: \(why, privacy: .public): \(String(describing: error), privacy: .public)")
                state = state.following(planned)
                setReachable(false)
                ports.helper.dropConnection()
                outcome = .failed(String(describing: error))
            }
        } else if let command = plan.command {
            // A command cannot reach a helper that is not enabled; the charger holds what it held.
            let notSent = NotSent(command: command, reason: plan.reason)
            if notSent != lastNotSent {
                let why = EngineLogText.because(plan.reason, cause: reassertCause, level: level,
                                                thresholds: settings.thresholds)
                AppLog.engine.notice("\(EngineLogText.notSent(command, why: why), privacy: .public)")
                lastNotSent = notSent
            }
            state = state.following(planned)
            outcome = .failed("the helper is not enabled")
        } else {
            lastNotSent = nil
            state = planned
            outcome = .nothingToDo
        }

        // Switching the adapter off, or keeping it off, comes last and only once the charge is held.
        if let command = plan.step.adapterCommand, command != .enable {
            if case .failed = outcome {
                AppLog.engine.error("\(EngineLogText.adapterWords(command), privacy: .public) not sent: the charge is not held")
                state = state.endingDischargeAfterFailure()
                dischargeEnded = .blocked
            } else if let problem = await sendAdapter(command, registration: registration, level: level) {
                state = state.endingDischargeAfterFailure()
                dischargeEnded = .blocked
                adapterFailure = problem
            }
        }

        if state.dischargeActive != lastDischargeActive {
            let line = state.dischargeActive
                ? EngineLogText.dischargeStarted(level: level)
                : EngineLogText.dischargeEnded(dischargeEnded ?? dischargeEndingAsked ?? .stopped, level: level)
            AppLog.engine.notice("\(line, privacy: .public)")
            lastDischargeActive = state.dischargeActive
        }
        dischargeEndingAsked = nil
        if state.fullChargeActive != lastFullChargeActive {
            let line = state.fullChargeActive
                ? EngineLogText.fullChargeStarted(level: level)
                : EngineLogText.fullChargeEnded(plan.step.fullChargeEnded, level: level)
            AppLog.engine.notice("\(line, privacy: .public)")
            lastFullChargeActive = state.fullChargeActive
        }

        let path = WritePath.verdict(registration, answered: reachable)
        if path != lastWritePath {
            if let old = lastWritePath {
                AppLog.engine.notice("write path: \(String(describing: old), privacy: .public) → \(String(describing: path), privacy: .public)")
            } else {
                AppLog.engine.notice("write path: \(String(describing: path), privacy: .public)")
            }
            lastWritePath = path
        }
        let snapshot = plan.snapshot
            .withWritePath(path)
            .withDischarge(state.dischargeActive,
                           adapterSwitchAvailable: adapterSwitchAvailable && reading.adapterPresent == true)
        if snapshot != lastSnapshot {
            lastSnapshot = snapshot
            publish.yield(snapshot)
        }
        ports.observer.observe(snapshot, fullChargeEnded: plan.step.fullChargeEnded)
        if case .failed = outcome { return outcome }
        return adapterFailure.map(Outcome.failed) ?? outcome
    }

    /// Sends one adapter command; nil when it landed, otherwise why not. Never sent while the registration is not
    /// enabled, nor to a helper older than protocol 2: an unknown selector would break the connection.
    private func sendAdapter(_ command: AdapterCommand, registration: HelperRegistration, level: Int) async -> String? {
        let words = EngineLogText.adapterWords(command)
        guard registration == .enabled, adapterSwitchAvailable else {
            if command != lastAdapterNotSent {
                AppLog.engine.notice("\(EngineLogText.adapterNotSent(command), privacy: .public)")
                lastAdapterNotSent = command
            }
            return "the helper cannot switch the adapter"
        }
        lastAdapterNotSent = nil
        switch await ports.helper.setAdapter(enabled: command.enabled, leaseSeconds: command.leaseSeconds) {
        case .success(let reply) where reply.result == .done:
            if case .renew = command {
                AppLog.engine.info("\(words, privacy: .public) landed (level \(level)%)")
            } else {
                AppLog.engine.notice("\(words, privacy: .public) landed (level \(level)%)")
            }
            setReachable(true)
            return nil
        case .success(let reply):
            AppLog.engine.error("\(words, privacy: .public) refused (level \(level)%): \(reply.detail, privacy: .public)")
            setReachable(true)
            return reply.detail
        case .failure(let error):
            AppLog.engine.error("\(words, privacy: .public) not answered (level \(level)%): \(String(describing: error), privacy: .public)")
            setReachable(false)
            ports.helper.dropConnection()
            return String(describing: error)
        }
    }

    // MARK: Probe and repair

    /// Leaves `reachable` true or false; the pass that follows publishes the write path.
    private func probeWritePath() async {
        guard ports.registrar.registration == .enabled else {
            setReachable(false)
            return
        }
        if await ping() { return }
        guard !repaired else { return }
        repaired = true
        AppLog.engine.notice("helper registered and not answering — registering again")
        _ = ports.registrar.registerHelper()
        if await ping() {
            AppLog.engine.notice("helper answers again")
        } else {
            AppLog.engine.error("helper still not answering after registering again")
        }
    }

    private func ping() async -> Bool {
        let answered: Bool
        if case .success(let version) = await ports.helper.ping() {
            answered = true
            noteHelperVersion(version)
        } else {
            answered = false
            ports.helper.dropConnection()
        }
        setReachable(answered)
        return answered
    }

    // A running helper keeps its old binary after an app update; the log is where a mismatch shows.
    private func noteHelperVersion(_ version: Int) {
        guard version != helperVersion else { return }
        helperVersion = version
        if version == HelperIdentity.protocolVersion {
            AppLog.engine.notice("the helper speaks protocol \(version)")
        } else {
            AppLog.engine.error("the helper speaks protocol \(version), the app \(HelperIdentity.protocolVersion)")
        }
    }

    private func setReachable(_ now: Bool) {
        if WritePath.writeOwed(wasReachable: reachable, nowReachable: now) {
            // At launch the first ping reconnects; the write owed is still the start's.
            reassertCause = reassertCause ?? .reconnection
        }
        if now {
            repaired = false
        }
        reachable = now
    }

    // MARK: Actions

    private func setProtection(_ on: Bool, _ answer: Answer) async {
        let inForce = ports.settings.chargeSettings.protection
        ports.settings.setBatteryProtection(on)
        guard case .failed = await pass(nil) else {
            answer.resolve(.succeeded)
            return
        }
        // Restore the value that was in force, not the request's complement.
        ports.settings.setBatteryProtection(inForce)
        _ = await pass(nil)
        answer.resolve(.failed(.chargerNotReached))
    }

    private func setFullCharge(_ on: Bool, _ answer: Answer) async {
        if on {
            // During a discharge this is the cable, not the power source.
            guard lastOnAC == true else {
                answer.resolve(.failed(.adapterRequired))
                return
            }
            ports.settings.setBatteryProtection(true)
        }
        // A running discharge ends in this pass, adapter first.
        state = state.withFullCharge(on)
        answer.resolve(Self.result(await pass(nil), failure: .chargerNotReached))
    }

    /// The panel shows the button only when the start check passes, so a refusal here is a race; it answers with
    /// the charger sentence, as there is no other.
    private func setDischarge(_ on: Bool, _ answer: Answer) async {
        if on {
            guard !state.dischargeActive else {
                answer.resolve(.succeeded)
                return
            }
            if let refusal = DischargeStart.refusal(lastSnapshot) {
                AppLog.engine.notice("\(EngineLogText.dischargeRefused(refusal), privacy: .public)")
                answer.resolve(.failed(.chargerNotReached))
                return
            }
            state = state.withDischarge(true)
        } else {
            guard state.dischargeActive else {
                answer.resolve(.succeeded)
                return
            }
            dischargeEndingAsked = .stopped
            state = state.withDischarge(false)
        }
        answer.resolve(Self.result(await pass(nil), failure: .chargerNotReached))
    }

    /// Before the Mac sleeps a running discharge ends and an owed `enable` goes out. Without either, no pass runs:
    /// an ordinary sleep costs nothing.
    private func willSleep(_ answer: Answer) async {
        guard state.dischargeActive || state.adapterDisabled else {
            answer.resolve(.succeeded)
            return
        }
        if state.dischargeActive {
            dischargeEndingAsked = .sleep
            state = state.withDischarge(false)
        }
        answer.resolve(Self.result(await pass(nil), failure: .chargerNotReached))
    }

    private func installHelper(_ answer: Answer) async {
        let registration = ports.registrar.registerHelper()
        let installed = registration == .enabled || registration == .requiresApproval
        let result: ActionResult = installed ? .succeeded : .failed(.helperNotInstalled)
        let fallback = resolveAfterSettleWait(answer, result)
        await probeWritePath()
        _ = await pass(nil)
        fallback.cancel()
        answer.resolve(result)
    }

    private func removeHelper(_ answer: Answer) async {
        // The adapter goes back on first: a helper that is gone can never switch it on again.
        if state.dischargeActive || state.adapterDisabled {
            if await sendEnable(waitingAtMost: timing.adapterOnWait) == .landed {
                AppLog.engine.notice("adapter on landed before removing the helper")
                state = state.adapterSwitchedOn()
            } else {
                AppLog.engine.error("adapter on did not land before removing the helper")
                state = state.endingDischargeAfterFailure()
            }
        }
        if state.holdsInhibit {
            if await sendAllow() {
                AppLog.engine.notice("allow landed before removing the helper")
                let owing = state.adapterDisabled
                state = MachineState().withFullCharge(state.fullChargeActive)
                if owing { state = state.owingAdapterEnable() }
            } else {
                AppLog.engine.error("allow did not land before removing the helper")
            }
        }
        let registration = ports.registrar.unregisterHelper()
        let result: ActionResult = registration == .notRegistered ? .succeeded : .failed(.helperNotRemoved)
        let fallback = resolveAfterSettleWait(answer, result)
        _ = await pass(nil)
        fallback.cancel()
        answer.resolve(result)
    }

    /// The caller waits for the pass that publishes the new write path, but not past `settleWait`: the
    /// answer is first-wins, so the pass's own resolve is dropped once this one has landed.
    private func resolveAfterSettleWait(_ answer: Answer, _ result: ActionResult) -> Task<Void, Never> {
        let limit = timing.settleWait
        return Task {
            guard (try? await Task.sleep(for: limit)) != nil else { return }
            answer.resolve(result)
        }
    }

    private func shutdown(_ answer: Answer) async {
        AppLog.engine.notice("shutting down")
        for source in ports.eventSources {
            source.stop()
        }
        // The adapter first, then the charge; the helper also switches the adapter on when this connection ends.
        let clock = ContinuousClock()
        let deadline = clock.now + timing.shutdownBudget
        var helperSilent = false
        if state.dischargeActive || state.adapterDisabled {
            if state.dischargeActive {
                let line = EngineLogText.dischargeEnded(.shutdown, level: lastSnapshot?.displayLevel ?? 0)
                AppLog.engine.notice("\(line, privacy: .public)")
            }
            switch await sendEnable(waitingAtMost: min(timing.adapterOnWait, deadline - clock.now)) {
            case .landed:
                AppLog.engine.notice("adapter on landed on the way out")
            case .unanswered:
                AppLog.engine.error("adapter on not answered on the way out")
                helperSilent = true
            case .failed, .notSent:
                AppLog.engine.error("adapter on did not land on the way out")
            }
        }
        if state.holdsInhibit {
            if helperSilent {
                // A second unanswered call would outlast the app's wait.
                AppLog.engine.error("allow not sent on the way out: the helper did not answer")
            } else {
                let helper = ports.helper
                switch await Self.bounded(by: deadline - clock.now, { await helper.setCharging(allow: true) }) {
                case .success(let reply) where reply.result == .done:
                    AppLog.engine.notice("allow landed on the way out")
                case nil:
                    AppLog.engine.error("allow sent on the way out, its answer not awaited")
                default:
                    AppLog.engine.error("allow did not land on the way out")
                }
            }
        }
        answer.resolve(.succeeded)
    }

    private func sendAllow() async -> Bool {
        if case .success(let reply) = await ports.helper.setCharging(allow: true) {
            return reply.result == .done
        }
        return false
    }

    /// The adapter goes back on outside a pass: on the way out and before the helper is removed. Never sent while
    /// the registration is not enabled, nor to a helper older than protocol 2; never waited for past `limit`.
    private func sendEnable(waitingAtMost limit: Duration) async -> EnableOutcome {
        guard ports.registrar.registration == .enabled, adapterSwitchAvailable else { return .notSent }
        let helper = ports.helper
        switch await Self.bounded(by: limit, { await helper.setAdapter(enabled: true, leaseSeconds: 0) }) {
        case .success(let reply): return reply.result == .done ? .landed : .failed
        case .failure(.timedOut), nil: return .unanswered
        case .failure(.transport): return .failed
        }
    }

    /// The helper's reply, or nil once `limit` passed first; the call goes on and a late reply is dropped.
    private static func bounded<Value: Sendable>(
        by limit: Duration,
        _ call: @escaping @Sendable () async -> Result<Value, HelperCallError>
    ) async -> Result<Value, HelperCallError>? {
        guard limit > .zero else {
            Task { _ = await call() }
            return nil
        }
        var deadline: Task<Void, Never>?
        // The outer failure is the deadline; the helper's own answer, failures included, is the outer success.
        let raced: Result<Result<Value, HelperCallError>, HelperCallError> = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { once.resume(.success(await call())) }
            deadline = Task {
                guard (try? await Task.sleep(for: limit)) != nil else { return }
                once.resume(.failure(.timedOut))
            }
        }
        deadline?.cancel()
        return try? raced.get()
    }

    private static func result(_ outcome: Outcome, failure: ActionFailure) -> ActionResult {
        if case .failed = outcome { return .failed(failure) }
        return .succeeded
    }
}

/// What became of an adapter `enable` sent outside a pass.
private enum EnableOutcome {
    /// `failed` is refused or a broken connection; `unanswered` is a helper that stayed silent past the wait.
    case landed, failed, unanswered, notSent
}

/// A command the engine owed but could not send; logged once until it changes.
private struct NotSent: Equatable {
    let command: ChargeCommand
    let reason: CommandReason?
}
