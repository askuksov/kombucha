import KombuchaCore
import Synchronization

/// Scripted watts and energy samples. Each `sampleEnergy` call hands out the next reading and then repeats
/// the last, so a test can take as many steps as it likes.
final class PowerFeed: Sendable {
    private struct State {
        var readings: PowerReadings
        var energy: [EnergyReading]
        var energyCalls = 0
        var powerCalls = 0
    }

    private let state: Mutex<State>

    init(readings: PowerReadings = PowerReadings(systemWatts: 5, adapterWatts: 6), energy: [EnergyReading]) {
        state = Mutex(State(readings: readings, energy: energy))
    }

    var readPower: @Sendable () -> PowerReadings {
        { [self] in state.withLock { $0.powerCalls += 1; return $0.readings } }
    }

    var sampleEnergy: @Sendable () -> EnergyReading {
        { [self] in
            state.withLock { state in
                let index = min(state.energyCalls, state.energy.count - 1)
                state.energyCalls += 1
                return state.energy[index]
            }
        }
    }

    func setReadings(_ readings: PowerReadings) { state.withLock { $0.readings = readings } }
    var powerCalls: Int { state.withLock { $0.powerCalls } }
}

func energyReading(_ seconds: Double, _ rows: [(Int32, String, UInt64)]) -> EnergyReading {
    EnergyReading(samples: rows.map { EnergySample(pid: $0.0, executablePath: $0.1, energyNanojoules: $0.2) },
                  seconds: seconds)
}
