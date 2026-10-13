import KombuchaCore
import SwiftUI

/// A failed action's message. Primary text with a red symbol: red text alone is unreadable on the light panel material.
struct FailureNote: View {
    let failure: ActionFailure

    var body: some View {
        Label {
            Text(Copy.failure(failure))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
        .font(.footnote)
    }
}
