import KombuchaCore
import SwiftUI

struct GateSection: View {
    let model: AppModel
    let path: WritePath

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HelperActionButton(model: model, path: path)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            if let failure = model.helperFailure {
                FailureNote(failure: failure)
            }
        }
    }
}
