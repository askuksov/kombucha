import Foundation
import Security
import Testing
@testable import HelperCore

@Test func acceptsTheRunningProcessAgainstItsOwnDesignatedRequirement() throws {
    var own: SecCode?
    try #require(SecCodeCopySelf([], &own) == errSecSuccess)
    var staticCode: SecStaticCode?
    try #require(SecCodeCopyStaticCode(try #require(own), [], &staticCode) == errSecSuccess)
    var requirement: SecRequirement?
    try #require(SecCodeCopyDesignatedRequirement(try #require(staticCode), [], &requirement) == errSecSuccess)

    let verdict = CallerVerifier.check(pid: getpid(), against: try #require(requirement))

    #expect(verdict.accepted)
}

@Test func refusesACallerOutsideTheRequirementAndNamesItsPath() throws {
    let requirement = try #require(CallerVerifier.compile(#"identifier "dev.kuksov.kombucha" and anchor apple generic"#))

    let verdict = CallerVerifier.check(pid: getpid(), against: requirement)

    #expect(!verdict.accepted)
    #expect(verdict.status == errSecCSReqFailed)
    #expect(verdict.path.hasPrefix("/"))
}

@Test func anInvalidRequirementDoesNotCompile() {
    #expect(CallerVerifier.compile("identifier and and") == nil)
}

/// A caller in another process is what the helper actually checks: `/bin/sleep` is Apple-signed
/// and carries a different identifier, so it is accepted by one requirement and refused by ours.
@Test func checksACallerRunningInAnotherProcess() throws {
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["10"]
    try child.run()
    defer { child.terminate() }

    let apple = try #require(CallerVerifier.compile("anchor apple"))
    var accepted = CallerVerifier.check(pid: child.processIdentifier, against: apple)
    // The code identity of a freshly spawned process is not published instantly.
    let deadline = ContinuousClock.now + .seconds(5)
    while !accepted.accepted, ContinuousClock.now < deadline {
        usleep(20_000)
        accepted = CallerVerifier.check(pid: child.processIdentifier, against: apple)
    }
    #expect(accepted.accepted)
    #expect(accepted.path == "/bin/sleep")

    let ours = try #require(CallerVerifier.compile(#"identifier "dev.kuksov.kombucha" and anchor apple generic"#))
    let refused = CallerVerifier.check(pid: child.processIdentifier, against: ours)
    #expect(!refused.accepted)
    #expect(refused.status == errSecCSReqFailed)
    #expect(refused.path == "/bin/sleep")
}
