import KombuchaCore
import SwiftUI

/// The symbol and color beside the status line. The color never stands alone: the symbol and text say it too.
struct StatusBadge: Equatable {
    let symbol: String
    let tint: Color

    static func of(_ state: PanelState) -> StatusBadge? {
        switch state {
        case .firstReading:
            nil
        case .unsupported:
            StatusBadge(symbol: "exclamationmark.triangle.fill", tint: .secondary)
        case .writePathBlocked, .externalBatteryManager:
            StatusBadge(symbol: "exclamationmark.triangle.fill", tint: .orange)
        case .controls(let snapshot):
            switch snapshot.mode {
            case .protected: StatusBadge(symbol: "checkmark.shield.fill", tint: .green)
            case .charging: StatusBadge(symbol: "shield.lefthalf.filled", tint: .orange)
            case .fullCharge: StatusBadge(symbol: "bolt.fill", tint: .orange)
            case .protectionOff: StatusBadge(symbol: "powerplug.fill", tint: .secondary)
            case .onBattery: StatusBadge(symbol: "battery.50percent", tint: .secondary)
            case .heatPaused: StatusBadge(symbol: "thermometer.high", tint: .orange)
            case .discharging: StatusBadge(symbol: "battery.50percent", tint: .blue)
            }
        }
    }
}

extension MenuBarSymbol {
    /// The asset-catalog image; nil for a symbol that is drawn from an SF Symbol.
    var assetName: String? {
        switch self {
        case .resting: "menubar.resting"
        case .charging: "menubar.charging"
        case .fullCharge: "menubar.fullCharge"
        case .onBattery: "menubar.onBattery"
        case .blocked: "menubar.blocked"
        case .heatPaused: nil
        }
    }

    /// The SF Symbol of a symbol that has no asset-catalog image yet; a custom image can replace it later.
    var systemSymbolName: String? {
        self == .heatPaused ? "thermometer.medium" : nil
    }
}
