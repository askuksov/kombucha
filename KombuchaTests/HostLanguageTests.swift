import Foundation
import Testing

@Test func theTestsRunInEnglishWhateverTheMacSpeaks() {
    #expect(Locale.preferredLanguages.first?.hasPrefix("en") == true)
}
