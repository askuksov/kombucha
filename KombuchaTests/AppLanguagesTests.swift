import Foundation
import Testing
@testable import Kombucha

/// A throwaway suite per test: free tests run in parallel and must not share a domain.
private func freshDefaults() -> (defaults: UserDefaults, suite: String) {
    let suite = "dev.kuksov.kombucha.tests.languages.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}

private func storedCodes(_ defaults: UserDefaults, _ suite: String) -> [String]? {
    defaults.persistentDomain(forName: suite)?[AppLanguages.key] as? [String]
}

@Test func fewerThanTwoLanguagesOfferNothingToChoose() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    for available in [["en"], ["en", "Base"], []] {
        let languages = AppLanguages(available: available, defaults: defaults, domain: suite)
        #expect(languages.languages.isEmpty)
        #expect(!languages.isSwitchable)
    }
}

@Test func languagesAreNamedInTheirOwnLanguageAndOrderedByCode() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let languages = AppLanguages(available: ["uk", "en", "de", "Base"], defaults: defaults, domain: suite)
    #expect(languages.isSwitchable)
    #expect(languages.languages.map(\.code) == ["de", "en", "uk"])
    #expect(languages.languages.map(\.name) == ["Deutsch", "English", "Українська"])
}

@Test func nothingStoredReadsAsSystemDefault() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    #expect(languages.selection == .system)
    #expect(!languages.restartNeeded)
}

@Test func choosingALanguageWritesAppleLanguages() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    var languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    languages.select(.language("de"))
    #expect(languages.selection == .language("de"))
    #expect(storedCodes(defaults, suite) == ["de"])
}

@Test func choosingSystemDefaultRemovesTheKey() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    var languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    languages.select(.language("de"))
    languages.select(.system)
    #expect(languages.selection == .system)
    #expect(storedCodes(defaults, suite) == nil)
}

@Test func aChoiceOutsideTheListIsIgnored() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    var languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    languages.select(.language("xx"))
    #expect(languages.selection == .system)
    #expect(storedCodes(defaults, suite) == nil)
}

@Test func aRestartIsNeededOnlyWhileTheChoiceDiffersFromTheLaunchChoice() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    var languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    #expect(!languages.restartNeeded)
    languages.select(.language("de"))
    #expect(languages.restartNeeded)
    languages.select(.language("en"))
    #expect(languages.restartNeeded)
    languages.select(.system)
    #expect(!languages.restartNeeded)
}

@Test func aStoredChoiceIsReadBackAndIsNotARestart() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    var first = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    first.select(.language("de"))
    let second = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    #expect(second.selection == .language("de"))
    #expect(!second.restartNeeded)
}

@Test func aRegionalStoredCodeResolvesToItsLanguage() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["de-DE"], forKey: AppLanguages.key)
    let languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    #expect(languages.selection == .language("de"))
}

@Test func anUnknownStoredCodeReadsAsSystemAndStaysStored() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["xx"], forKey: AppLanguages.key)
    let languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    #expect(languages.selection == .system)
    #expect(storedCodes(defaults, suite) == ["xx"])
}

@Test func aGlobalOrArgumentLanguageIsNotTakenForAChoice() {
    // The test scheme launches with -AppleLanguages (en), so array(forKey:) answers from sources that are not
    // persisted. A registered default stands in for them: only the app's own stored domain may read as a choice.
    // Registration is process-wide and permanent for the test host; harmless, because nothing reads
    // AppleLanguages through array(forKey:) and the argument domain outranks registration.
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.register(defaults: [AppLanguages.key: ["de"]])
    let languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    #expect(languages.selection == .system)
    #expect(!languages.restartNeeded)
}

@Test func aRestartFromAStoredLaunchLanguageIsMeasuredAgainstThatLanguage() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["de"], forKey: AppLanguages.key)
    var languages = AppLanguages(available: ["en", "de"], defaults: defaults, domain: suite)
    #expect(languages.selection == .language("de"))
    #expect(!languages.restartNeeded)
    languages.select(.language("en"))
    #expect(languages.restartNeeded)
    languages.select(.language("de"))
    #expect(!languages.restartNeeded)
    languages.select(.system)
    #expect(languages.restartNeeded)
}

@Test func selectingWithASingleLanguageChangesNothing() {
    let (defaults, suite) = freshDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["fr"], forKey: AppLanguages.key)
    var languages = AppLanguages(available: ["en"], defaults: defaults, domain: suite)
    languages.select(.language("en"))
    #expect(storedCodes(defaults, suite) == ["fr"])
    languages.select(.system)
    #expect(storedCodes(defaults, suite) == ["fr"])
    #expect(languages.selection == .system)
}
