import Foundation

/// The languages the app can show and the one the user chose. A choice is written as `AppleLanguages` in the
/// app's own defaults and takes effect at the next launch.
struct AppLanguages {
    enum Selection: Hashable {
        case system
        case language(String)
    }

    struct Language: Equatable, Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    static let key = "AppleLanguages"

    /// Empty when there is nothing to choose between.
    let languages: [Language]
    private(set) var selection: Selection
    private let launchSelection: Selection
    private let codes: [String]
    private let defaults: UserDefaults

    init(available: [String], defaults: UserDefaults, domain: String) {
        let codes = Set(available).subtracting(["Base"]).sorted()
        self.codes = codes
        self.languages = codes.count < 2 ? [] : codes.map { Language(code: $0, name: Self.nativeName($0)) }
        self.defaults = defaults
        let stored = Self.stored(in: defaults, domain: domain, codes: codes)
        self.selection = stored
        self.launchSelection = stored
    }

    static var current: AppLanguages {
        AppLanguages(available: Bundle.main.localizations, defaults: .standard,
                     domain: Bundle.main.bundleIdentifier ?? "")
    }

    var isSwitchable: Bool { !languages.isEmpty }

    /// The stored choice differs from the one the running process started with.
    var restartNeeded: Bool { selection != launchSelection }

    mutating func select(_ selection: Selection) {
        guard isSwitchable else { return }
        switch selection {
        case .system:
            defaults.removeObject(forKey: Self.key)
        case .language(let code):
            guard codes.contains(code) else { return }
            defaults.set([code], forKey: Self.key)
        }
        self.selection = selection
    }

    /// Reads the app's own domain only: `array(forKey:)` would also answer the launch argument and the system list.
    private static func stored(in defaults: UserDefaults, domain: String, codes: [String]) -> Selection {
        guard let first = (defaults.persistentDomain(forName: domain)?[key] as? [String])?.first,
              let code = codes.first(where: { first == $0 || first.hasPrefix($0 + "-") }) else { return .system }
        return .language(code)
    }

    private static func nativeName(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
