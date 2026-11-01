import Foundation

func candidate(_ text: String, _ channel: Int64, _ video: Bool = true) -> ExploreSimilarity.Candidate {
    return ExploreSimilarity.Candidate(text: text, channel: channel, isVideo: video)
}
let source = candidate("فوتبال ایران جام جهانی", 1)
let options = [candidate("Unrelated news", 3), candidate("اخبار فوتبال ایران", 4), candidate("", 1), candidate("جام جهانی فوتبال", 5)]
precondition(ExploreSimilarity.rankedIndices(source: source, candidates: options) == [3, 1, 0, 2])
let emptySource = candidate("", 1)
precondition(ExploreSimilarity.rankedIndices(source: emptySource, candidates: [candidate("", 3), candidate("", 1), candidate("", 1)]) == [0, 1, 2])
let commonWords = candidate("the and for", 1)
precondition(ExploreSimilarity.rankedIndices(source: commonWords, candidates: [candidate("the and for", 1), candidate("", 2)]) == [1, 0])
let videoSource = candidate("space mission", 1)
precondition(ExploreSimilarity.rankedIndices(source: videoSource, candidates: [candidate("space mission", 2, false), candidate("space mission", 3, true), candidate("unrelated", 1)]) == [1, 0, 2])
let diversity = [candidate("space mission", 1), candidate("space mission", 1), candidate("space", 2), candidate("unrelated", 3)]
precondition(ExploreSimilarity.rankedIndices(source: videoSource, candidates: diversity) == [0, 2, 1, 3])
precondition(ExploreSimilarity.rankedIndices(source: videoSource, candidates: diversity, precedingChannels: [1, 1]) == [2, 0, 1, 3])
print("Explore similarity checks passed")

// Together excludes unrelated posts instead of disguising them as recommendations.
let together = TogetherRelevance.ranked(title: "Weekend hiking", publicSourceTexts: [], candidates: [candidate("hiking trails", 1), candidate("football results", 2), candidate("weekend hiking", 3)])
precondition(together.map(\.index) == [2, 0])
precondition(TogetherRelevance.ranked(title: "the and", publicSourceTexts: [], candidates: [candidate("the and", 1)]).isEmpty)
let persian = TogetherRelevance.ranked(title: "فوتبال ایران", publicSourceTexts: [], candidates: options)
precondition(!persian.isEmpty && persian.allSatisfy { !$0.terms.isEmpty })
let sameChannels = TogetherRelevance.ranked(title: "hiking", publicSourceTexts: [], candidates: [candidate("hiking", 1), candidate("hiking", 1), candidate("hiking", 1), candidate("hiking", 2)])
precondition(sameChannels.map(\.index) == [0, 1, 3, 2])
let reference = ExplorationReference(groupId: 10, topicId: 20, title: "Trip", groupTitle: "Friends")
let secondGroup = ExplorationReference(groupId: 11, topicId: 20, title: "Trip", groupTitle: "Other group")
precondition(TogetherRelevance.upserting(reference, into: [reference, secondGroup]).count == 2)
precondition(ExplorationReference.storageKey(accountId: 1) != ExplorationReference.storageKey(accountId: 2))
let restoredReference = try JSONDecoder().decode(ExplorationReference.self, from: JSONEncoder().encode(reference))
precondition(restoredReference == reference)
precondition(TogetherRelevance.containsPublicSource("https://t.me/Channel/123?t=40", username: "channel", messageId: 123))
precondition(!TogetherRelevance.containsPublicSource("https://t.me/channel/1234", username: "channel", messageId: 123))
precondition(!TogetherRelevance.containsPublicSource("https://t.me.evil.example/channel/123", username: "channel", messageId: 123))
let contribution = TogetherRelevance.contributionText(channel: "Nature", link: "https://t.me/nature/5?t=12", quote: "A route", comment: "Try this")
precondition(contribution == "Try this\n\n“A route”\n\nFrom Nature\nhttps://t.me/nature/5?t=12")
print("Together model, attribution and ranking checks passed")

precondition(TogetherRelevance.matchesSearch("CAFE hiking", text: "Hiking near the café"))
precondition(TogetherRelevance.matchesSearch("کیش", text: "سفر به كيش"))
precondition(TogetherRelevance.matchesSearch("", text: "anything"))
precondition(!TogetherRelevance.matchesSearch("hiking budget", text: "Hiking routes"))
print("Together local search checks passed")
