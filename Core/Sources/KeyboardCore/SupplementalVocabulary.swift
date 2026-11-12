import Foundation

/// Small, bundled colloquial vocabulary and a separately classified profanity
/// set. These entries are local only and are never learned from typed text.
public enum SupplementalVocabulary {
    private static let englishProfanity = Set(["fuck", "fucks", "fucked", "fucking", "fucker", "fuckers", "motherfucker", "motherfuckers", "shit", "shits", "shitty", "bullshit", "bitch", "bitches", "bitchy", "asshole", "assholes", "damn", "dammit"])
    private static let russianProfanity = Set(["блядь", "бля", "блядский", "блядская", "блядское", "блядские", "хуй", "хуя", "хуе", "хуёвый", "хуевый", "пизда", "пиздец", "пиздеть", "ебать", "ебёт", "ебет", "заебал", "заебала", "сука", "суки", "мудак", "мудила"])
    private static let ukrainianProfanity = Set(["блядь", "бля", "хуй", "хуя", "пизда", "пиздець", "пиздити", "єбати", "їбати", "сука", "суки", "мудак"])
    private static let englishWords = ["based", "bet", "brainrot", "bruh", "bussin", "cap", "cringe", "delulu", "finna", "flex", "ghosted", "goated", "gyatt", "ick", "mid", "noob", "nope", "rizz", "rizzler", "salty", "sigma", "simp", "skibidi", "slay", "sus", "vibe", "vibing", "yeet", "fuck", "fucking", "fucked", "fucker", "shit", "shitty", "bullshit", "bitch", "bitches", "asshole", "damn", "motherfucker"]
    private static let russianWords = ["вайб", "вайбовый", "кринж", "кринжовый", "имба", "рофл", "рофлить", "токсик", "чилл", "чилить", "зашквар", "жиза", "краш", "слэй", "база", "базированный", "хайп", "хайповый", "пофиг", "пофигу", "блядь", "бля", "блядский", "хуй", "хуя", "хуёвый", "пизда", "пиздец", "ебать", "ебёт", "заебал", "сука", "мудак"]
    private static let ukrainianWords = ["вайб", "вайбовий", "крінж", "крінжовий", "імба", "рофл", "рофлити", "токсик", "чил", "чилити", "зашквар", "жиза", "краш", "база", "хайп", "пофіг", "блядь", "бля", "хуй", "хуя", "пизда", "пиздець", "єбати", "їбати", "сука", "мудак"]
    public static func words(for language: KeyboardLanguage) -> [String] {
        switch language {
        case .english: return englishWords
        case .russian: return russianWords
        case .ukrainian: return ukrainianWords
        }
    }

    public static func isProfanity(_ word: String, language: KeyboardLanguage) -> Bool {
        let candidate = normalize(word)
        guard !candidate.isEmpty else { return false }
        return profanity(for: language).contains(candidate)
    }

    private static func profanity(for language: KeyboardLanguage) -> Set<String> {
        switch language {
        case .english: return englishProfanity
        case .russian: return russianProfanity
        case .ukrainian: return ukrainianProfanity
        }
    }

    private static func normalize(_ value: String) -> String {
        if value == value.lowercased(), !value.contains("ё"), !value.contains("’") { return value }
        return value.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: "’", with: "'")
    }
}
