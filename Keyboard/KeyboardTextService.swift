import UIKit
import KeyboardCore

/// Narrow UIKit boundary for local spelling plus GlassType's explicit and
/// offline correction sources. It never reads or persists surrounding text.
protocol SystemSpellingChecking {
    func check(_ word: String, language: KeyboardLanguage) -> (known: Bool, candidates: [String])
}

final class KeyboardTextService {
    private let correctionPipeline: AutocorrectionPipeline
    private let spelling: SystemSpellingChecking

    init(correctionPipeline: AutocorrectionPipeline = AutocorrectionPipeline(),
         spelling: SystemSpellingChecking? = nil) {
        self.correctionPipeline = correctionPipeline
        self.spelling = spelling ?? SystemSpelling()
    }

    func replacement(for word: String, language: KeyboardLanguage,
                     personalLexicon: PersonalLexicon,
                     includeProfanity: Bool = false,
                     languageModel: PersonalNGramModel = PersonalNGramModel(),
                     previousContext: String = "") -> String? {
        let needsDictionary = correctionPipeline.needsDictionaryChecks(for: word, language: language,
                                                                       personalLexicon: personalLexicon)
        let local = needsDictionary ? OfflineLexicon.preparedCheck(word, language: language, includeProfanity: includeProfanity) : nil
        let system: (known: Bool, candidates: [String])
        if let local, local.known {
            system = (known: true, candidates: [])
        } else if needsDictionary {
            let check = spelling.check(word, language: language)
            system = (known: check.known, candidates: includeProfanity ? check.candidates : check.candidates.filter { !SupplementalVocabulary.isProfanity($0, language: language) })
        } else {
            system = (known: false, candidates: [])
        }
        let replacement = correctionPipeline.replacement(for: word, language: language,
                                              personalLexicon: personalLexicon,
                                              offlineCheck: local,
                                              systemWordIsKnown: system.known,
                                              systemCandidates: system.candidates,
                                              languageModel: languageModel,
                                              previousContext: previousContext)
        guard includeProfanity || replacement.map({ !SupplementalVocabulary.isProfanity($0, language: language) }) == true else { return nil }
        return replacement
    }
}

/// UIKit adapter uses the device's local dictionary; no network or learning.
private final class SystemSpelling: SystemSpellingChecking {
    private let checker = UITextChecker()

    func check(_ word: String, language: KeyboardLanguage) -> (known: Bool, candidates: [String]) {
        let available = UITextChecker.availableLanguages
        let preferred: String
        switch language {
        case .english: preferred = "en_US"
        case .russian: preferred = "ru_RU"
        case .ukrainian: preferred = "uk_UA"
        }
        guard let code = available.first(where: { $0 == preferred }) ?? available.first(where: {
            $0.replacingOccurrences(of: "_", with: "-").lowercased().hasPrefix(language.rawValue + "-") || $0 == language.rawValue
        }) else { return (false, []) }
        let text = word.lowercased()
        let range = NSRange(location: 0, length: (text as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(in: text, range: range, startingAt: 0, wrap: false, language: code)
        if misspelled.location == NSNotFound { return (true, []) }
        return (false, Array((checker.guesses(forWordRange: range, in: text, language: code) ?? []).prefix(8)))
    }
}
