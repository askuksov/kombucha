/// What the panel shows. The first match wins: an unsupported Mac, no reading yet, a write path that is not
/// ready, an external battery manager, then the controls. A gate outranks the mode, so a Kombucha that has
/// stepped back never reads as protecting.
public enum PanelState: Equatable, Sendable {
    case unsupported(SupportVerdict)
    case firstReading
    case writePathBlocked(WritePath, level: Int)
    case externalBatteryManager(ExternalBatteryManager, level: Int)
    case controls(ChargeSnapshot)

    public static func make(snapshot: ChargeSnapshot?, verdict: SupportVerdict?) -> PanelState {
        if let verdict, verdict != .supported { return .unsupported(verdict) }
        guard let snapshot else { return .firstReading }
        if snapshot.writePath != .ready {
            return .writePathBlocked(snapshot.writePath, level: snapshot.displayLevel)
        }
        if let manager = snapshot.externalBatteryManager {
            return .externalBatteryManager(manager, level: snapshot.displayLevel)
        }
        return .controls(snapshot)
    }
}
