import Foundation
import Testing
@testable import Kombucha

@Test func theFirstResultWinsAndEveryLaterOneIsDropped() async {
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Int, HelperCallError>, Never>) in
        let once = ResumeOnce(continuation)
        once.resume(.success(1))
        once.resume(.failure(.timedOut))
        once.resume(.success(2))
    }
    #expect(result == .success(1))
}

@Test func aDeadlineThatFiresFirstIsTheResult() async {
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Int, HelperCallError>, Never>) in
        let once = ResumeOnce(continuation)
        once.resume(.failure(.timedOut))
        once.resume(.success(1))
    }
    #expect(result == .failure(.timedOut))
}

@Test func concurrentResumesDeliverExactlyOneAnswer() async {
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Int, HelperCallError>, Never>) in
        let once = ResumeOnce(continuation)
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            once.resume(.success(index))
        }
    }
    guard case .success(let value) = result else {
        Issue.record("a concurrent resume answered with a failure")
        return
    }
    #expect((0..<64).contains(value))
}
