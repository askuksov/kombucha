import Foundation
import Testing

/// Reads a String Catalog as JSON and reports what a declared language is missing.
enum CatalogAudit {
    private struct Catalog {
        let source: String
        let strings: [String: [String: Any]]
    }

    private static func parse(_ data: Data) throws -> Catalog {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let source = root["sourceLanguage"] as? String,
              let strings = root["strings"] as? [String: [String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Catalog(source: source, strings: strings)
    }

    private static func translatable(_ catalog: Catalog) -> [(key: String, entry: [String: Any])] {
        catalog.strings
            .filter { $0.value["shouldTranslate"] as? Bool != false }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, entry: $0.value) }
    }

    /// The source language and every language any entry carries.
    static func languages(in data: Data) throws -> [String] {
        let catalog = try parse(data)
        var found: Set<String> = [catalog.source]
        for entry in catalog.strings.values {
            if let localizations = entry["localizations"] as? [String: Any] {
                found.formUnion(localizations.keys)
            }
        }
        return found.sorted()
    }

    /// `"<language>: <key>"` for every translatable entry that lacks a filled value in a declared language. The
    /// source language may omit a value (the key is the value) but not leave it empty.
    static func gaps(in data: Data) throws -> [String] {
        let catalog = try parse(data)
        let all = try languages(in: data)
        var gaps: [String] = []
        for (key, entry) in translatable(catalog) {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in all {
                guard let localization = localizations[language] as? [String: Any] else {
                    if language != catalog.source { gaps.append("\(language): \(key)") }
                    continue
                }
                if !isFilled(localization) { gaps.append("\(language): \(key)") }
            }
        }
        return gaps
    }

    /// `"<language>: <key>"` for every translated plain value whose placeholders differ from the source's.
    /// Plural variations are skipped: a singular form may legitimately drop the number.
    static func placeholderMismatches(in data: Data) throws -> [String] {
        let catalog = try parse(data)
        var mismatches: [String] = []
        for (key, entry) in translatable(catalog) {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let expected = placeholders(in: value(of: localizations[catalog.source]) ?? key)
            for (language, localization) in localizations where language != catalog.source {
                guard let text = value(of: localization), placeholders(in: text) != expected else { continue }
                mismatches.append("\(language): \(key)")
            }
        }
        return mismatches.sorted()
    }

