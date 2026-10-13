import KombuchaCore
import SwiftUI

struct StatusHeader: View {
    let state: PanelState

    var body: some View {
        let header = Copy.header(for: state)
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if let level = header.level {
                    Text(level)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                if let title = header.title {
                    Label {
                        Text(title)
                    } icon: {
                        if let badge = StatusBadge.of(state) {
                            Image(systemName: badge.symbol)
                                .foregroundStyle(badge.tint)
                        }
                    }
                    .font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
            ForEach([header.detail, header.note].compactMap { $0 }, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
