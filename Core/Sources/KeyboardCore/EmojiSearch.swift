import Foundation

/// Offline search over the bundled emoji annotations. Aliases cover common
/// Russian and Ukrainian terms because Unicode's bundled annotations are English.
public enum EmojiSearch {
    private static let aliases: [(localized: String, english: String)] = [
        ("улыб", "smil"), ("посміш", "smil"), ("сме", "laugh"), ("смі", "laugh"),
        ("привет", "waving hand"), ("привіт", "waving hand"), ("hello", "waving hand"), ("серд", "heart"),
        ("кот", "cat"), ("кіт", "cat"), ("собак", "dog"), ("пес", "dog"), ("песик", "dog"),
        ("огон", "fire"), ("вогон", "fire"), ("вогн", "fire"),
        ("флаг укра", "flag: ukraine"), ("прапор укра", "flag: ukraine"),
        ("флаг", "flag"), ("прапор", "flag"), ("еда", "food"), ("їжа", "food"),
        ("кофе", "coffee"), ("кава", "coffee"), ("серце", "heart"), ("сонце", "sun")
    ]

    /// Returns catalogue-ordered matches and applies the limit after filtering.
    /// A query may be an English Unicode annotation, a localized alias, or the
    /// emoji sequence itself. Matching is case- and diacritic-insensitive.
    public static func search(_ query: String, in items: [EmojiItem], limit: Int? = nil) -> [EmojiItem] {
        let normalized = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty else { return [] }

        let expanded = aliases.compactMap { alias -> String? in
            normalized.contains(normalize(alias.localized)) ? normalize(alias.english) : nil
        }
        let matches = items.lazy.filter { item in
            item.emoji.contains(query) || normalize(item.name).contains(normalized) ||
                expanded.contains(where: { normalize(item.name).contains($0) })
        }
        guard let limit, limit >= 0 else { return Array(matches) }
        return Array(matches.prefix(limit))
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
