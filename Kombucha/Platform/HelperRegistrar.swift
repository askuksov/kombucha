import HelperProtocol
import KombuchaCore
import ServiceManagement

/// What the engine may ask about the helper's registration. `SMAppService.Status` stays behind it.
protocol HelperRegistering: Sendable {
    var registration: HelperRegistration { get }
    /// The registration after the call; a thrown error is logged, never interpreted.
    func registerHelper() -> HelperRegistration
    func unregisterHelper() -> HelperRegistration
}

struct HelperRegistrar: HelperRegistering {
    private var service: SMAppService {
        SMAppService.daemon(plistName: HelperIdentity.launchdPlistName)
    }

    var registration: HelperRegistration {
        service.status.registration
    }

    // register() throws even when the registration succeeded; the status is the verdict.
    func registerHelper() -> HelperRegistration {
        do { try service.register() } catch { Self.log(error, action: "register") }
        return registration
    }

    func unregisterHelper() -> HelperRegistration {
        do { try service.unregister() } catch { Self.log(error, action: "unregister") }
        return registration
    }

    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func log(_ error: any Error, action: String) {
        AppLog.helper.error("\(action, privacy: .public) threw: \(String(describing: error), privacy: .public)")
    }
}

extension SMAppService.Status {
    var registration: HelperRegistration {
        switch self {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }
}
