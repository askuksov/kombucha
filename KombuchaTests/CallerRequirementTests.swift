import Foundation
import HelperCore
import HelperProtocol
import Security
import Testing

private let helperURL = Bundle.main.bundleURL.appending(path: "Contents/MacOS/kombucha-helper")

private func signingInformation(of url: URL) throws -> [String: Any] {
    var code: SecStaticCode?
    try #require(SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess)
    var information: CFDictionary?
    let status = SecCodeCopySigningInformation(try #require(code), SecCSFlags(rawValue: kSecCSSigningInformation), &information)
    try #require(status == errSecSuccess)
    return try #require(information as? [String: Any])
}

private func clientRequirementText() throws -> String {
    let embedded = try #require(try signingInformation(of: helperURL)[kSecCodeInfoPList as String] as? [String: Any])
    return try #require(embedded[HelperIdentity.clientRequirementKey] as? String)
}

@Test func theTestsRunInsideTheAppTheHelperWillBeAskedAbout() {
    #expect(Bundle.main.bundleIdentifier == "dev.kuksov.kombucha")
}

@Test func theEmbeddedHelperCarriesTheRequirementItChecksCallersWith() throws {
    let text = try clientRequirementText()
    #expect(text.hasPrefix(#"identifier "dev.kuksov.kombucha" and anchor apple generic and certificate leaf[subject.OU] = ""#))

    // The team is never a literal in sources: it must match the team the app is signed with.
    let team = try #require(try signingInformation(of: Bundle.main.bundleURL)[kSecCodeInfoTeamIdentifier as String] as? String)
    #expect(text == #"identifier "dev.kuksov.kombucha" and anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#)
}

@Test func theRunningAppSatisfiesThatRequirement() throws {
    let requirement = try #require(CallerVerifier.compile(try clientRequirementText()))

    let verdict = CallerVerifier.check(pid: getpid(), against: requirement)

    #expect(verdict.accepted)
    #expect(verdict.status == errSecSuccess)
    #expect(verdict.path.hasSuffix("Kombucha.app"))
}

@Test func aProcessOutsideTheBundleIsRefusedByThatRequirement() throws {
    let requirement = try #require(CallerVerifier.compile(try clientRequirementText()))
    let child = Process()
    child.executableURL = URL(fileURLWithPath: "/bin/sleep")
    child.arguments = ["10"]
    try child.run()
    defer { child.terminate() }

    var verdict = CallerVerifier.check(pid: child.processIdentifier, against: requirement)
    // The code identity of a freshly spawned process is not published instantly.
    let deadline = ContinuousClock.now + .seconds(5)
    while verdict.path != "/bin/sleep", ContinuousClock.now < deadline {
        usleep(20_000)
        verdict = CallerVerifier.check(pid: child.processIdentifier, against: requirement)
    }

    #expect(!verdict.accepted)
    #expect(verdict.status == errSecCSReqFailed)
    #expect(verdict.path == "/bin/sleep")
}

@Test func theAppRequirementAcceptsTheHelperTheAppShipsWith() throws {
    let text = try #require(Bundle.main.object(forInfoDictionaryKey: HelperIdentity.helperRequirementKey) as? String)
    #expect(text.hasPrefix(#"identifier "dev.kuksov.kombucha.helper" and anchor apple generic"#))

    // The team is never a literal in sources: it must match the team the app is signed with.
    let team = try #require(try signingInformation(of: Bundle.main.bundleURL)[kSecCodeInfoTeamIdentifier as String] as? String)
    #expect(text == #"identifier "dev.kuksov.kombucha.helper" and anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#)

    let requirement = try #require(CallerVerifier.compile(text))
    var code: SecStaticCode?
    try #require(SecStaticCodeCreateWithPath(helperURL as CFURL, [], &code) == errSecSuccess)

    #expect(SecStaticCodeCheckValidity(try #require(code), [], requirement) == errSecSuccess)
}

@Test func aForeignTeamIsRefusedByTheTeamClauseAlone() throws {
    let text = try clientRequirementText()
    let team = try #require(try signingInformation(of: Bundle.main.bundleURL)[kSecCodeInfoTeamIdentifier as String] as? String)
    let foreign = text.replacingOccurrences(of: "\"\(team)\"", with: "\"AAAAAAAAAA\"")
    #expect(foreign != text)
    let requirement = try #require(CallerVerifier.compile(foreign))

    // The app satisfies the identifier and the anchor, so only the team clause can refuse it.
    let verdict = CallerVerifier.check(pid: getpid(), against: requirement)

    #expect(!verdict.accepted)
    #expect(verdict.status == errSecCSReqFailed)
}
