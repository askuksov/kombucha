import KombuchaCore
import SMCKit
import Testing
@testable import Kombucha

@Test func theNamedFailuresKeepTheirNames() {
    #expect(SMCProbe.result(of: .serviceNotFound) == .serviceNotFound)
    #expect(SMCProbe.result(of: .keyNotFound) == .keyNotFound)
}

@Test func everyOtherFailureMakesTheSMCUnusable() {
    let others: [SMCError] = [.connectionFailed(5), .callFailed(5), .smcResult(0x85),
                              .unexpectedSize(expected: 4, actual: 1), .permissionDenied,
                              .writeNotApplied(wrote: [1, 0, 0, 0], read: [0, 0, 0, 0])]
    for error in others {
        #expect(SMCProbe.result(of: error) == .otherFailure)
    }
}
