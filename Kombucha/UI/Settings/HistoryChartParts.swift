import KombuchaCore
import SwiftUI

/// 45° lines, 5 pt apart, drawn over a rectangle; clipped by the caller.
struct HatchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = 5 * 2.0.squareRoot()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}

/// Lays its children out left to right and wraps to a new line when the next one does not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Swatches that are miniatures of the marks, so a state reads without its color.
struct HistoryLegend: View {
    let chart: HistoryChart

    var body: some View {
        FlowLayout {
            item(Copy.legendCharging) { lane(row: 0, color: .green) }
            item(Copy.legendResting) { lane(row: 1, color: Color.accentColor) }
            item(Copy.legendOnBattery) { lane(row: 2, color: Color.secondary) }
            item(Copy.legendNoData) {
                HatchShape()
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    .frame(width: 14, height: 10)
                    .clipped()
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
            }
            if let limit = chart.limit {
                item(Copy.currentLimit(limit)) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                        .frame(width: 14, height: 10)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The three lane rows in chart order (charging, resting, on battery); only `row` is filled.
    private func lane(row: Int, color: Color) -> some View {
        VStack(spacing: 1.1) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(index == row ? color : Color.secondary.opacity(0.12))
                    .frame(width: 16, height: 2.6)
            }
        }
    }

    private func item<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
