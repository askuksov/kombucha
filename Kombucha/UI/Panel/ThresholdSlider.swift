import SwiftUI

/// One threshold: the label row and a drawn slider. The stock `Slider` renders its thumb see-through in the
/// panel's translucent window, so the track, fill and thumb are drawn here. A drag commits when it ends;
/// the thumb stops at the partner's limit.
struct ThresholdSlider: View {
    let title: String
    let stored: Int
    let bounds: ClosedRange<Int>
    // AppModel's methods are main-actor isolated; Swift 6 rejects passing them as plain closures.
    let clamp: @MainActor (Int) -> Int
    let commit: @MainActor (Int) -> Void

    @State private var draft: Int?

    private nonisolated static let height: CGFloat = 22

    var body: some View {
        let shown = draft ?? stored
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(Copy.percent(shown))
                    .monospacedDigit()
            }
            .accessibilityHidden(true)
            GeometryReader { proxy in
                let offset = Self.thumbOffset(of: shown, width: proxy.size.width, bounds: bounds)
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.24))
                    Capsule().fill(.white).frame(width: offset + Self.height)
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .frame(width: Self.height, height: Self.height)
                        .offset(x: offset)
                }
                // The hairline edge the system's own sliders have; it keeps the track apart from the panel.
                .overlay(Capsule().strokeBorder(.primary.opacity(0.22), lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        draft = clamp(Self.value(forX: drag.location.x, width: proxy.size.width, bounds: bounds))
                    }
                    .onEnded { _ in
                        if let draft { commit(draft) }
                    })
            }
            .frame(height: Self.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(Copy.sliderAccessibilityValue(shown))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : -1
                let next = clamp(shown + step)
                draft = next
                commit(next)
            }
        }
        .onChange(of: stored) {
            draft = nil
        }
    }

    /// The whole percent under a touch at `x`; the thumb's centre travels between half a thumb from each end.
    nonisolated static func value(forX x: CGFloat, width: CGFloat, bounds: ClosedRange<Int>) -> Int {
        let travel = width - height
        guard travel > 0 else { return bounds.lowerBound }
        let fraction = min(max((x - height / 2) / travel, 0), 1)
        let span = Double(bounds.upperBound - bounds.lowerBound)
        return bounds.lowerBound + Int((Double(fraction) * span).rounded())
    }

    /// The thumb's leading edge for `value`; the inverse of `value(forX:width:bounds:)`.
    nonisolated static func thumbOffset(of value: Int, width: CGFloat, bounds: ClosedRange<Int>) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0, width > height else { return 0 }
        let fraction = CGFloat(min(max(value, bounds.lowerBound), bounds.upperBound) - bounds.lowerBound) / CGFloat(span)
        return fraction * (width - height)
    }
}
