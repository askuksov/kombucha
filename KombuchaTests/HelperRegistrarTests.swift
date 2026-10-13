import KombuchaCore
import ServiceManagement
import Testing
@testable import Kombucha

@Test(arguments: [
    (SMAppService.Status.enabled, HelperRegistration.enabled),
    (.requiresApproval, .requiresApproval),
    (.notRegistered, .notRegistered),
    (.notFound, .notFound),
])
func everyServiceStatusHasItsRegistration(status: SMAppService.Status, expected: HelperRegistration) {
    #expect(status.registration == expected)
}

@Test func aStatusThisBuildDoesNotKnowIsUnknown() {
    #expect(SMAppService.Status(rawValue: 99)?.registration == HelperRegistration.unknown)
}
