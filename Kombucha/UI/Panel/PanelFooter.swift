import AppKit
import SwiftUI

struct PanelFooter: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            MenuRow(title: Copy.footerSettings, key: ",") {
                openSettings()
                NSApp.activate()
            }
            MenuRow(title: Copy.footerQuit, key: "q") {
                NSApp.terminate(nil)
            }
        }
    }
}

/// A footer button drawn as a menu row: full width, highlighted under the pointer, with its shortcut.
private struct MenuRow: View {
    let title: String
    let key: Character
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "⌘\(String(key).uppercased())")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(hovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        .onHover { hovering = $0 }
    }
}
