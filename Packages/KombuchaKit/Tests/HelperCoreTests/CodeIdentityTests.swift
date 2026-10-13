import Foundation
import Testing
@testable import HelperCore

private func temporaryCopy(of source: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: url)
    return url
}

// Apple's binaries carry signatures; a copy keeps them.
@Test func aReplacedExecutableNoLongerMatches() throws {
    let url = try temporaryCopy(of: "/bin/ls")
    defer { try? FileManager.default.removeItem(at: url) }
    let identity = CodeIdentity(executablePath: url.path)
    #expect(identity.matchesDisk())

    try FileManager.default.removeItem(at: url)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/cat"), to: url)

    #expect(!identity.matchesDisk())
}

@Test func aDeletedExecutableNoLongerMatches() throws {
    let url = try temporaryCopy(of: "/bin/ls")
    let identity = CodeIdentity(executablePath: url.path)
    try FileManager.default.removeItem(at: url)
    #expect(!identity.matchesDisk())
}

@Test func anExecutableMissingAtStartupNeverMatches() {
    #expect(!CodeIdentity(executablePath: "/nonexistent/kombucha-helper").matchesDisk())
}

@Test func anUnsignedFileNeverMatches() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
    try Data("#!/bin/sh\n".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(!CodeIdentity(executablePath: url.path).matchesDisk())
}

@Test func aReadableStartupIdentityIsKnown() throws {
    let url = try temporaryCopy(of: "/bin/ls")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(CodeIdentity(executablePath: url.path).knowsStartupCode)
}

@Test func anUnreadableStartupIdentityIsReported() throws {
    #expect(!CodeIdentity(executablePath: "/nonexistent/kombucha-helper").knowsStartupCode)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
    try Data("#!/bin/sh\n".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(!CodeIdentity(executablePath: url.path).knowsStartupCode)
}
