import Foundation
import HelperProtocol
import ObjectiveC
import Testing

@Test func resultCodesNeverChange() {
    #expect(HelperResult.done.rawValue == 0)
    #expect(HelperResult.failed.rawValue == 1)
}

@Test func identityMatchesTheLaunchdJob() {
    #expect(HelperIdentity.machServiceName == "dev.kuksov.kombucha.helper")
    #expect(HelperIdentity.launchdPlistName == "\(HelperIdentity.machServiceName).plist")
    #expect(HelperIdentity.protocolVersion == 2)
    #expect(HelperIdentity.adapterSwitchVersion == 2)
}

@Test func protocolHasExactlyThreeMethods() {
    var count: UInt32 = 0
    let methods = protocol_copyMethodDescriptionList(KombuchaHelperProtocol.self, true, true, &count)
    free(methods)
    #expect(count == 3)
}
