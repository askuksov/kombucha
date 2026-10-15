import Charts
import KombuchaCore
import SwiftUI

struct HistoryLevelChart: View {
    let chart: HistoryChart
    @Binding var selected: HistoryDetail?

    /// The window width is fixed, so the plot width is a constant the minimum run width can rely on.
    private static let plotWidth = 380.0
    private static let minimumRunPoints = 1.5
    /// About half a 7-day label (centred on its noon) and a whole 30-day label (starts at its Monday).
    private static let weekLabelMargin = 22.0
    private static let monthLabelWidth = 46.0
    private static let rowHeight: CGFloat = 5

    private var floor: Double { Double(chart.yFloor) }
    private var span: Double { 100 - floor }
    private var rowPitch: Double { span * 0.045 }
    private var lanes: [(offset: Int, element: HistoryLane)] { Array(HistoryLane.allCases.enumerated()) }

    /// The middle of a lane row, in level units, below the floor.
    private func rowY(_ index: Int) -> Double { floor - span * 0.06 - rowPitch * (Double(index) + 0.5) }
    private var bottom: Double { rowY(HistoryLane.allCases.count - 1) - rowPitch }

    var body: some View {
        Chart {
            limitMarks
            laneMarks
            lineMarks
            selectionMarks
        }
        .chartYScale(domain: bottom...100)
        .chartXScale(domain: chart.periodStart...chart.periodEnd)
        .chartYAxis {
            AxisMarks(position: .trailing, values: chart.yTicks.map(Double.init)) { value in
                // The dashed accent rules are drawn at the limit ticks, so no solid line there.
                if let tick = value.as(Double.self), !isLimitTick(tick) {
                    AxisGridLine()
                }
                AxisValueLabel {
                    if let tick = value.as(Double.self) {
                        let isLimit = isLimitTick(tick)
                        Text(verbatim: String(Int(tick)))
                            .fontWeight(isLimit ? .semibold : .regular)
                            .foregroundStyle(isLimit ? Color.accentColor : Color.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: ruleDates) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
            AxisMarks(values: labelDates) { value in
                AxisValueLabel(anchor: chart.range == .week ? .top : .topLeading) {
                    if let date = value.as(Date.self) {
                        Text(chart.range == .week ? Copy.axisWeekdayAndDay(date) : Copy.axisMonthAndDay(date))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in hatch(proxy) }
        .chartOverlay { proxy in pointer(proxy) }
        .overlay { if chart.buckets.isEmpty { emptyNote } }
        .frame(height: 220)
        .accessibilityLabel(Copy.levelSection)
        .accessibilityValue(chart.summary.map { Copy.historySummary(restedPercent: $0.restedPercent, recorded: $0.recorded) }
                            ?? Copy.historyNothingRecorded(days: Int(chart.range.span / 86_400)))
    }

    // MARK: marks

    @ChartContentBuilder private var limitMarks: some ChartContent {
        if let limit = chart.limit {
            RectangleMark(xStart: .value(ChartLabel.start, chart.periodStart),
                          xEnd: .value(ChartLabel.end, chart.periodEnd),
                          yStart: .value(ChartLabel.min, Double(limit.lower)),
                          yEnd: .value(ChartLabel.max, Double(limit.upper)))
                .foregroundStyle(Color.accentColor.opacity(0.08))
            ForEach([limit.lower, limit.upper], id: \.self) { value in
                RuleMark(y: .value(ChartLabel.level, Double(value)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }
        }
    }

    @ChartContentBuilder private var laneMarks: some ChartContent {
        ForEach(lanes, id: \.offset) { row in
            RectangleMark(xStart: .value(ChartLabel.start, chart.periodStart),
                          xEnd: .value(ChartLabel.end, chart.periodEnd),
                          y: .value(ChartLabel.state, rowY(row.offset)),
                          height: .fixed(Self.rowHeight))
                .foregroundStyle(Color.secondary.opacity(0.08))
            ForEach(chart.runs(for: row.element)) { run in
                RectangleMark(xStart: .value(ChartLabel.start, run.start),
                              xEnd: .value(ChartLabel.end, widenedEnd(of: run)),
                              y: .value(ChartLabel.state, rowY(row.offset)),
                              height: .fixed(Self.rowHeight))
                    .foregroundStyle(laneColor(row.element))
            }
        }
    }

    @ChartContentBuilder private var lineMarks: some ChartContent {
        ForEach(chart.buckets, id: \.index) { bucket in
            LineMark(x: .value(ChartLabel.time, bucket.start),
                     y: .value(ChartLabel.level, Double(bucket.level)),
                     series: .value(ChartLabel.run, bucket.segment))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(Color.primary)
        }
        ForEach(shortSegmentDots, id: \.index) { bucket in
            PointMark(x: .value(ChartLabel.time, bucket.start), y: .value(ChartLabel.level, Double(bucket.level)))
                .symbolSize(16)
                .foregroundStyle(Color.primary)
        }
    }

    /// One dot per short segment (its last bucket), so neighbouring dots do not merge into a blob.
    private var shortSegmentDots: [HistoryBucket] {
        Dictionary(grouping: chart.shortSegmentBuckets, by: \.segment)
            .compactMap { $0.value.last }
            .sorted { $0.index < $1.index }
    }

    @ChartContentBuilder private var selectionMarks: some ChartContent {
        if let selected {
            // The first slot can start before the period; keep the marks inside the X domain.
            let x = max(selected.start, chart.periodStart)
            RuleMark(x: .value(ChartLabel.selected, x),
                     yStart: .value(ChartLabel.min, bottom),
                     yEnd: .value(ChartLabel.max, 100.0))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.secondary)
            if let level = selected.level {
                PointMark(x: .value(ChartLabel.selected, x), y: .value(ChartLabel.level, Double(level)))
                    .symbolSize(40)
                    .foregroundStyle(Color.primary)
            }
        }
    }

    private func laneColor(_ lane: HistoryLane) -> Color {
        switch lane {
        case .charging: .green
        case .resting: .accentColor
        case .onBattery: .secondary
        }
    }

    /// A run narrower than 1.5 pt is drawn 1.5 pt wide, so one 15-minute burst still shows.
    private func widenedEnd(of run: HistoryRun) -> Date {
        let seconds = chart.periodEnd.timeIntervalSince(chart.periodStart)
        let minimum = seconds / Self.plotWidth * Self.minimumRunPoints
        return min(max(run.end, run.start.addingTimeInterval(minimum)), chart.periodEnd)
    }

    private func isLimitTick(_ tick: Double) -> Bool {
        guard let limit = chart.limit else { return false }
        return Int(tick) == limit.lower || Int(tick) == limit.upper
    }

    // MARK: axes

    private var interval: DateInterval { DateInterval(start: chart.periodStart, end: chart.periodEnd) }

    /// 7 days: every midnight. 30 days: every Monday.
    private var ruleDates: [Date] {
        let components = chart.range == .week ? DateComponents(hour: 0, minute: 0)
                                              : DateComponents(hour: 0, minute: 0, weekday: 2)
        return Self.dates(matching: components, in: interval)
    }

    /// 7 days: noon of each day, so the label is centred under it. 30 days: the Monday rule itself.
    /// A label that would not fit before the edge of the plot is dropped; the rules stay.
    private var labelDates: [Date] {
        let perPoint = interval.duration / Self.plotWidth
        guard chart.range == .week else {
            let latest = chart.periodEnd.addingTimeInterval(-perPoint * Self.monthLabelWidth)
            return ruleDates.filter { $0 <= latest }
        }
        let margin = perPoint * Self.weekLabelMargin
        let noons = [Calendar.current.startOfDay(for: chart.periodStart)] + ruleDates
        return noons.map { $0.addingTimeInterval(12 * 3_600) }.filter {
            $0 >= chart.periodStart.addingTimeInterval(margin) && $0 <= chart.periodEnd.addingTimeInterval(-margin)
        }
    }

    private static func dates(matching components: DateComponents, in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        Calendar.current.enumerateDates(startingAfter: interval.start, matching: components,
                                        matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date <= interval.end else {
                stop = true
                return
            }
            result.append(date)
        }
        return result
    }

    // MARK: hatch, pointer, empty note

    private func hatch(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame, !chart.buckets.isEmpty {
                let plot = geometry[anchor]
                ForEach(chart.gaps) { gap in
                    if let start = proxy.position(forX: gap.start), let end = proxy.position(forX: gap.end), end > start {
                        let width = end - start
                        HatchShape()
                            .stroke(Color.secondary.opacity(0.17), lineWidth: 1)
                            .frame(width: width, height: plot.height)
                            .clipped()
                            .overlay {
                                if width >= 44 {
                                    Text(Copy.legendNoData)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            .offset(x: plot.minX + start, y: plot.minY)
                    }
                }
            }
        }
    }

    private func pointer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .pointerStyle(.rectSelection)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): select(at: location, proxy: proxy, geometry: geometry)
                    case .ended: selected = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { select(at: $0.location, proxy: proxy, geometry: geometry) }
                    .onEnded { _ in selected = nil })
        }
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard !chart.buckets.isEmpty, let anchor = proxy.plotFrame else {
            selected = nil
            return
        }
        let x = location.x - geometry[anchor].origin.x
        selected = proxy.value(atX: x, as: Date.self).flatMap(chart.detail(at:))
    }

    private var emptyNote: some View {
        VStack(spacing: 2) {
            Text(Copy.historyNothingRecorded(days: Int(chart.range.span / 86_400)))
            Text(Copy.historyAwakeNote).foregroundStyle(.secondary)
        }
        .font(.callout)
        .multilineTextAlignment(.center)
    }
}
