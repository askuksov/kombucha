import KombuchaCore
import Testing

private let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
private let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework"
    + "/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"

private func reading(_ seconds: Double, _ rows: [(Int32, String, UInt64)]) -> EnergyReading {
    EnergyReading(samples: rows.map { EnergySample(pid: $0.0, executablePath: $0.1, energyNanojoules: $0.2) },
                  seconds: seconds)
}

@Test func theEnergyDeltaOverTheIntervalIsWatts() {
    let before = reading(10, [(1, "/Applications/Xcode.app/Contents/MacOS/Xcode", 1_000_000_000)])
    let after = reading(12, [(1, "/Applications/Xcode.app/Contents/MacOS/Xcode", 5_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after) == [AppEnergy(name: "Xcode", watts: 2.0)])
}

@Test func anAppsHelperProcessesAreOneApp() {
    let before = reading(0, [(1, chrome, 0), (2, chromeHelper, 0)])
    let after = reading(1, [(1, chrome, 1_000_000_000), (2, chromeHelper, 3_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after) == [AppEnergy(name: "Google Chrome", watts: 4.0)])
}

@Test func aProgramOutsideAnAppBundleIsNamedByItsExecutable() {
    let before = reading(0, [(7, "/usr/bin/yes", 0)])
    let after = reading(1, [(7, "/usr/bin/yes", 2_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after) == [AppEnergy(name: "yes", watts: 2.0)])
}

@Test func aProcessSeenOnlyOnceIsSkipped() {
    let before = reading(0, [(1, chrome, 0)])
    let after = reading(1, [(2, "/usr/bin/yes", 9_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after).isEmpty)
}

@Test func aReusedPidIsNotChargedWithTheOldCounter() {
    let before = reading(0, [(5, chrome, 8_000_000_000)])
    let after = reading(1, [(5, "/usr/bin/yes", 8_500_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after).isEmpty)
}

@Test func aCounterThatWentBackwardsIsSkippedNotWrapped() {
    let before = reading(0, [(1, chrome, 9_000_000_000)])
    let after = reading(1, [(1, chrome, 1_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after).isEmpty)
}

@Test(arguments: [0.0, -1.0])
func aNonPositiveIntervalGivesNothing(seconds: Double) {
    let before = reading(5, [(1, chrome, 0)])
    let after = reading(5 + seconds, [(1, chrome, 1_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after).isEmpty)
}

@Test func theListIsSortedLimitedAndFloored() {
    func app(_ name: String) -> String { "/Applications/\(name).app/Contents/MacOS/\(name)" }
    let before = reading(0, [(1, app("A"), 0), (2, app("B"), 0), (3, app("C"), 0), (4, app("D"), 0), (5, app("E"), 0)])
    // A 5 W, B 4 W, C 4 W, D 3 W, E 0.005 W: B and C tie on watts and sort by name; E is under the floor.
    let after = reading(1, [(1, app("A"), 5_000_000_000), (2, app("B"), 4_000_000_000),
                            (3, app("C"), 4_000_000_000), (4, app("D"), 3_000_000_000), (5, app("E"), 5_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after).map(\.name) == ["A", "B", "C"])
    #expect(EnergyRanking.top(10, previous: before, current: after).map(\.name) == ["A", "B", "C", "D"])
    #expect(EnergyRanking.top(0, previous: before, current: after).isEmpty)
}

@Test(arguments: [
    ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "Google Chrome"),
    ("/usr/bin/yes", "yes"),
    ("/x/.app/y", "y"),
    ("/Applications/Foo.app/Contents/Frameworks/Bar.app/Contents/MacOS/Bar", "Foo"),
    ("yes", "yes"),
] as [(String, String?)])
func anAppIsNamedByItsBundleOrItsExecutable(path: String, name: String?) {
    #expect(EnergyRanking.appName(of: path) == name)
}

@Test(arguments: ["", "/"])
func aPathWithNoNameHasNoApp(path: String) {
    #expect(EnergyRanking.appName(of: path) == nil)
}

@Test func theFloorIsFiftyMilliwattsInclusive() {
    let app = "/Applications/A.app/Contents/MacOS/A"
    let before = reading(0, [(1, app, 0)])
    #expect(EnergyRanking.top(3, previous: before, current: reading(1, [(1, app, 49_000_000)])).isEmpty)
    #expect(EnergyRanking.top(3, previous: before, current: reading(1, [(1, app, 50_000_000)]))
        == [AppEnergy(name: "A", watts: 0.05)])
}

@Test func helpersEachUnderTheFloorAreSummedBeforeFlooring() {
    let main = "/Applications/A.app/Contents/MacOS/A"
    let helper = "/Applications/A.app/Contents/Frameworks/H.app/Contents/MacOS/H"
    let before = reading(0, [(1, main, 0), (2, helper, 0)])
    let after = reading(1, [(1, main, 30_000_000), (2, helper, 30_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after).map(\.name) == ["A"])
}

@Test(arguments: [
    "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/WebContent",
    "/usr/libexec/trustd",
    "/usr/sbin/cfprefsd",
    "/sbin/launchd",
])
func aSystemExecutableIsNotListed(path: String) {
    let before = reading(0, [(1, path, 0)])
    let after = reading(1, [(1, path, 2_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after).isEmpty)
}

@Test(arguments: [
    ("/System/Applications/Mail.app/Contents/MacOS/Mail", "Mail"),
    ("/usr/bin/yes", "yes"),
])
func aUserRunProgramUnderSystemPathsIsListed(path: String, name: String) {
    let before = reading(0, [(1, path, 0)])
    let after = reading(1, [(1, path, 2_000_000_000)])
    #expect(EnergyRanking.top(3, previous: before, current: after) == [AppEnergy(name: name, watts: 2.0)])
}
