import SwiftUI

@main
struct KombuchaApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: delegate.model)
        }

        Window(Copy.welcomeTitle, id: WelcomeView.windowID) {
            WelcomeView(model: delegate.model)
        }
        .windowResizability(.contentSize)
    }
}
