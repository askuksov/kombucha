import KombuchaCore
import SwiftUI

/// The first launch, and anything About asks for later. Nothing here is stored until Done: closing the window
/// registers nothing and asks for nothing (FR-WEL-1, AC-2).
struct WelcomeView: View {
    nonisolated static let windowID = "welcome"

    let model: AppModel
    @State private var launchAtLogin = true
    @State private var notifyFullCharge = true
    @State private var notifyProtectionChanges = true
    @Environment(\.dismiss) private var dismiss

    static func showsSteps(for model: AppModel) -> Bool {
        guard let verdict = model.verdict else { return true }
        return verdict == .supported
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Copy.welcomeTitle)
                .font(.title2.weight(.semibold))
            if Self.showsSteps(for: model) {
                steps
            } else if let verdict = model.verdict {
                Text(Copy.unsupportedHeading)
                    .font(.headline)
                Text(Copy.unsupportedReason(verdict))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(Copy.welcomeClose) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { model.welcomeOpened() }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            step(number: 1, title: Copy.welcomeMenuBarTitle) {
                Text(Copy.welcomeMenuBarBody)
                    .foregroundStyle(.secondary)
            }
            step(number: 2, title: Copy.welcomeHelperTitle) {
                helperStep
            }
            step(number: 3, title: Copy.launchAtLogin) {
                Toggle(Copy.launchAtLogin, isOn: $launchAtLogin)
                    .labelsHidden()
                    .accessibilityLabel(Copy.launchAtLogin)
                Text(Copy.welcomeLaunchBody)
                    .foregroundStyle(.secondary)
            }
            step(number: 4, title: Copy.notificationsSection) {
                Toggle(Copy.notifyFullCharge, isOn: $notifyFullCharge)
                Toggle(Copy.notifyProtectionChanges, isOn: $notifyProtectionChanges)
            }
            HStack {
                Spacer()
                Button(Copy.welcomeDone) {
                    Task {
                        await model.finishWelcome(launchAtLogin: launchAtLogin,
                                                  fullCharge: notifyFullCharge,
                                                  protectionChanges: notifyProtectionChanges)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The same live status the panel and the Helper tab show, so the user sees one answer in three places.
    @ViewBuilder private var helperStep: some View {
        let state = PanelState.make(snapshot: model.snapshot, verdict: model.verdict)
        if case .writePathBlocked(let path, _) = state {
            if let reason = Copy.reason(path) {
                Text(reason).foregroundStyle(.secondary)
            }
            HelperActionButton(model: model, path: path)
            Text(Copy.heading(path)).font(.footnote).foregroundStyle(.secondary)
        } else {
            Text(Copy.heading(.ready)).foregroundStyle(.secondary)
        }
    }

    private func step(number: Int, title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.headline)
                .frame(width: 16, alignment: .trailing)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
        .accessibilityElement(children: .contain)
    }
}
