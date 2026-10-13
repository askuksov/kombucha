import KombuchaCore
import Testing

@Test(arguments: [
    (HelperRegistration.enabled, true, WritePath.ready),
    (.enabled, false, .unreachable),
    (.requiresApproval, true, .requiresApproval),
    (.requiresApproval, false, .requiresApproval),
    (.notRegistered, true, .notRegistered),
    (.notRegistered, false, .notRegistered),
    (.notFound, true, .notFound),
    (.notFound, false, .notFound),
    (.unknown, true, .unknown),
    (.unknown, false, .unknown),
])
func theVerdictTableHolds(registration: HelperRegistration, answered: Bool, expected: WritePath) {
    #expect(WritePath.verdict(registration, answered: answered) == expected)
}

@Test func onlyAnEnabledRegistrationLooksAtTheAnswer() {
    for registration in [HelperRegistration.requiresApproval, .notRegistered, .notFound, .unknown] {
        #expect(WritePath.verdict(registration, answered: true) == WritePath.verdict(registration, answered: false))
    }
}

@Test(arguments: [
    (WritePath.ready, HelperAction.register, true),
    (.unreachable, .register, true),
    (.notRegistered, .register, false),
    (.notFound, .register, false),
    (.requiresApproval, .openLoginItems, true),
    (.unknown, .openLoginItems, false),
])
func theActionTableHolds(path: WritePath, action: HelperAction, offersRemoveHelper: Bool) {
    #expect(path.offer.action == action)
    #expect(path.offer.offersRemoveHelper == offersRemoveHelper)
}

@Test(arguments: [
    (false, false, false),
    (false, true, true),
    (true, false, false),
    (true, true, false),
])
func aWriteIsOwedOnlyWhenTheWritePathComesBack(wasReachable: Bool, nowReachable: Bool, expected: Bool) {
    #expect(WritePath.writeOwed(wasReachable: wasReachable, nowReachable: nowReachable) == expected)
}
