import ServiceManagement

/// The login item is the app macOS starts when the user signs in to their Mac. There is no account and no
/// password involved, and the status is never stored: `SMAppService` is the only truth (§3.11).
@MainActor
protocol LoginItemControlling: Sendable {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
struct LoginItem: LoginItemControlling {
    private let service = SMAppService.mainApp

    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
}
