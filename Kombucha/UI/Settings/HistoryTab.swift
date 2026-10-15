import Charts
import KombuchaCore
import SwiftUI

/// Internal value labels for Swift Charts. Typed `String` constants, not literals: a literal resolves to the
/// `LocalizedStringKey` overload and the compiler would extract it into the string catalog.
enum ChartLabel {
    static let start: String = "Start"
    static let end: String = "End"
    static let min: String = "Min"
    static let max: String = "Max"
    static let state: String = "State"
    static let time: String = "Time"
    static let level: String = "Level"
    static let run: String = "Run"
    static let selected: String = "Selected"
    static let day: String = "Day"
    static let capacity: String = "Capacity"
}

struct HistoryTab: View {
    let model: AppModel
    @State private var range: HistoryRange = .week
    @State private var selected: HistoryDetail?
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Form {
            switch model.history {
            case .loading:
                Section { Text(Copy.reading) }
            case .empty:
                Section {
                    Text(Copy.historyEmpty)
                } footer: {
                    footer
                }
            case .ready(let content):
                levelSection(content)
                capacitySection(content)
            }
        }
        .formStyle(.grouped)
        // Loads when the tab appears and again whenever the window comes forward; reads a file, takes no samples.
        .task(id: appearsActive) {
            guard appearsActive else { return }
            await model.loadHistory()
        }
        .onDisappear { model.unloadHistory() }
        .onChange(of: range) { selected = nil }
    }

    private var footer: some View {
        Text(Copy.historyFooter)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelSection(_ content: AppModel.HistoryContent) -> some View {
        let chart = range == .week ? content.weekChart : content.monthChart
        return Section {
            Picker(Copy.rangeLabel, selection: $range) {
                Text(Copy.rangeWeek).tag(HistoryRange.week)
                Text(Copy.rangeMonth).tag(HistoryRange.month)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 8) {
                if let summary = chart.summary {
                    Text(Copy.historySummary(restedPercent: summary.restedPercent, recorded: summary.recorded))
                        .font(.subheadline.weight(.medium))
                }
                HistoryLevelChart(chart: chart, selected: $selected)
                if !chart.buckets.isEmpty {
                    HistoryLegend(chart: chart)
                    detailSlot
                }
            }
        } header: {
            Text(Copy.levelSection)
        }
    }

    /// A fixed-height slot, so nothing moves when the pointer comes and goes.
    private var detailSlot: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let selected {
                Text(Copy.historyDetail(selected)).monospacedDigit()
            } else {
                Text(Copy.historyRestLine)
                Text(Copy.historyHint).foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
    }

    private func capacitySection(_ content: AppModel.HistoryContent) -> some View {
        Section {
            if content.health.count < 2 {
                Text(Copy.capacityTooFew)
            } else {
                // Indexed ids: two health points can share a day after a clock correction.
                Chart(Array(content.health.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value(ChartLabel.day, point.day), y: .value(ChartLabel.capacity, point.maximumCapacityPercent))
                    PointMark(x: .value(ChartLabel.day, point.day), y: .value(ChartLabel.capacity, point.maximumCapacityPercent))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(Copy.axisDay(date)) }
                        }
                    }
                }
                .frame(height: 120)
                .accessibilityLabel(Copy.maximumCapacity)
            }
        } header: {
            Text(Copy.maximumCapacity)
        } footer: {
            footer
        }
    }
}
