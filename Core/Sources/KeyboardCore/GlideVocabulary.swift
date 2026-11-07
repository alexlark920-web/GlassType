import Foundation

extension GlideDecoder {
    /// The complete rank-sorted bundled corpus is indexed before any geometric
    /// candidate cap. Common conversational words are included in that corpus.
    static func words(for language: KeyboardLanguage) -> [String] {
        OfflineLexicon.words(language: language)
    }
}
