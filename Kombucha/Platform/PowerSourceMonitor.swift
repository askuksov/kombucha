import Foundation
import IOKit.ps
import KombuchaCore

/// The internal battery through IOPowerSources: read on demand, and every change posted to the engine.
final class PowerSourceMonitor: PowerSource, EventSource, @unchecked Sendable {
    enum Key {
        static let type = "Type"
        static let internalBattery = "InternalBattery"
        static let currentCapacity = "Current Capacity"
        static let maxCapacity = "Max Capacity"
        static let powerSourceState = "Power Source State"
        static let acPower = "AC Power"
        static let isCharging = "Is Charging"
    }

    let name = "power source"
    private let inbox: EngineInbox
    private let lock = NSLock()
    private var source: CFRunLoopSource?

    init(inbox: EngineInbox) {
        self.inbox = inbox
    }

    deinit {
        stop()
    }

    var hasInternalBattery: Bool {
        Self.internalBatteryDescription() != nil
    }

    func read() -> PowerReading? {
        guard var reading = Self.internalBatteryDescription().flatMap(Self.reading(from:)) else { return nil }
        // One IORegistry read per power event or tick: the temperature for Heat Protection and the cable for a
        // discharge. A failed read leaves both nil.
        let registry = BatteryHealthReader.registryReading()
        reading.temperatureCelsius = registry.temperatureCelsius
        reading.adapterPresent = registry.adapterPresent
        return reading
    }

    /// False when already started or when IOKit gives no source.
    func start() -> Bool {
        lock.withLock {
            guard source == nil else { return false }
            // The source never outlives the monitor: stop() removes it.
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let created = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue().powerChanged()
            }, context)?.takeRetainedValue() else { return false }
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
            source = created
            return true
        }
    }

    func stop() {
        lock.withLock {
            guard let source else { return }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            self.source = nil
        }
    }

    private func powerChanged() {
        if let reading = read() {
            inbox.post(.powerChanged(reading))
        }
    }

    /// Nil unless both capacities are there and the maximum is positive.
    static func reading(from description: [String: Any]) -> PowerReading? {
        guard let current = description[Key.currentCapacity] as? Int,
              let maximum = description[Key.maxCapacity] as? Int,
              maximum > 0 else { return nil }
        let level = Double(current) / Double(maximum) * 100
        guard level.isFinite else { return nil }
        return PowerReading(level: min(max(level, 0), 100),
                            onAC: description[Key.powerSourceState] as? String == Key.acPower,
                            charging: description[Key.isCharging] as? Bool ?? false)
    }

    static func internalBattery(in descriptions: [[String: Any]]) -> [String: Any]? {
        descriptions.first { $0[Key.type] as? String == Key.internalBattery }
    }

    private static func internalBatteryDescription() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() else { return nil }
        let descriptions = (list as [CFTypeRef]).compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return internalBattery(in: descriptions)
    }
}
