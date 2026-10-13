/// What `SMAppService` says about the helper. The app maps its status onto these cases.
public enum HelperRegistration: Equatable, Sendable {
    case enabled, requiresApproval, notRegistered, notFound, unknown
}

public enum WritePath: Equatable, Sendable {
    case ready, unreachable, requiresApproval, notRegistered, notFound, unknown

    public static func verdict(_ registration: HelperRegistration, answered: Bool) -> WritePath {
        switch registration {
        case .enabled: answered ? .ready : .unreachable
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .notFound
        case .unknown: .unknown
        }
    }

    /// A write path that has just come back owes one write of the implied command.
    public static func writeOwed(wasReachable: Bool, nowReachable: Bool) -> Bool {
        nowReachable && !wasReachable
    }

    public var offer: HelperOffer {
        switch self {
        case .ready: HelperOffer(action: .register, offersRemoveHelper: true)
        case .unreachable: HelperOffer(action: .register, offersRemoveHelper: true)
        case .notRegistered: HelperOffer(action: .register, offersRemoveHelper: false)
        case .notFound: HelperOffer(action: .register, offersRemoveHelper: false)
        case .requiresApproval: HelperOffer(action: .openLoginItems, offersRemoveHelper: true)
        case .unknown: HelperOffer(action: .openLoginItems, offersRemoveHelper: false)
        }
    }
}

public enum HelperAction: Equatable, Sendable {
    case register, openLoginItems
}

public struct HelperOffer: Equatable, Sendable {
    public let action: HelperAction
    public let offersRemoveHelper: Bool

    init(action: HelperAction, offersRemoveHelper: Bool) {
        self.action = action
        self.offersRemoveHelper = offersRemoveHelper
    }
}
