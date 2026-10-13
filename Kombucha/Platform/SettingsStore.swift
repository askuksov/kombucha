import Foundation
import KombuchaCore

protocol SettingsStoring: Sendable {
    var chargeSettings: ChargeSettings { get }
    func setThresholds(lower: Int, upper: Int)
    func setBatteryProtection(_ on: Bool)
    func normalizeStoredThresholds()
}

/// The settings only the interface cares about. The engine's `SettingsStoring` stays as narrow as it was.
protocol UISettingsStoring: AnyObject, Sendable {
    var notifyFullChargeFinished: Bool { get }
    var notifyProtectionChanges: Bool { get }
    var notifyBatteryAttention: Bool { get }
    var welcomeCompleted: Bool { get }
    func setNotifyFullChargeFinished(_ on: Bool)
    func setNotifyProtectionChanges(_ on: Bool)
    func setNotifyBatteryAttention(_ on: Bool)
    func setWelcomeCompleted(_ done: Bool)
}

/// The app's user defaults. The engine reads its settings here and never from `UserDefaults`.
final class SettingsStore: SettingsStoring, UISettingsStoring, @unchecked Sendable {
    enum Key {
        static let lowerThreshold = "lowerThreshold"
        static let upperThreshold = "upperThreshold"
        static let batteryProtection = "batteryProtection"
        static let showPercentageInMenuBar = "showPercentageInMenuBar"
        static let notifyFullChargeFinished = "notifyFullChargeFinished"
        static let notifyProtectionChanges = "notifyProtectionChanges"
        static let notifyBatteryAttention = "notifyBatteryAttention"
        static let welcomeCompleted = "welcomeCompleted"
    }

    private let defaults: UserDefaults
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()

    init(defaults: UserDefaults, onChange: @escaping @Sendable () -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        defaults.register(defaults: [
            Key.lowerThreshold: Thresholds.standard.lower,
            Key.upperThreshold: Thresholds.standard.upper,
            Key.batteryProtection: true,
            Key.notifyFullChargeFinished: true,
            Key.notifyProtectionChanges: true,
            Key.notifyBatteryAttention: true,
        ])
    }

    var thresholds: Thresholds {
        lock.withLock { storedThresholds() }
    }

    var batteryProtection: Bool {
        lock.withLock { defaults.bool(forKey: Key.batteryProtection) }
    }

    var notifyFullChargeFinished: Bool {
        lock.withLock { defaults.bool(forKey: Key.notifyFullChargeFinished) }
    }

    var notifyProtectionChanges: Bool {
        lock.withLock { defaults.bool(forKey: Key.notifyProtectionChanges) }
    }

    var notifyBatteryAttention: Bool {
        lock.withLock { defaults.bool(forKey: Key.notifyBatteryAttention) }
    }

    var welcomeCompleted: Bool {
        lock.withLock { defaults.bool(forKey: Key.welcomeCompleted) }
    }

    var chargeSettings: ChargeSettings {
        lock.withLock {
            ChargeSettings(thresholds: storedThresholds(), protection: defaults.bool(forKey: Key.batteryProtection))
        }
    }

    func setThresholds(lower: Int, upper: Int) {
        let pair = Thresholds.normalized(lower: lower, upper: upper)
        write { [Key.lowerThreshold: pair.lower, Key.upperThreshold: pair.upper] }
    }

    func setBatteryProtection(_ on: Bool) {
        write { [Key.batteryProtection: on] }
    }

    func normalizeStoredThresholds() {
        write {
            let pair = storedThresholds()
            return [Key.lowerThreshold: pair.lower, Key.upperThreshold: pair.upper]
        }
    }

    // None of the four is a charge setting, so none of them wakes the engine.
    func setNotifyFullChargeFinished(_ on: Bool) { store(on, forKey: Key.notifyFullChargeFinished) }
    func setNotifyProtectionChanges(_ on: Bool) { store(on, forKey: Key.notifyProtectionChanges) }
    func setNotifyBatteryAttention(_ on: Bool) { store(on, forKey: Key.notifyBatteryAttention) }
    func setWelcomeCompleted(_ done: Bool) { store(done, forKey: Key.welcomeCompleted) }

    private func store(_ value: Bool, forKey key: String) {
        lock.withLock { defaults.set(value, forKey: key) }
    }

    // The lock is not recursive: this is the read path for code that already holds it.
    private func storedThresholds() -> Thresholds {
        Thresholds.normalized(lower: defaults.integer(forKey: Key.lowerThreshold),
                              upper: defaults.integer(forKey: Key.upperThreshold))
    }

    // The values are computed under the lock; a write that stores what is already stored emits nothing.
    private func write(_ values: () -> [String: AnyHashable]) {
        let changed = lock.withLock {
            let values = values()
            let changed = values.contains { key, value in defaults.object(forKey: key) as? AnyHashable != value }
            if changed {
                for (key, value) in values { defaults.set(value, forKey: key) }
            }
            return changed
        }
        if changed { onChange() }
    }
}
