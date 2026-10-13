import Dispatch
import Foundation
import HelperProtocol
import SMCKit
import Synchronization
import Testing
@testable import HelperCore

final class RecordingWriter: ChargeWriting {
    private let calls = Mutex<[Bool]>([])
    private let failure: SMCError?
    private let log: CallLog?

    init(failure: SMCError? = nil, log: CallLog? = nil) {
        self.failure = failure
        self.log = log
    }

    var recorded: [Bool] { calls.withLock { $0 } }

    func setCharging(allow: Bool) throws {
        log?.note(allow ? "allow" : "inhibit")
        calls.withLock { $0.append(allow) }
        if let failure { throw failure }
    }
}

@Test func pingNeverReachesTheWriter() {
    let writer = RecordingWriter()
    let version = Mutex<Int?>(nil)
    HelperService(writer: writer).ping { value in version.withLock { $0 = value } }
    #expect(version.withLock { $0 } == HelperIdentity.protocolVersion)
    #expect(writer.recorded.isEmpty)
}

@Test func pingIsAnsweredWhenWritesFail() {
    let writer = RecordingWriter(failure: .permissionDenied)
    let version = Mutex<Int?>(nil)
    HelperService(writer: writer).ping { value in version.withLock { $0 = value } }
    #expect(version.withLock { $0 } == HelperIdentity.protocolVersion)
    #expect(writer.recorded.isEmpty)
}

@Test func aLandedWriteAnswersDone() {
    let writer = RecordingWriter()
    let reply = Mutex<(Int, String)?>(nil)
    HelperService(writer: writer).setCharging(allow: false) { code, detail in reply.withLock { $0 = (code, detail) } }
    #expect(reply.withLock { $0?.0 } == HelperResult.done.rawValue)
    #expect(reply.withLock { $0?.1 } == "setCharging: inhibit — done")
    #expect(writer.recorded == [false])
}

@Test func aRefusedWriteAnswersFailedWithItsReason() {
    let writer = RecordingWriter(failure: .permissionDenied)
    let reply = Mutex<(Int, String)?>(nil)
    HelperService(writer: writer).setCharging(allow: true) { code, detail in reply.withLock { $0 = (code, detail) } }
    #expect(reply.withLock { $0?.0 } == HelperResult.failed.rawValue)
    #expect(reply.withLock { $0?.1 }?.hasPrefix("setCharging: allow — failed:") == true)
    #expect(writer.recorded == [true])
}

@Test func theIntentReachesTheWriterUnchanged() {
    let writer = RecordingWriter()
    let service = HelperService(writer: writer)
    service.setCharging(allow: true) { _, _ in }
    service.setCharging(allow: false) { _, _ in }
    #expect(writer.recorded == [true, false])
}

/// Holds `setCharging` until the test releases it.
private final class BlockingWriter: ChargeWriting {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let finished = Mutex(false)

    var didFinish: Bool { finished.withLock { $0 } }

    func setCharging(allow: Bool) throws {
        entered.signal()
        release.wait()
        finished.withLock { $0 = true }
    }
}

@Test func retiringReleasesTheChargerBeforeItEndsTheProcess() {
    let writer = RecordingWriter()
    let seenAtExit = Mutex<[Bool]?>(nil)
    HelperService(writer: writer, exitProcess: { seenAtExit.withLock { $0 = writer.recorded } }).retire(because: "a test")
    #expect(seenAtExit.withLock { $0 } == [true])
}

@Test func retiringEndsTheProcessEvenWhenTheReleaseFails() {
    let exits = Occurrences()
    let writer = RecordingWriter(failure: .permissionDenied)
    HelperService(writer: writer, exitProcess: { exits.record() }).retire(because: "a test")
    #expect(writer.recorded == [true])
    #expect(exits.count == 1)
}

@Test func retiringEndsTheProcess() {
    let exits = Occurrences()
    HelperService(writer: RecordingWriter(), exitProcess: { exits.record() }).retire(because: "a test")
    #expect(exits.count == 1)
}

@Test func retiringWaitsForAWriteInFlight() {
    let writer = BlockingWriter()
    let exits = Occurrences()
    let replies = Occurrences()
    let service = HelperService(writer: writer, exitProcess: { exits.record() })

    DispatchQueue.global().async { service.setCharging(allow: false) { _, _ in replies.record() } }
    #expect(writer.entered.wait(timeout: .now() + 2) == .success)
    DispatchQueue.global().async { service.retire(because: "a test") }

    #expect(!exits.wait(seconds: 0.3))
    // One release for the write in flight, one for the allow that retiring sends after it.
    writer.release.signal()
    writer.release.signal()
    #expect(exits.wait(seconds: 2))
    #expect(writer.didFinish)
    #expect(replies.count == 1)
}

@Test func pingIsAnsweredWhileAWriteIsInFlight() {
    let writer = BlockingWriter()
    let service = HelperService(writer: writer, exitProcess: {})
    DispatchQueue.global().async { service.setCharging(allow: false) { _, _ in } }
    #expect(writer.entered.wait(timeout: .now() + 2) == .success)

    let version = Mutex<Int?>(nil)
    service.ping { value in version.withLock { $0 = value } }

    #expect(version.withLock { $0 } == HelperIdentity.protocolVersion)
    writer.release.signal()
}
