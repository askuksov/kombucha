import KombuchaCore
import SwiftUI

/// The action a write path offers: install or start the helper through the engine, or open Login Items.
struct HelperActionButton: View {
    let model: AppModel
    let path: WritePath

    var body: some View {
        Button(Copy.action(path)) {
            switch path.offer.action {
            case .register: Task { await model.installHelper() }
            case .openLoginItems: HelperRegistrar.openLoginItems()
            }
        }
        .disabled(model.isPending)
    }
}
