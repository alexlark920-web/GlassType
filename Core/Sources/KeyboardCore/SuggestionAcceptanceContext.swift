import Foundation

/// Validates the live text before replacing a prefix and returns the context
/// preceding that prefix. An empty prefix represents a next-word suggestion.
public enum SuggestionAcceptanceContext {
    public static func precedingContext(prefix: String, documentContext: String?) -> String? {
        let context = documentContext ?? ""
        if prefix.isEmpty {
            return LocalSuggestionProvider.trailingWord(in: context).isEmpty ? context : nil
        }
        guard documentContext != nil,
              LocalSuggestionProvider.trailingWord(in: context) == prefix else { return nil }
        return String(context.dropLast(prefix.count))
    }
}
