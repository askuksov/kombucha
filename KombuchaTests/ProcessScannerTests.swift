import Foundation
import Testing
@testable import Kombucha

@Test func theScanFindsThisProcess() throws {
    let own = try #require(Bundle.main.executablePath)
    let paths = ProcessScanner().executablePaths()
    #expect(paths.contains(URL(fileURLWithPath: own).resolvingSymlinksInPath().path))
}

@Test func theScanReachesAnotherUsersProcess() {
    #expect(ProcessScanner().executablePaths().contains("/sbin/launchd"))
}
