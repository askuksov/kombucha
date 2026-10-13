import AppKit
import KombuchaCore
import SwiftUI
import Testing
@testable import Kombucha

private func controls(onAC: Bool = true, charging: Bool = false, protection: Bool = true, fullCharge: Bool = false,
                      heatHold: Bool = false, discharging: Bool = false) -> PanelState {
    .controls(ChargeSnapshot(level: 78, onAC: onAC, charging: charging, thresholds: .standard, protection: protection,
                             fullChargeActive: fullCharge, writePath: .ready, heatHold: heatHold, dischargeActive: discharging))
}

@Test func everyStateHasItsBadge() {
    #expect(StatusBadge.of(controls()) == StatusBadge(symbol: "checkmark.shield.fill", tint: .green))
    #expect(StatusBadge.of(controls(charging: true)) == StatusBadge(symbol: "shield.lefthalf.filled", tint: .orange))
    #expect(StatusBadge.of(controls(fullCharge: true)) == StatusBadge(symbol: "bolt.fill", tint: .orange))
    #expect(StatusBadge.of(controls(protection: false)) == StatusBadge(symbol: "powerplug.fill", tint: .secondary))
    #expect(StatusBadge.of(controls(onAC: false)) == StatusBadge(symbol: "battery.50percent", tint: .secondary))
    #expect(StatusBadge.of(controls(heatHold: true)) == StatusBadge(symbol: "thermometer.high", tint: .orange))
    #expect(StatusBadge.of(controls(discharging: true)) == StatusBadge(symbol: "battery.50percent", tint: .blue))
    #expect(StatusBadge.of(.writePathBlocked(.notFound, level: 78)) == StatusBadge(symbol: "exclamationmark.triangle.fill", tint: .orange))
    #expect(StatusBadge.of(.externalBatteryManager(.batt, level: 78)) == StatusBadge(symbol: "exclamationmark.triangle.fill", tint: .orange))
    #expect(StatusBadge.of(.unsupported(.noBattery)) == StatusBadge(symbol: "exclamationmark.triangle.fill", tint: .secondary))
    #expect(StatusBadge.of(.firstReading) == nil)
    for badge in [StatusBadge.of(controls()), StatusBadge.of(controls(heatHold: true)), StatusBadge.of(controls(discharging: true)), StatusBadge.of(.unsupported(.noBattery))].compactMap({ $0 }) {
        #expect(NSImage(systemSymbolName: badge.symbol, accessibilityDescription: nil) != nil)
    }
}

@Test(arguments: [MenuBarSymbol.resting, .charging, .fullCharge, .onBattery, .blocked])
func everyMenuBarSymbolHasItsImage(symbol: MenuBarSymbol) throws {
    // The test host is the app, so the asset catalog is the app's.
    let image = NSImage(named: try #require(symbol.assetName))
    #expect(image != nil)
    #expect(image?.isTemplate == true)
}

@Test func theHeatSymbolIsASystemSymbolWithoutAnAsset() {
    #expect(MenuBarSymbol.heatPaused.assetName == nil)
    let name = MenuBarSymbol.heatPaused.systemSymbolName
    #expect(name == "thermometer.medium")
    #expect(name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) } != nil)
    #expect(MenuBarSymbol.resting.systemSymbolName == nil)
}
