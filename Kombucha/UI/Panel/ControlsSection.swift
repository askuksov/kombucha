import KombuchaCore
import SwiftUI

struct ControlsSection: View {
    let model: AppModel
    let snapshot: ChargeSnapshot

    // One track for both thresholds, so equal values sit at the same place.
    private static let bleed: CGFloat = 4
    private static let track = Thresholds.lowerRange.lowerBound...Thresholds.upperRange.upperBound

    var body: some View {
        let protection = model.pendingProtection ?? snapshot.protection
        let fullCharge = model.pendingFullCharge ?? snapshot.fullChargeActive
        let range = snapshot.thresholds
        VStack(alignment: .leading, spacing: 8) {
            // The tiles and the button reach 4 pt closer to the panel's edge than the text above and below.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Copy.protectionSwitch)
                        .accessibilityHidden(true)
                    Spacer()
                    Toggle(Copy.protectionSwitch, isOn: Binding(get: { protection }, set: { on in
                        Task { await model.setProtection(on) }
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                .accessibilityElement(children: .contain)
                .disabled(model.isPending)
                .controlTile()
                ThresholdSlider(title: Copy.stopSlider, stored: range.upper, bounds: Self.track,
                                clamp: { range.movingUpper(to: $0).upper },
                                commit: model.setUpper)
                    .controlTile()
                ThresholdSlider(title: Copy.resumeSlider, stored: range.lower, bounds: Self.track,
                                clamp: { range.movingLower(to: $0).lower },
                                commit: model.setLower)
                    .controlTile()
                fullChargeButton(active: fullCharge)
                dischargeControl()
            }
            .padding(.horizontal, -Self.bleed)
            if let failure = model.controlFailure {
                FailureNote(failure: failure)
            }
        }
    }

    @ViewBuilder
    private func fullChargeButton(active: Bool) -> some View {
        if active {
            Button {
                Task { await model.setFullCharge(false) }
            } label: {
                Text(Copy.fullChargeStop).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.isPending)
        } else {
            Button {
                Task { await model.setFullCharge(true) }
            } label: {
                Label(Copy.fullChargeStart, systemImage: "bolt.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isPending || !snapshot.onAC)
        }
    }

    /// Which discharge button the panel shows. The stop button replaces the start button while a discharge runs;
    /// the start button shows only while a discharge could start now.
    enum DischargeButton: Equatable {
        case start(upper: Int)
        case stop
    }

    nonisolated static func dischargeButton(for snapshot: ChargeSnapshot, pending: Bool?) -> DischargeButton? {
        if pending ?? snapshot.dischargeActive { return .stop }
        return DischargeStart.refusal(snapshot) == nil ? .start(upper: snapshot.thresholds.upper) : nil
    }

    @ViewBuilder
    private func dischargeControl() -> some View {
        switch Self.dischargeButton(for: snapshot, pending: model.pendingDischarge) {
        case .start(let upper):
            Button {
                Task { await model.setDischarge(true) }
            } label: {
                Label(Copy.dischargeStart(upper), systemImage: "battery.50percent").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.isPending)
        case .stop:
            Button {
                Task { await model.setDischarge(false) }
            } label: {
                Text(Copy.dischargeStop).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.isPending)
        case nil:
            EmptyView()
        }
    }
}

private extension View {
    func controlTile() -> some View { modifier(ControlTile()) }
}

/// A rounded block lighter than the panel, with an edge in the dark appearance, the way Control Center sets its sliders apart.
private struct ControlTile: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 10)
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(dark ? 0.05 : 0.35), in: shape)
            // Only the dark Control Center tiles carry an edge.
            .overlay(shape.strokeBorder(.white.opacity(dark ? 0.1 : 0), lineWidth: 1))
    }
}
