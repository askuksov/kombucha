# Add a translation

Kombucha reads every user-facing sentence from one String Catalog, `Kombucha/Resources/Localizable.xcstrings`.
A language is a new column in that file. No code changes: once the catalog has two languages, the app shows a
Language row in Settings → General by itself, and macOS picks the language from System Settings as for any app.

## 1. Add the language to the catalog

Open `Localizable.xcstrings` in Xcode (the catalog editor) and add the language, or edit the JSON by hand. Each
entry gets one more block next to `en`:

```json
"de" : { "stringUnit" : { "state" : "translated", "value" : "…" } }
```

`xcstringstool sync` does not work with Xcode 26.6, so new English keys are added by hand when the code gains a
string. Translate every entry: the catalog test names what is missing.

## 2. Keep the placeholders

`%@` stands for text and `%lld` for a whole number. Keep every one in the translation. If the grammar needs another
order, number them: English `%@ of %@` can become `%2$@ von %1$@`. A literal percent sign is `%%`.

## 3. Plurals

A string with a count uses the catalog's "Vary by Plural". Give every plural category your language needs (German
has `one` and `other`; Ukrainian also has `few` and `many`). The catalog test fails if one form is empty.

## 4. What not to translate

- The product name: **Kombucha**.
- The idea behind **Battery Rest**: the state where the battery sits idle while the Mac runs from the adapter. If
  your language has no good short term, keep "Battery Rest" and explain it in the pull request.
- Exact moments keep the house format `yyyy-MM-dd HH:mm` in every language. Weekday and month names on the History
  chart are localized by macOS.
- File names, command names and `code`-style words.

## 5. Check it

```
make test-app
```

The test scheme always runs in English, so the suite gives the same result on any Mac. To see your language, run
the built app with a launch argument (this starts the live engine like any launch):

```
build/DerivedData/Build/Products/Debug/Kombucha.app/Contents/MacOS/Kombucha -AppleLanguages "(de)"
```

To look for text that does not fit, add `-NSDoubleLocalizedStrings YES`: every string is doubled in length. Look at
the menu bar panel, every Settings tab and a notification.

## 6. Send it

Open a pull request with the catalog change. Say which language and whether you are a native speaker.
