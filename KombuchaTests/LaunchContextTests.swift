import Foundation
import Testing
@testable import Kombucha

@Test func theTestHostKnowsItHostsTests() {
    #expect(LaunchContext.current() == .tests)
}

@Test func aPlainLaunchIsTheApp() {
    #expect(LaunchContext.current(environment: [:]) == .app)
}
