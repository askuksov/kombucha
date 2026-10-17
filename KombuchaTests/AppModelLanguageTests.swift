import Foundation
import Testing
@testable import Kombucha

@MainActor
private func makeModel(available: [String], restarter: any Restarting = FakeRestarter())
    -> (model: AppModel, defaults: UserDefaults, suite: String) {
    let suite = "dev.kuksov.kombucha.tests.modellanguages.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let model = AppModel()
    model.attach(languages: AppLanguages(available: available, defaults: defaults, domain: suite),
                 restarter: restarter)
    return (model, defaults, suite)
}

@MainActor
@Test func aModelWithOneLanguageIsNotSwitchable() {
    let (model, defaults, suite) = makeModel(available: ["en"])
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(!model.languages.isSwitchable)
}

@MainActor
@Test func choosingALanguageNeedsARestartAndRestartingAsksTheRestarter() {
    let restarter = FakeRestarter()
    let (model, defaults, suite) = makeModel(available: ["en", "de"], restarter: restarter)
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(!model.languages.restartNeeded)
    model.chooseLanguage(.language("de"))
    #expect(model.languages.selection == .language("de"))
    #expect(model.languages.restartNeeded)
    #expect(restarter.restarts == 0)
    model.restart()
    #expect(restarter.restarts == 1)
    #expect(model.restartPending)
    model.restart()
    #expect(restarter.restarts == 1)
}

@MainActor
@Test func aFailedRestartCanBeTriedAgain() {
    let restarter = FailingRestarter()
    let (model, defaults, suite) = makeModel(available: ["en", "de"], restarter: restarter)
    defer { defaults.removePersistentDomain(forName: suite) }
    model.restart()
    #expect(!model.restartPending)
    model.restart()
    #expect(restarter.restarts == 2)
}

@MainActor
@Test func choosingTheLaunchLanguageAgainNeedsNoRestart() {
    let (model, defaults, suite) = makeModel(available: ["en", "de"])
    defer { defaults.removePersistentDomain(forName: suite) }
    model.chooseLanguage(.language("de"))
    model.chooseLanguage(.system)
    #expect(!model.languages.restartNeeded)
}

@MainActor
@Test func restartingWithoutARestarterDoesNothing() {
    AppModel().restart()
}
