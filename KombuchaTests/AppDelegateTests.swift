import AppKit
import Testing
@testable import Kombucha

@MainActor
@Test func theTestHostBuiltNoEngine() throws {
    let delegate = try #require(AppDelegate.current)
    #expect(delegate.engine == nil)
}

@MainActor
@Test func withoutAnEngineTheAppQuitsAtOnce() throws {
    let delegate = try #require(AppDelegate.current)
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
}

@MainActor
@Test func theTestHostRegisteredNoGateway() throws {
    let delegate = try #require(AppDelegate.current)
    #expect(delegate.registeredGateway == false)
}
