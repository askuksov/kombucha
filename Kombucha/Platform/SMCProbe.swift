import KombuchaCore
import SMCKit

/// Opens AppleSMC and checks the charge key the way the helper will use it, reading only.
struct SMCProbe: SMCProbing {
    func probe() -> SMCProbeResult {
        do {
            _ = try ChargeSwitch.arm()
            return .ok
        } catch let error as SMCError {
            return Self.result(of: error)
        } catch {
            return .otherFailure
        }
    }

    func probeAdapterSwitch() -> Bool {
        (try? AdapterSwitch.arm()) != nil
    }

    static func result(of error: SMCError) -> SMCProbeResult {
        switch error {
        case .serviceNotFound: .serviceNotFound
        case .keyNotFound: .keyNotFound
        default: .otherFailure
        }
    }
}
