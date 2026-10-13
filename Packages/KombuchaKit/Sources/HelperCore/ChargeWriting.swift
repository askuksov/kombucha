import SMCKit

public protocol ChargeWriting: Sendable {
    func setCharging(allow: Bool) throws
}

extension ChargeSwitch: ChargeWriting {}
