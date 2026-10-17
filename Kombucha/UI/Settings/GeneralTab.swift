import AppKit
import SwiftUI
import UserNotifications

struct GeneralTab: View {
    /// What the notifications section has to explain, if anything.
    enum Authorization: Equatable {
        case asked, notAsked, denied

        var switchesAreDisabled: Bool { self == .denied }
    }

    let model: AppModel
    @AppStorage(SettingsStore.Key.showPercentageInMenuBar) private var showPercentage = false
    @Environment(\.appearsActive) private var appearsActive

    /// `notAsked` only matters while a switch is on: nothing is missing if nothing wants to notify.
    static func authorization(for model: AppModel) -> Authorization {
        switch model.notificationAuthorization {
        case .denied:
            .denied
        case .notDetermined:
            model.notifyFullChargeFinished || model.notifyProtectionChanges || model.notifyBatteryAttention ? .notAsked : .asked
        default:
            .asked
        }
    }

    var body: some View {
        let authorization = Self.authorization(for: model)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(Copy.launchAtLogin, isOn: Binding(get: { model.launchAtLoginIsOn },
                                                             set: { on in Task { await model.setLaunchAtLogin(on) } }))
                    if model.launchAtLoginNeedsApproval {
                        Text(Copy.launchAtLoginRefused)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(Copy.openLoginItems) { NSWorkspace.shared.open(Copy.SystemSettings.loginItems) }
                    }
                }
                .accessibilityElement(children: .contain)
                Toggle(Copy.showPercentage, isOn: $showPercentage)
            }
            if model.languages.isSwitchable {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker(Copy.languageRow,
                               selection: Binding(get: { model.languages.selection },
                                                  set: { model.chooseLanguage($0) })) {
                            Text(Copy.languageSystemDefault).tag(AppLanguages.Selection.system)
                            ForEach(model.languages.languages) { language in
                                Text(language.name).tag(AppLanguages.Selection.language(language.code))
                            }
                        }
                        if model.languages.restartNeeded {
                            Text(Copy.languageRestartNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button(Copy.restartKombucha) { model.restart() }
                                .disabled(model.restartPending)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            Section(Copy.notificationsSection) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(Copy.notifyFullCharge,
                           isOn: Binding(get: { model.notifyFullChargeFinished },
                                         set: { on in Task { await model.setNotifyFullChargeFinished(on) } }))
                        .disabled(authorization.switchesAreDisabled)
                    Toggle(Copy.notifyProtectionChanges,
                           isOn: Binding(get: { model.notifyProtectionChanges },
                                         set: { on in Task { await model.setNotifyProtectionChanges(on) } }))
                        .disabled(authorization.switchesAreDisabled)
                    Toggle(Copy.notifyBatteryAttention,
                           isOn: Binding(get: { model.notifyBatteryAttention },
                                         set: { on in Task { await model.setNotifyBatteryAttention(on) } }))
                        .disabled(authorization.switchesAreDisabled)
                    switch authorization {
                    case .asked:
                        EmptyView()
                    case .notAsked:
                        Text(Copy.notificationsNotAsked)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(Copy.allowNotifications) {
                            Task { await model.requestNotificationAuthorization() }
                        }
                    case .denied:
                        Text(Copy.notificationsDenied)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(Copy.openNotificationSettings) {
                            NSWorkspace.shared.open(Copy.SystemSettings.notifications)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
            if let updates = model.updates {
                Section(Copy.updatesSection) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(Copy.updateCheckDaily,
                               isOn: Binding(get: { updates.dailyCheck },
                                             set: { on in Task { await updates.setDailyCheck(on) } }))
                        Text(Copy.updateCheckDailyNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
        .onChange(of: appearsActive) { _, active in
            if active { refresh() }
        }
    }

    /// Both truths live outside the app, so both are re-read whenever the window comes forward (FR-SET-2's AC).
    private func refresh() {
        model.refreshLoginItem()
        Task { await model.refreshNotificationAuthorization() }
    }
}
