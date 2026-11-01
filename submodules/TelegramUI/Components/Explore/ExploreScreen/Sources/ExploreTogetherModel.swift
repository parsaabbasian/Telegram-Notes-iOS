import Foundation

// Only navigation metadata is persisted here. Topic messages remain on Telegram.
struct ExplorationReference: Codable, Equatable {
    let groupId: Int64
    let topicId: Int64
    var title: String
    var groupTitle: String
    var purposeMessageId: Int32?

    static func storageKey(accountId: Int64) -> String { "explore-together-v1-\(accountId)" }
    var key: String { "\(groupId):\(topicId)" }
}

enum TogetherRelevance {
    // Local retrieval only; this query never becomes a discovery signal.
    static func matchesSearch(_ query: String, text: String) -> Bool {
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "ي", with: "ی").replacingOccurrences(of: "ك", with: "ک")
                .replacingOccurrences(of: "\u{200c}", with: " ")
        }
        let haystack = normalized(text)
        return normalized(query).split(whereSeparator: { $0.isWhitespace }).allSatisfy { haystack.contains($0) }
    }

    struct Match {
        let index: Int
        let terms: [String]
    }

    static func ranked(title: String, publicSourceTexts: [String], candidates: [ExploreSimilarity.Candidate]) -> [Match] {
        let sourceText = ([title] + publicSourceTexts).joined(separator: " ")
        let matches = candidates.enumerated().compactMap { index, candidate -> Match? in
            let terms = ExploreSimilarity.sharedTerms(sourceText, candidate.text)
            return terms.isEmpty ? nil : Match(index: index, terms: terms)
        }
        let source = ExploreSimilarity.Candidate(text: sourceText, channel: Int64.min, isVideo: false)
        return ExploreSimilarity.rankedIndices(source: source, candidates: matches.map { candidates[$0.index] }).map { matches[$0] }
    }

    static func upserting(_ reference: ExplorationReference, into references: [ExplorationReference]) -> [ExplorationReference] {
        return [reference] + references.filter { $0.key != reference.key }
    }

    static func containsPublicSource(_ text: String, username: String, messageId: Int32) -> Bool {
        return text.components(separatedBy: .whitespacesAndNewlines).contains { word in
            guard let url = URLComponents(string: word), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  ["t.me", "telegram.me"].contains(url.host?.lowercased() ?? "") else { return false }
            let parts = url.path.split(separator: "/")
            return parts.count == 2 && parts[0].lowercased() == username.lowercased() && Int32(parts[1]) == messageId
        }
    }

    static func contributionText(channel: String, link: String, quote: String?, comment: String) -> String {
        var parts = [String]()
        if !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(comment.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let quote, !quote.isEmpty { parts.append("“\(quote)”") }
        parts.append("From \(channel)\n\(link)")
        return parts.joined(separator: "\n\n")
    }
}
