import KombuchaCore
import SwiftUI

struct HelperTab: View {
    let model: AppModel
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Form {
            Section(Copy.helperSection) {
                if let verdict = model.verdict, verdict != .supported {
                    Text(Copy.unsupportedReason(verdict))
                } else if let path = model.snapshot?.writePath {
                    Label {
                        Text(Copy.heading(path))
                    } icon: {
                        Image(systemName: path == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(path == .ready ? Color.green : Color.orange)
                    }
                    if let reason = Copy.reason(path) {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        HelperActionButton(model: model, path: path)
                        if path.offer.offersRemoveHelper {
                            Button(Copy.removeHelper) {
                                Task { await model.removeHelper() }
                            }
                            .disabled(model.isPending)
                        }
                    }
                    if path.offer.offersRemoveHelper {
                        Text(Copy.removeNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let failure = model.helperFailure {
                        FailureNote(failure: failure)
                    }
                } else {
                    Text(Copy.checking)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { probe() }
        .onChange(of: appearsActive) { _, active in
            if active { probe() }
        }
    }

    private func probe() {
        Task { await model.probeHelper() }
    }
}
