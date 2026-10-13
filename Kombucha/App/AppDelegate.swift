import AppIntents
import AppKit
import HelperProtocol
import KombuchaCore

/// Builds the live engine in the app, never in the test host, and holds termination until the engine
/// has let go of the charger.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The delegate SwiftUI created; tests read it to see what the host built.
    private(set) weak static var current: AppDelegate?

    private nonisolated static let historyFile = HistoryFile.standard()

    let model: AppModel
    /// Registered before anything else runs, so an intent that launches Kombucha always finds it.
    let gateway: LiveEngineGateway
    private(set) var registeredGateway = false
    private(set) var engine: Engine?
    private var notificationController: NotificationController?
    private var historyRecorder: HistoryRecorder?

    override init() {
        let model = AppModel(readHealth: { BatteryHealthReader.read() },
                             readPower: { PowerReader.read() },
                             sampleEnergy: { EnergySampler().sample() },
                             readHistory: { HistoryLog(records: AppDelegate.historyFile.load()) })
        self.model = model
        let gateway = LiveEngineGateway(model: model)
        self.gateway = gateway
        super.init()
        Self.current = self
        if LaunchContext.current() == .app {
            AppDependencyManager.shared.add(dependency: gateway as any EngineGateway)
            registeredGateway = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard LaunchContext.current() == .app else { return }
        assemble()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine else { return .terminateNow }
        Task {
            _ = await engine.shutdown(waitingAtMost: .milliseconds(2500))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func assemble() {
        guard let requirement = Bundle.main.object(forInfoDictionaryKey: HelperIdentity.helperRequirementKey) as? String else {
            AppLog.engine.fault("the app carries no helper requirement")
            return
        }
        let inbox = EngineInbox()
        let settings = SettingsStore(defaults: .standard) { inbox.post(.settingsChanged) }
        let helper = HelperClient(onConnectionLost: { inbox.post(.helperConnectionLost) },
                                  makeConnection: HelperClient.machService(requirement: requirement))
        let power = PowerSourceMonitor(inbox: inbox)
        let notifications = NotificationCenterClient()
        let controller = NotificationController(centre: notifications, ui: settings) { [model] in
            model.settingsTab = .helper
            // The private `showSettingsWindow:` selector did not fire reliably (found live, 2026-09-30);
            // `openSettingsAction` wraps the proven `@Environment(\.openSettings)` MenuBarLabel already uses.
            model.openSettingsAction?()
            NSApp.activate()
        }
        self.notificationController = controller
        let recorder = HistoryRecorder(store: Self.historyFile, ui: settings, alerts: controller,
                                       readHealth: { BatteryHealthReader.read() })
        self.historyRecorder = recorder
        let ports = EnginePorts(power: power,
                                smc: SMCProbe(),
                                processes: ProcessScanner(),
                                helper: helper,
                                registrar: HelperRegistrar(),
                                settings: settings,
                                observer: CompositeObserver([controller, recorder]),
                                eventSources: [power, WakeMonitor(inbox: inbox)],
                                ownBundlePath: Bundle.main.bundlePath)
        let engine = Engine(inbox: inbox, ports: ports)
        self.engine = engine
        model.attach(engine: engine, settings: settings)
        gateway.attach(engine: engine, settings: settings)
        model.attach(loginItem: LoginItem(), notifications: notifications, ui: settings)
        Task { await model.refreshNotificationAuthorization() }
        Task { await model.consume(engine.snapshots) }
        Task {
            let verdict = await engine.start()
            model.publish(verdict)
            AppLog.engine.info("support verdict \(String(describing: verdict), privacy: .public) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")
            if verdict == .supported {
                await engine.run()
            }
        }
    }
}
