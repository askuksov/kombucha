import Foundation
import KombuchaCore
import Testing

@Test func aPlainAndAPrefixedNumberParseToTheSameVersion() {
    #expect(AppVersion("0.2.0") == AppVersion(0, 2, 0))
    #expect(AppVersion("v0.2.0") == AppVersion(0, 2, 0))
    #expect(AppVersion("v10.20.30") == AppVersion(10, 20, 30))
}

@Test(arguments: ["", "v", "0.2", "0.2.0.1", "v0.2.0-beta", "latest", "0.2.x", "1..0", " 0.2.0", "0.2.0\n",
                  "V0.2.0", "-1.0.0", "+1.0.0", "١.٢.٣", "99999999999999999999.0.0"])
func aTextThatIsNotAReleaseNumberIsNil(text: String) {
    #expect(AppVersion(text) == nil)
}

@Test func versionsCompareNumbersNotText() {
    #expect(AppVersion(0, 10, 0) > AppVersion(0, 9, 0))
    #expect(AppVersion(1, 0, 0) > AppVersion(0, 99, 99))
    #expect(AppVersion(0, 1, 10) > AppVersion(0, 1, 9))
    #expect(AppVersion(0, 1, 0) == AppVersion(0, 1, 0))
    #expect(!(AppVersion(0, 1, 0) < AppVersion(0, 1, 0)))
}

@Test func aVersionReadsWithoutThePrefix() {
    #expect(AppVersion("v0.2.0")?.description == "0.2.0")
    #expect(AppVersion(1, 0, 0).description == "1.0.0")
}

@Test func theReleasePageIsBuiltFromTheVersion() {
    #expect(AppVersion(0, 2, 0).releasePage == URL(string: "https://github.com/askuksov/kombucha/releases/tag/v0.2.0"))
}
