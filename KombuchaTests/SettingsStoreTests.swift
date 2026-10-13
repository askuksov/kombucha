import Foundation
import KombuchaCore
import Testing
@testable import Kombucha

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private func withStore(_ body: (SettingsStore, UserDefaults, ChangeCounter) -> Void) {
    let suite = "dev.kuksov.kombucha.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let changes = ChangeCounter()
    let store = SettingsStore(defaults: defaults) { changes.increment() }
    body(store, defaults, changes)
}

@Test func anEmptyStoreHoldsTheDefaults() {
    withStore { store, _, changes in
        #expect(store.chargeSettings == ChargeSettings(thresholds: .standard, protection: true))
        #expect(changes.count == 0)
    }
}

@Test func aBrokenStoredPairIsNormalizedAtLaunchAndReported() {
    withStore { store, defaults, changes in
        defaults.set(90, forKey: SettingsStore.Key.lowerThreshold)
        defaults.set(60, forKey: SettingsStore.Key.upperThreshold)
        let expected = Thresholds.normalized(lower: 90, upper: 60)
        store.normalizeStoredThresholds()
        #expect(defaults.integer(forKey: SettingsStore.Key.lowerThreshold) == expected.lower)
        #expect(defaults.integer(forKey: SettingsStore.Key.upperThreshold) == expected.upper)
        #expect(changes.count == 1)
    }
}

@Test func normalizingAValidPairStoresItWithoutReportingAChange() {
    withStore { store, defaults, changes in
        defaults.set(70, forKey: SettingsStore.Key.lowerThreshold)
        defaults.set(80, forKey: SettingsStore.Key.upperThreshold)
        store.normalizeStoredThresholds()
        #expect(store.thresholds == Thresholds.normalized(lower: 70, upper: 80))
        #expect(changes.count == 0)
    }
}

@Test func aBrokenPairReadsNormalizedEvenBeforeItIsRewritten() {
    withStore { store, defaults, _ in
        defaults.set(10, forKey: SettingsStore.Key.lowerThreshold)
        defaults.set(300, forKey: SettingsStore.Key.upperThreshold)
        #expect(store.thresholds == Thresholds.normalized(lower: 10, upper: 300))
    }
}

@Test func aThresholdWriteIsNormalizedAndReportedOnce() {
    withStore { store, _, changes in
        store.setThresholds(lower: 84, upper: 85)
        #expect(store.thresholds == Thresholds.normalized(lower: 84, upper: 85))
        #expect(changes.count == 1)
    }
}

@Test func writingTheStoredValueReportsNothing() {
    withStore { store, _, changes in
        store.setThresholds(lower: 70, upper: 80)
        store.setThresholds(lower: 70, upper: 80)
        store.setBatteryProtection(false)
        store.setBatteryProtection(false)
        #expect(changes.count == 2)
    }
}

@Test func aProtectionWriteIsStoredAndReported() {
    withStore { store, _, changes in
        store.setBatteryProtection(false)
        #expect(store.chargeSettings.protection == false)
        #expect(changes.count == 1)
    }
}

@Test func theUISwitchesStartOnAndTheWelcomeIsUnseen() {
    withStore { store, _, changes in
        #expect(store.notifyFullChargeFinished)
        #expect(store.notifyProtectionChanges)
        #expect(!store.welcomeCompleted)
        #expect(changes.count == 0)
    }
}

@Test func aUISwitchIsStoredAndTellsNobody() {
    withStore { store, defaults, changes in
        store.setNotifyFullChargeFinished(false)
        store.setNotifyProtectionChanges(false)
        store.setWelcomeCompleted(true)
        #expect(!defaults.bool(forKey: SettingsStore.Key.notifyFullChargeFinished))
        #expect(!defaults.bool(forKey: SettingsStore.Key.notifyProtectionChanges))
        #expect(defaults.bool(forKey: SettingsStore.Key.welcomeCompleted))
        // None of the four is a charge setting: the engine must not be woken for them.
        #expect(changes.count == 0)
    }
}

@Test func aReaderNeverSeesHalfOfAThresholdWrite() async {
    let suite = "dev.kuksov.kombucha.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults) {}
    let pairs = [Thresholds.normalized(lower: 70, upper: 80), Thresholds.normalized(lower: 60, upper: 90)]
    store.setThresholds(lower: 70, upper: 80)
    let writer = Task.detached {
        for index in 0..<2_000 {
            let pair = pairs[index % 2]
            store.setThresholds(lower: pair.lower, upper: pair.upper)
        }
    }
    let reader = Task.detached {
        var mixed = 0
        for _ in 0..<2_000 where !pairs.contains(store.chargeSettings.thresholds) {
            mixed += 1
        }
        return mixed
    }
    await writer.value
    #expect(await reader.value == 0)
}

@Test func theBatteryAttentionSwitchIsOnByDefaultAndStoredWithoutWakingTheEngine() {
    withStore { store, defaults, changes in
        #expect(store.notifyBatteryAttention)
        store.setNotifyBatteryAttention(false)
        #expect(!store.notifyBatteryAttention)
        #expect(!defaults.bool(forKey: SettingsStore.Key.notifyBatteryAttention))
        #expect(changes.count == 0)
    }
}
