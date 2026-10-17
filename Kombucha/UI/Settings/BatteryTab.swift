import KombuchaCore
import SwiftUI

struct BatteryTab: View {
    let model: AppModel
    @Environment(\.appearsActive) private var appearsActive

    /// How often the open tab samples (FR-SET-6).
    private static let interval = Duration.seconds(2)

    var body: some View {
        Form {
            Section {
                switch model.health {
                case .reading:
                    Text(Copy.reading)
                case .unavailable:
                    Text(Copy.unavailable)
                case .read(let health):
                    LabeledContent(Copy.cycleCount, value: String(health.cycleCount))
                    LabeledContent(Copy.maximumCapacity, value: Copy.percent(health.maximumCapacityPercent))
                    LabeledContent(Copy.conditionLabel, value: Copy.condition(health.condition))
                    LabeledContent(Copy.temperatureLabel, value: Copy.temperature(health.temperatureCelsius))
                    LabeledContent(Copy.voltageLabel, value: Copy.voltage(health.voltageVolts))
                }
            } header: {
                Text(Copy.batterySection)
            } footer: {
                Text(Copy.batteryRestLine)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent(Copy.systemRow, value: Copy.watts(model.power.readings?.systemWatts))
                if model.power.adapterShown {
                    LabeledContent(Copy.adapterRow, value: Copy.watts(model.power.readings?.adapterWatts))
                }
            } header: {
                Text(Copy.powerSection)
            } footer: {
                if model.power.adapterFallsShort {
                    Text(Copy.adapterFallsShort)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                apps
            } header: {
                Text(Copy.appsSection)
            } footer: {
                Text(Copy.appsFooter)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshHealth() }
        .onChange(of: appearsActive) { _, active in
            if active { model.refreshHealth() } else { model.pausePower() }
        }
        // The sample loop lives only while the tab is in front of an active window: it ends when the view goes
        // away or `appearsActive` changes, and nothing else keeps a timer (G-6). An inactive window keeps its
        // last numbers (only the baselines go, see `pausePower`); leaving the tab clears them. Each iteration also
        // re-reads the health rows, so the temperature and voltage follow the battery (FR-SET-4, one IORegistry read).
        .task(id: appearsActive) {
            guard appearsActive else { return }
            while !Task.isCancelled {
                model.refreshHealth()
                await model.refreshPower()
                try? await Task.sleep(for: Self.interval)
            }
        }
        .onDisappear { model.resetPower() }
    }

    @ViewBuilder
    private var apps: some View {
        if let apps = model.power.apps {
            if apps.isEmpty {
                Text(Copy.noApps)
            } else {
                ForEach(apps, id: \.name) { app in
                    LabeledContent(app.name, value: Copy.watts(app.watts))
                }
            }
        } else {
            Text(Copy.measuring)
        }
    }
}
