import KombuchaCore
import Synchronization
@testable import Kombucha

/// Records what intents asked for and answers with a scripted status or error.
final class FakeGateway: EngineGateway {
    private struct State {
        var calls: [String] = []
        var status = BatteryStatus(level: 78, mode: .protected, thresholds: .standard, protection: true,
                                   holdingLimit: true, line: "Protected: Battery resting 75% – 80%")
        var error: GatewayError?
    }

    private let state = Mutex(State())

    var calls: [String] { state.withLock { $0.calls } }
    func answer(_ status: BatteryStatus) { state.withLock { $0.status = status } }
    func fail(with error: GatewayError) { state.withLock { $0.error = error } }

    private func record(_ call: String) throws {
        let error = state.withLock { state in
            state.calls.append(call)
            return state.error
        }
        if let error { throw error }
    }

    func status() async throws -> BatteryStatus {
        try record("status")
        return state.withLock { $0.status }
    }

    func setProtection(_ on: Bool) async throws -> Bool {
        try record("protection \(on)")
        return on
    }

    func startFullCharge() async throws { try record("start") }

    func stopFullCharge() async throws { try record("stop") }

    func setThresholds(stop: Int, resume: Int) async throws -> Thresholds {
        try record("limit \(stop) \(resume)")
        return .normalized(lower: resume, upper: stop)
    }
}
