import Foundation

public struct PredictionResult: Equatable {
    public let prefix: String
    public let words: [String]
    public init(prefix: String, words: [String]) { self.prefix = prefix; self.words = words }
}

/// Ranks bounded dictionary candidates with the local adaptive n-gram profile.
/// It has no UIKit, networking, or document-proxy dependency.
public struct PredictionEngine {
    private let generator: CandidateGenerator
    public init(generator: CandidateGenerator = CandidateGenerator()) { self.generator = generator }

    public func predict(context: String, language: KeyboardLanguage,
                        personalLexicon: PersonalLexicon = PersonalLexicon(),
                        model: PersonalNGramModel = PersonalNGramModel(),
                        includeProfanity: Bool = false,
                        nextWordPrediction: Bool = true,
                        limit: Int = 3) -> PredictionResult {
        let prefix = LocalSuggestionProvider.trailingWord(in: String(context.suffix(64)))
        guard limit > 0 else { return PredictionResult(prefix: prefix, words: []) }
        if prefix.isEmpty {
            guard nextWordPrediction else { return PredictionResult(prefix: "", words: []) }
            let words = model.nextWords(after: context, language: language, limit: limit).filter {
                includeProfanity || !SupplementalVocabulary.isProfanity($0, language: language)
            }
            return PredictionResult(prefix: "", words: Array(words.prefix(limit)))
        }

        let candidates = generator.candidates(prefix: prefix, language: language,
                                              personalLexicon: personalLexicon,
                                              includeProfanity: includeProfanity,
                                              limit: max(limit * 6, 18))
        let previousContext = String(context.dropLast(prefix.count))
        let personalCandidates = Set(personalLexicon.completions(for: prefix, limit: 8).map { $0.lowercased() })
        let ranked = candidates.enumerated().sorted { left, right in
            let leftScore = model.score(left.element, after: previousContext, language: language)
            let rightScore = model.score(right.element, after: previousContext, language: language)
            if abs(leftScore - rightScore) > 0.000_001 { return leftScore > rightScore }
            let leftIsPersonal = personalCandidates.contains(left.element.lowercased())
            let rightIsPersonal = personalCandidates.contains(right.element.lowercased())
            if leftIsPersonal != rightIsPersonal { return leftIsPersonal }
            let leftRank = OfflineLexicon.frequencyIndex(word: left.element, language: language) ?? Int.max
            let rightRank = OfflineLexicon.frequencyIndex(word: right.element, language: language) ?? Int.max
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
        return PredictionResult(prefix: prefix, words: Array(ranked.prefix(limit)))
    }
}

/// Spacing for a glide word follows punctuation already committed at the caret.
public enum GlideWordSpacing {
    private static let openingPunctuation = Set("([{«“„‘\"")
    public static func leadingSpace(after context: String?) -> String {
        guard let last = context?.last else { return "" }
        if last.isWhitespace || openingPunctuation.contains(last) { return "" }
        if last.isLetter || last.isNumber { return " " }
        guard let scalar = last.unicodeScalars.first else { return "" }
        return CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) ? " " : ""
    }
}
