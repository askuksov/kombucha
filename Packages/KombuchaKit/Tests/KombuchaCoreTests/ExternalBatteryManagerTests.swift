import KombuchaCore
import Testing

private let ownBundle = "/Applications/Kombucha.app"

private func verdict(_ paths: [String], ownBundlePath: String = ownBundle) -> ExternalBatteryManager? {
    ExternalBatteryManagers.verdict(executablePaths: paths, ownBundlePath: ownBundlePath, table: ExternalBatteryManagers.table)
}

@Test func noProcessesMeansNoExternalBatteryManager() {
    #expect(verdict([]) == nil)
    #expect(verdict(["/usr/libexec/secinitd", "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"]) == nil)
}

@Test func battIsFoundByItsFileName() {
    #expect(verdict(["/opt/homebrew/bin/batt"]) == .batt)
    #expect(verdict(["/usr/local/bin/batt"]) == .batt)
}

@Test func battOptIsFoundByItsMeasuredPathAndItsBundle() {
    #expect(verdict(["/Library/Application Support/battopt/battopt"]) == .battOpt)
    #expect(verdict(["/Applications/BattOpt.app/Contents/MacOS/BattOpt"]) == .battOpt)
}

@Test func battAndBattOptAreNeverConfused() {
    #expect(verdict(["/Library/Application Support/battopt/battopt"]) != .batt)
    #expect(verdict(["/opt/homebrew/bin/batt"]) != .battOpt)
}

@Test func aHomebrewBattOptIsNotOneOfTheKnownIdentities() {
    #expect(verdict(["/opt/homebrew/bin/battopt"]) == nil)
}

@Test func aProductWhoseNameStartsWithAKnownOneDoesNotMatch() {
    #expect(verdict(["/Applications/BattOptimizer.app/Contents/MacOS/BattOptimizer"]) == nil)
}

@Test func aBundleOutsideApplicationsDoesNotMatch() {
    #expect(verdict(["/Users/someone/Applications/BattOpt.app/Contents/MacOS/BattOpt"]) == nil)
    #expect(verdict(["/Users/someone/Downloads/AlDente.app/Contents/MacOS/AlDente"]) == nil)
}

@Test func theAlDenteHelperAloneIsEnough() {
    #expect(verdict(["/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro.helper"]) == .alDente)
}

@Test func batFiIsFoundByItsBundle() {
    #expect(verdict(["/Applications/BatFi.app/Contents/MacOS/BatFi"]) == .batFi)
}

@Test func kombuchaFloatIsFoundByItsAppAlone() {
    #expect(verdict(["/Applications/Float.app/Contents/MacOS/kombucha-float"]) == .kombuchaFloat)
    #expect(verdict(["/Applications/Kombucha Float.app/Contents/MacOS/kombucha-float-helper"]) == nil)
}

@Test func theFirstRowInTableOrderIsReported() {
    let paths = [
        "/opt/homebrew/bin/batt",
        "/Applications/BatFi.app/Contents/MacOS/BatFi",
        "/Applications/BattOpt.app/Contents/MacOS/BattOpt",
    ]
    #expect(verdict(paths) == .battOpt)
    #expect(verdict(["/opt/homebrew/bin/batt", "/Applications/BatFi.app/Contents/MacOS/BatFi"]) == .batFi)
}

@Test func processesInsideOurOwnBundleNeverMatch() {
    #expect(verdict(["/Applications/Kombucha.app/Contents/MacOS/kombucha-float"]) == nil)
    #expect(verdict(["/Applications/Kombucha.app/Contents/MacOS/kombucha-helper"]) == nil)
    #expect(verdict(["/Applications/Kombucha.app/Contents/MacOS/kombucha-float"],
                    ownBundlePath: "/Users/someone/Applications/Kombucha.app") == .kombuchaFloat)
}

@Test func theBundleIdentityNeedsTheContentsDirectory() {
    #expect(verdict(["/Applications/BattOpt.app"]) == nil)
    #expect(verdict(["/Applications/BattOpt.appendix/Contents/MacOS/Other"]) == nil)
}

@Test func everyExternalBatteryManagerHasARowAndADisplayName() {
    #expect(ExternalBatteryManagers.table.map(\.externalBatteryManager) == ExternalBatteryManager.allCases)
    #expect(ExternalBatteryManager.allCases.map(\.displayName) == ["BattOpt", "AlDente", "BatFi", "batt", "Kombucha Float"])
}
