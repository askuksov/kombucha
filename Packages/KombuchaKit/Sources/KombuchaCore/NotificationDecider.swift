import Foundation

/// One notification to make. The app turns it into words; the rules never touch text.
public enum NotificationPost: Equatable, Sendable {
    case fullyCharged(Thresholds)
    /// The state whose heading is the body: a blocked write path or an external battery manager.
    case protectionStopped(PanelState)
    case protectionResumed
}

/// The two switches of the General tab, passed in rather than stored: the bookkeeping has to know whether a
/// notification really went out, or a switch flipped mid-interruption would produce a lone "resumed".
public struct NotificationGates: Equatable, Sendable {
    public var fullChargeFinished: Bool
    public var protectionChanges: Bool

    public init(fullChargeFinished: Bool, protectionChanges: Bool) {
        self.fullChargeFinished = fullChargeFinished
        self.protectionChanges = protectionChanges
    }
}

public struct NotificationDecision: Equatable, Sendable {
    public var posts: [NotificationPost]
    /// When the decider wants to be asked again even if no pass arrives.
    public var wakeAt: Date?

    public static let nothing = NotificationDecision(posts: [], wakeAt: nil)

    public init(posts: [NotificationPost], wakeAt: Date?) {
        self.posts = posts
        self.wakeAt = wakeAt
    }
}

/// The rules of §6.3. The engine calls `observe` on every pass, published or not, so a snapshot equal to the
/// last one decides nothing: that is how "the previous published snapshot" is honoured without touching the port.
public struct NotificationDecider: Sendable {
    /// An interruption shorter than this says nothing: it absorbs the automatic repair of §3.4.
    public static let interruptionGrace: TimeInterval = 30

    private var last: ChargeSnapshot?
    private var interruptionStart: Date?
    private var stoppedPosted = false

    public init() {}

    public mutating func observe(_ snapshot: ChargeSnapshot,
                                 fullChargeEnded: FullChargeEnding?,
                                 gates: NotificationGates,
                                 now: Date) -> NotificationDecision {
        let previous = last
        let isNew = snapshot != previous
        if isNew { last = snapshot }

        var posts: [NotificationPost] = []
        if isNew {
            if fullChargeEnded == .reachedFull, previous?.fullChargeActive == true, gates.fullChargeFinished {
                posts.append(.fullyCharged(snapshot.thresholds))
            }
            posts += trackInterruption(previous: previous, snapshot: snapshot, now: now)
        }
        posts += stopIfGraceIsOver(snapshot: snapshot, gates: gates, now: now)
        return NotificationDecision(posts: posts, wakeAt: pendingWake(now: now))
    }

    public mutating func tick(gates: NotificationGates, now: Date) -> NotificationDecision {
        guard let snapshot = last else { return .nothing }
        let posts = stopIfGraceIsOver(snapshot: snapshot, gates: gates, now: now)
        return NotificationDecision(posts: posts, wakeAt: pendingWake(now: now))
    }

    /// Opens, closes or forgets the current interruption. Returns the "resumed" post when one is due.
    private mutating func trackInterruption(previous: ChargeSnapshot?,
                                            snapshot: ChargeSnapshot,
                                            now: Date) -> [NotificationPost] {
        // Nothing to compare the first snapshot with: a Mac that starts unable to manage stays quiet.
        guard let previous else { return [] }
        if snapshot.mayManage {
            let announced = stoppedPosted
            forgetInterruption()
            return announced ? [.protectionResumed] : []
        }
        guard snapshot.protection else {
            // The user switched protection off themselves; they do not need to be told about it.
            forgetInterruption()
            return []
        }
        if previous.mayManage, interruptionStart == nil { interruptionStart = now }
        return []
    }

    private mutating func stopIfGraceIsOver(snapshot: ChargeSnapshot,
                                           gates: NotificationGates,
                                           now: Date) -> [NotificationPost] {
        guard let began = interruptionStart, !stoppedPosted,
              snapshot.protection, !snapshot.mayManage,
              now.timeIntervalSince(began) >= Self.interruptionGrace,
              gates.protectionChanges else { return [] }
        stoppedPosted = true
        return [.protectionStopped(PanelState.make(snapshot: snapshot, verdict: .supported))]
    }

    private func pendingWake(now: Date) -> Date? {
        guard let began = interruptionStart, !stoppedPosted else { return nil }
        let due = began.addingTimeInterval(Self.interruptionGrace)
        return due > now ? due : nil
    }

    private mutating func forgetInterruption() {
        interruptionStart = nil
        stoppedPosted = false
    }
}
