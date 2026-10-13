import AppIntents

struct KombuchaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFullChargeIntent(),
                    phrases: ["Charge to 100% once with \(.applicationName)"],
                    shortTitle: "Start Full Charge",
                    systemImageName: "bolt.fill")
        AppShortcut(intent: GetBatteryStatusIntent(),
                    phrases: ["\(.applicationName) battery status"],
                    shortTitle: "Get Battery Status",
                    systemImageName: "battery.75percent")
    }
}
