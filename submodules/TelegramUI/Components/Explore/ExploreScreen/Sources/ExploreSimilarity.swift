import Foundation

// A lightweight, on-device ranking for the viewer. It uses only information that is
// already in the feed; it does not infer the contents of an uncaptioned video.
enum ExploreSimilarity {
    struct Candidate {
        let text: String
        let channel: Int64
        let isVideo: Bool
    }

    private static let stopWords: Set<String> = [
        "about", "after", "also", "and", "are", "for", "from", "have", "has", "into", "just", "more", "not", "our", "out", "the", "their", "this", "that", "there", "they", "was", "were", "with", "you", "your",
        "как", "для", "или", "это", "что", "все", "они", "его", "она", "так", "уже", "этот", "эта", "при",
        "این", "برای", "های", "یک", "است", "هایش", "بود", "شده", "کرد", "که", "هایى"
    ]

    private static func tokens(_ text: String) -> Set<String> {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let separators = CharacterSet.letters.union(.decimalDigits).inverted
        return Set(normalized.components(separatedBy: separators).filter { $0.count >= 3 && !self.stopWords.contains($0) })
    }

    static func sharedTerms(_ lhs: String, _ rhs: String) -> [String] {
        return self.tokens(lhs).intersection(self.tokens(rhs)).sorted()
    }

    static func rankedIndices(source: Candidate, candidates: [Candidate], precedingChannels: [Int64]? = nil) -> [Int] {
        let sourceTokens = self.tokens(source.text)
        let scored = candidates.enumerated().map { index, candidate -> (index: Int, score: Int) in
            let shared = sourceTokens.intersection(self.tokens(candidate.text)).count
            // Shared topics dominate; prefer a different channel when relevance is close.
            // Video breaks ties when the opened post is itself a video.
            let score = min(shared, 3) * 10 + (candidate.channel != source.channel ? 2 : 0) + (source.isVideo && candidate.isVideo ? 1 : 0)
            return (index, score)
        }
        var remaining = scored.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
        }
        var recentChannels = precedingChannels ?? [source.channel]
        var result: [Int] = []
        while !remaining.isEmpty {
            var next = 0
            if recentChannels.count >= 2, recentChannels[recentChannels.count - 1] == recentChannels[recentChannels.count - 2] {
                let lastChannel = recentChannels[recentChannels.count - 1]
                if let different = remaining.firstIndex(where: { candidates[$0.index].channel != lastChannel }) {
                    next = different
                }
            }
            let item = remaining.remove(at: next)
            result.append(item.index)
            recentChannels.append(candidates[item.index].channel)
        }
        return result
    }
}
