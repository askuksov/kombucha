import KombuchaCore
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel
    @AppStorage(SettingsStore.Key.showPercentageInMenuBar) private var showPercentage = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private func image(for symbol: MenuBarSymbol) -> Image {
        if let asset = symbol.assetName { return Image(asset) }
        return Image(systemName: symbol.systemSymbolName ?? "questionmark")
    }

    var body: some View {
        let symbol = MenuBarSymbol.symbol(snapshot: model.snapshot, supported: model.verdict == .supported)
        HStack(spacing: 2) {
            image(for: symbol)
                .renderingMode(.template)
            if showPercentage, let snapshot = model.snapshot {
                Text(Copy.percent(snapshot.displayLevel))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.menuBarAccessibilityLabel(PanelState.make(snapshot: model.snapshot, verdict: model.verdict)))
        .task(id: model.welcomePending) {
            guard model.welcomePending else { return }
            openWindow(id: WelcomeView.windowID)
        }
        .onAppear {
            // The only view that exists from launch, so the only place to hand the model a working
            // `openSettings` — a notification click has no view of its own to read it from.
            model.openSettingsAction = { openSettings() }
        }
    }
}
