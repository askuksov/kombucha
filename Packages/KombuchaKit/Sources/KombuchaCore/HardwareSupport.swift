public enum SMCProbeResult: Equatable, Sendable {
    case ok, serviceNotFound, keyNotFound, otherFailure
}

public enum SupportVerdict: Equatable, Sendable {
    case supported, noSMCService, noBattery, chargeKeyMissing, smcUnusable

    /// The architecture is not checked at run time: the binary is arm64-only.
    public static func verdict(hasInternalBattery: Bool, probe: SMCProbeResult) -> SupportVerdict {
        if probe == .serviceNotFound { return .noSMCService }
        if !hasInternalBattery { return .noBattery }
        switch probe {
        case .keyNotFound: return .chargeKeyMissing
        case .otherFailure: return .smcUnusable
        case .ok: return .supported
        case .serviceNotFound: return .noSMCService // answered above
        }
    }
}
