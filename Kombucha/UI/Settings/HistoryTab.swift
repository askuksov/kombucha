import Charts
import KombuchaCore
import SwiftUI

/// Internal value labels for Swift Charts. Typed `String` constants, not literals: a literal resolves to the
/// `LocalizedStringKey` overload and the compiler would extract it into the string catalog.
private enum ChartLabel {
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
    @State private var selection: Date?
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
    }

    private var footer: some View {
        Text(Copy.historyFooter)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buckets(_ content: AppModel.HistoryContent) -> [HistoryBucket] {
        range == .week ? content.week : content.month
    }

    private func levelSection(_ content: AppModel.HistoryContent) -> some View {
        let buckets = buckets(content)
        // A segment with one bucket draws no line, so its bucket gets a point instead.
        let segmentSizes = Dictionary(grouping: buckets, by: \.segment).mapValues(\.count)
        return Section {
            Picker(Copy.rangeLabel, selection: $range) {
                Text(Copy.rangeWeek).tag(HistoryRange.week)
                Text(Copy.rangeMonth).tag(HistoryRange.month)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if buckets.isEmpty {
                Text(Copy.historyPeriodEmpty)
            } else {
                Chart {
                    ForEach(buckets, id: \.index) { bucket in
                        if let band = band(for: bucket) {
                            RectangleMark(xStart: .value(ChartLabel.start, bucket.start),
                                          xEnd: .value(ChartLabel.end, bucket.start.addingTimeInterval(range.bucket)),
                                          yStart: .value(ChartLabel.min, 0),
                                          yEnd: .value(ChartLabel.max, 100))
                                .foregroundStyle(by: .value(ChartLabel.state, band))
                                .opacity(0.25)
                        }
                    }
                    ForEach(buckets, id: \.index) { bucket in
                        LineMark(x: .value(ChartLabel.time, bucket.start),
                                 y: .value(ChartLabel.level, bucket.level),
                                 series: .value(ChartLabel.run, bucket.segment))
                            .foregroundStyle(Color.primary)
                    }
                    ForEach(buckets.filter { segmentSizes[$0.segment] == 1 }, id: \.index) { bucket in
                        PointMark(x: .value(ChartLabel.time, bucket.start),
                                  y: .value(ChartLabel.level, bucket.level))
                            .foregroundStyle(Color.primary)
                    }
                    if let picked = picked(in: buckets) {
                        RuleMark(x: .value(ChartLabel.selected, picked.start))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartForegroundStyleScale(domain: [Copy.legendCharging, Copy.legendResting],
                                           range: [Color.green, Color.accentColor])
                .chartXScale(domain: content.generatedAt.addingTimeInterval(-range.span)...content.generatedAt)
                .chartYScale(domain: 0...100)
                .chartXSelection(value: $selection)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(Copy.axisDay(date)) }
                        }
                    }
                }
                .frame(height: 220)
                .accessibilityLabel(Copy.levelSection)
                if let picked = picked(in: buckets) {
                    HStack {
                        Text(Copy.timestamp(picked.start))
                        Spacer()
                        Text(Copy.percent(picked.level))
                        if let temperature = picked.peakTemperatureCelsius {
                            Text(Copy.temperature(temperature))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(Copy.levelSection)
        }
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

    /// The legend names the state, so color is never the only carrier (NFR-7). Charging wins over resting.
    private func band(for bucket: HistoryBucket) -> String? {
        if bucket.charging { return Copy.legendCharging }
        if bucket.resting { return Copy.legendResting }
        return nil
    }

    private func picked(in buckets: [HistoryBucket]) -> HistoryBucket? {
        guard let selection else { return nil }
        return buckets.min { abs($0.start.timeIntervalSince(selection)) < abs($1.start.timeIntervalSince(selection)) }
    }
}
