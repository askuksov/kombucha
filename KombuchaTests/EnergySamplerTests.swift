import Darwin
import Testing
@testable import Kombucha

@Test func theSampleHoldsThisProcessWithItsPath() throws {
    let reading = EnergySampler().sample()
    let own = try #require(reading.samples.first { $0.pid == getpid() })
    #expect(own.executablePath.hasSuffix(".xctest") || own.executablePath.contains("Kombucha"))
    #expect(reading.seconds > 0)
}

@Test func energyOnlyGrowsAndTimeMovesForward() throws {
    let first = EnergySampler().sample()
    var sink = 0.0
    for index in 1...2_000_000 { sink += Double(index).squareRoot() }
    #expect(sink > 0)
    let second = EnergySampler().sample()
    let before = try #require(first.samples.first { $0.pid == getpid() })
    let after = try #require(second.samples.first { $0.pid == getpid() })
    #expect(after.energyNanojoules >= before.energyNanojoules)
    #expect(second.seconds > first.seconds)
}

@Test func theScannerStillListsEveryPid() {
    #expect(ProcessScanner.allPids().contains(getpid()))
}
