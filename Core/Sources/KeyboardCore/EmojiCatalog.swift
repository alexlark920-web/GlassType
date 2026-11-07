import Foundation

public enum EmojiCategory: String, CaseIterable, Codable {
    case smileys, people, animals, food, travel, activities, objects, symbols, flags, components

    public var titleKey: String {
        switch self {
        case .smileys: return "Смайлы и эмоции"
        case .people: return "Люди и тело"
        case .animals: return "Животные и природа"
        case .food: return "Еда и напитки"
        case .travel: return "Путешествия и места"
        case .activities: return "Занятия"
        case .objects: return "Предметы"
        case .symbols: return "Символы"
        case .flags: return "Флаги"
        case .components: return "Составные символы"
        }
    }

    public var symbolName: String {
        switch self {
        case .smileys: return "face.smiling"
        case .people: return "person.fill"
        case .animals: return "leaf.fill"
        case .food: return "fork.knife"
        case .travel: return "car.fill"
        case .activities: return "figure.run"
        case .objects: return "lightbulb.fill"
        case .symbols: return "number"
        case .flags: return "flag.fill"
        case .components: return "person.crop.circle.fill"
        }
    }
}

public struct EmojiItem: Equatable, Hashable, Identifiable {
    public let emoji: String
    public let name: String
    public var id: String { emoji }

    public init(emoji: String, name: String) {
        self.emoji = emoji
        self.name = name
    }
}

public struct EmojiSection: Equatable, Identifiable {
    public let category: EmojiCategory
    public let entries: [EmojiItem]
    public var id: String { category.rawValue }
}

/// Immutable, bundled Unicode emoji catalog. The resource is parsed once
/// by the keyboard controller; views virtualize cells and never construct every key.
public struct EmojiCatalog {
    public let unicodeVersion: String
    public let sections: [EmojiSection]
    public var count: Int { sections.reduce(0) { $0 + $1.entries.count } }

    private init(unicodeVersion: String, sections: [EmojiSection]) {
        self.unicodeVersion = unicodeVersion
        self.sections = sections
    }

    public static func bundled() -> EmojiCatalog {
        guard let manifestURL = Bundle.module.url(forResource: "emoji_catalog-manifest", withExtension: "json"),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
              let catalogURL = Bundle.module.url(forResource: "emoji_catalog", withExtension: "tsv"),
              let contents = try? String(contentsOf: catalogURL, encoding: .utf8) else {
            return EmojiCatalog(unicodeVersion: "", sections: [])
        }

        var entries: [EmojiCategory: [EmojiItem]] = [:]
        for line in contents.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3,
                  let category = EmojiCategory(rawValue: String(columns[0])) else { continue }
            entries[category, default: []].append(EmojiItem(emoji: String(columns[1]), name: String(columns[2])))
        }
        let sections = EmojiCategory.allCases.compactMap { category -> EmojiSection? in
            guard let categoryEntries = entries[category], !categoryEntries.isEmpty else { return nil }
            return EmojiSection(category: category, entries: categoryEntries)
        }
        let catalog = EmojiCatalog(unicodeVersion: manifest.unicodeVersion, sections: sections)
        guard catalog.count == manifest.emojiCount else {
            return EmojiCatalog(unicodeVersion: "", sections: [])
        }
        return catalog
    }

    private struct Manifest: Decodable {
        let unicodeVersion: String
        let emojiCount: Int
    }
}