    static func placeholders(in text: String) -> [String] {
        let pattern = #/%(?:\d+\$)?(?:\.\d+)?(?:lld|ld|d|@|f|u|s)/#
        return text.matches(of: pattern)
            .map { String(text[$0.range]).replacing(#/\d+\$/#, with: "") }
            .sorted()
    }

    private static func value(of localization: Any?) -> String? {
        ((localization as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    private static func isFilled(_ localization: [String: Any]) -> Bool {
        if let unit = localization["stringUnit"] as? [String: Any] {
            return !((unit["value"] as? String) ?? "").isEmpty
        }
        if let variations = localization["variations"] as? [String: Any] {
            let cases = variations.values
                .compactMap { $0 as? [String: Any] }
                .flatMap { $0.values.compactMap { $0 as? [String: Any] } }
            return !cases.isEmpty && cases.allSatisfy { isFilled($0) }
        }
        return false
    }
}

private let catalogURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Kombucha/Resources/Localizable.xcstrings")

private func unit(_ value: String) -> String {
    #"{"stringUnit":{"state":"translated","value":"\#(value)"}}"#
}

private func entry(_ values: [String: String]) -> String {
    let body = values.sorted { $0.key < $1.key }.map { #""\#($0.key)":\#(unit($0.value))"# }.joined(separator: ",")
    return #"{"localizations":{\#(body)}}"#
}

/// `entries` maps a key to the JSON of its entry.
private func catalog(_ entries: [String: String]) -> Data {
    let body = entries.sorted { $0.key < $1.key }.map { #""\#($0.key)":\#($0.value)"# }.joined(separator: ",")
    return Data(#"{"sourceLanguage":"en","strings":{\#(body)},"version":"1.0"}"#.utf8)
}

@Test func theShippedCatalogHasEveryValueForEveryLanguage() throws {
    let data = try Data(contentsOf: catalogURL)
    #expect(try CatalogAudit.languages(in: data).contains("en"))
    #expect(try CatalogAudit.gaps(in: data) == [])
}

@Test func theShippedCatalogKeepsEveryPlaceholder() throws {
    #expect(try CatalogAudit.placeholderMismatches(in: Data(contentsOf: catalogURL)) == [])
}

@Test func aCompleteCatalogHasNoGaps() throws {
    let data = catalog(["Hello": entry(["en": "Hello", "de": "Hallo"]), "Bye": entry(["en": "Bye", "de": "Tschüss"])])
    #expect(try CatalogAudit.languages(in: data) == ["de", "en"])
    #expect(try CatalogAudit.gaps(in: data) == [])
}

@Test func aMissingValueIsNamed() throws {
    let data = catalog(["Hello": entry(["en": "Hello", "de": "Hallo"]), "Bye": entry(["en": "Bye"])])
    #expect(try CatalogAudit.gaps(in: data) == ["de: Bye"])
}

@Test func anEmptyValueIsAGap() throws {
    let data = catalog(["Hello": entry(["en": "Hello", "de": ""])])
    #expect(try CatalogAudit.gaps(in: data) == ["de: Hello"])
}

@Test func theSourceLanguageMayOmitAValueButNotLeaveItEmpty() throws {
    let omitted = catalog(["Hello": entry(["de": "Hallo"])])
    #expect(try CatalogAudit.gaps(in: omitted) == [])
    let empty = catalog(["Hello": entry(["en": "", "de": "Hallo"])])
    #expect(try CatalogAudit.gaps(in: empty) == ["en: Hello"])
}

@Test func anEntryMarkedNotToTranslateIsExempt() throws {
    let exempt = #"{"shouldTranslate":false,"localizations":{"en":\#(unit("OK"))}}"#
    let data = catalog(["OK": exempt, "Hello": entry(["en": "Hello", "de": "Hallo"])])
    #expect(try CatalogAudit.gaps(in: data) == [])
}

private func plural(_ one: String, _ other: String) -> String {
    #"{"variations":{"plural":{"one":\#(unit(one)),"other":\#(unit(other))}}}"#
}

@Test func aPluralWithAMissingFormIsAGap() throws {
    let whole = #"{"localizations":{"en":\#(plural("%lld day", "%lld days")),"de":\#(plural("%lld Tag", "%lld Tage"))}}"#
    let lacking = #"{"localizations":{"en":\#(plural("%lld day", "%lld days")),"de":\#(plural("%lld Tag", ""))}}"#
    #expect(try CatalogAudit.gaps(in: catalog(["days": whole])) == [])
    #expect(try CatalogAudit.gaps(in: catalog(["days": lacking])) == ["de: days"])
}

@Test func aTranslationThatLosesAPlaceholderIsNamed() throws {
    let data = catalog(["%lld min": entry(["en": "%lld min", "de": "Minuten"]),
                        "Hello": entry(["en": "Hello", "de": "Hallo"])])
    #expect(try CatalogAudit.placeholderMismatches(in: data) == ["de: %lld min"])
}

@Test func reorderedPositionalPlaceholdersAreNotAMismatch() throws {
    let data = catalog(["%@ of %@": entry(["en": "%@ of %@", "de": "%2$@ von %1$@"])])
    #expect(try CatalogAudit.placeholderMismatches(in: data) == [])
}

@Test func aLiteralPercentIsNotAPlaceholder() {
    #expect(CatalogAudit.placeholders(in: "%lld%% of %@") == ["%@", "%lld"])
}
