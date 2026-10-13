import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView(selection: Binding(get: { model.settingsTab }, set: { model.settingsTab = $0 })) {
            GeneralTab(model: model)
                .tabItem { Label(Copy.generalTab, systemImage: "gearshape") }
                .tag(SettingsTab.general)
            HelperTab(model: model)
                .tabItem { Label(Copy.helperTab, systemImage: "lock.shield") }
                .tag(SettingsTab.helper)
            BatteryTab(model: model)
                .tabItem { Label(Copy.batteryTab, systemImage: "battery.100percent") }
                .tag(SettingsTab.battery)
            HistoryTab(model: model)
                .tabItem { Label(Copy.historyTab, systemImage: "chart.xyaxis.line") }
                .tag(SettingsTab.history)
            AboutTab(model: model)
                .tabItem { Label(Copy.aboutTab, systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 460, maxWidth: 460, minHeight: 400, idealHeight: 620, maxHeight: .infinity)
        .background(VerticalResizeEnabler())
    }
}

/// SwiftUI strips `.resizable` from the Settings window right after it appears; this puts it back,
/// and again whenever SwiftUI removes it. The size limits stay SwiftUI's own, from `SettingsView.frame`.
private struct VerticalResizeEnabler: NSViewRepresentable {
    final class Coordinator {
        var observation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            let apply = { (window: NSWindow) in
                if !window.styleMask.contains(.resizable) { window.styleMask.insert(.resizable) }
            }
            apply(window)
            context.coordinator.observation = window.observe(\.styleMask) { window, _ in apply(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
