import Foundation

@objc(KombuchaHelperProtocol)
public protocol KombuchaHelperProtocol {
    // Frozen: any helper version must be able to answer it.
    func ping(reply: @escaping @Sendable (Int) -> Void)
    func setCharging(allow: Bool, reply: @escaping @Sendable (Int, String) -> Void)
    /// Protocol 2. `false` switches the adapter off until `leaseSeconds` pass without another `false`; `true`
    /// switches it on and ends the lease.
    func setAdapter(enabled: Bool, leaseSeconds: Int, reply: @escaping @Sendable (Int, String) -> Void)
}

public enum HelperResult: Int, Sendable {
    case done = 0
    case failed = 1
}

public enum HelperIdentity {
    public static let machServiceName = "dev.kuksov.kombucha.helper"
    public static let launchdPlistName = "dev.kuksov.kombucha.helper.plist"
    public static let protocolVersion = 2
    /// The first protocol with `setAdapter`; the app never sends it to an older helper.
    public static let adapterSwitchVersion = 2
    public static let clientRequirementKey = "KombuchaClientRequirement"
    public static let helperRequirementKey = "KombuchaHelperRequirement"
}
