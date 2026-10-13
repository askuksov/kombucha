import Foundation
import KombuchaCore
import Synchronization
@testable import Kombucha

/// An in-memory history file. `replaceAll` stores what it is given, so a compaction shows up as a rewrite.
final class FakeHistoryStore: HistoryStoring, Sendable {
    private struct State {
        var records: [HistoryRecord]
        var failWrites = false
        var failLoads = false
        var replaceCalls = 0
    }

    private let state: Mutex<State>

    init(records: [HistoryRecord] = []) { state = Mutex(State(records: records)) }

    var records: [HistoryRecord] { state.withLock { $0.records } }
    var log: HistoryLog { HistoryLog(records: records) }
    var replaceCalls: Int { state.withLock { $0.replaceCalls } }
    func failWrites(_ fail: Bool) { state.withLock { $0.failWrites = fail } }
    func failLoads(_ fail: Bool) { state.withLock { $0.failLoads = fail } }

    /// A failed read returns an empty list, as the real file does.
    func load() -> [HistoryRecord] { state.withLock { $0.failLoads ? [] : $0.records } }

    func append(_ record: HistoryRecord) -> Bool {
        state.withLock {
            guard !$0.failWrites else { return false }
            $0.records.append(record)
            return true
        }
    }

    func replaceAll(with records: [HistoryRecord]) -> Bool {
        state.withLock {
            $0.replaceCalls += 1
            guard !$0.failWrites else { return false }
            $0.records = records
            return true
        }
    }
}

@MainActor
final class FakeAlertPoster: BatteryAlertPosting {
    private(set) var alerts: [BatteryAlert] = []
    func post(_ alert: BatteryAlert) { alerts.append(alert) }
}

/// A clock the tests move by hand.
final class TestClock: Sendable {
    private let moment: Mutex<Date>
    init(_ start: Date) { moment = Mutex(start) }
    var now: Date { moment.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { moment.withLock { $0 = $0.addingTimeInterval(seconds) } }
    func set(_ date: Date) { moment.withLock { $0 = date } }
}

/// A health reading the tests can change, and a count of how often it was read.
final class FakeHealth: Sendable {
    private struct State {
        var temperature: Double?
        var capacity: Int
        var reads = 0
    }

    private let state: Mutex<State>
    init(temperature: Double? = 30, capacity: Int = 92) { state = Mutex(State(temperature: temperature, capacity: capacity)) }

    var reads: Int { state.withLock { $0.reads } }
    func set(temperature: Double?) { state.withLock { $0.temperature = temperature } }
    func set(capacity: Int) { state.withLock { $0.capacity = capacity } }

    /// A missing temperature is a missing registry key, which `BatteryHealth.derive` turns into no health at all.
    func read() -> BatteryHealth? {
        state.withLock { state in
            state.reads += 1
            guard let temperature = state.temperature else { return nil }
            return BatteryHealth.derive(BatteryRegistryValues(cycleCount: 100,
                                                              designCapacity: 1000,
                                                              nominalChargeCapacity: state.capacity * 10,
                                                              permanentFailureStatus: 0,
                                                              temperature: Int(temperature * 100),
                                                              voltage: 12_000))
        }
    }
}
