import KombuchaCore
import SwiftUI

struct PanelView: View {
    let model: AppModel

    var body: some View {
        let state = PanelState.make(snapshot: model.snapshot, verdict: model.verdict)
        VStack(alignment: .leading, spacing: 12) {
            StatusHeader(state: state)
            switch state {
            case .controls(let snapshot):
                Divider()
                ControlsSection(model: model, snapshot: snapshot)
            case .writePathBlocked(let path, _):
                GateSection(model: model, path: path)
            case .unsupported, .firstReading, .externalBatteryManager:
                EmptyView()
            }
            Divider()
            PanelFooter()
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            Task { await model.panelOpened() }
        }
    }
}
