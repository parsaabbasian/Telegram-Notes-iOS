import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

struct ExplorePost: Equatable {
    enum Kind: Equatable {
        case photo(TelegramMediaImage)
        case video(TelegramMediaFile, duration: Double?)
        case text
    }

    let message: EngineMessage
    let peer: EnginePeer
    let kind: Kind
    let albumCount: Int

    var id: EngineMessage.Id {
        return self.message.id
    }

    var viewCount: Int? {
        for attribute in self.message.attributes {
            if let attribute = attribute as? ViewCountMessageAttribute {
                return attribute.count
            }
        }
        return nil
    }

    static func ==(lhs: ExplorePost, rhs: ExplorePost) -> Bool {
        return lhs.id == rhs.id && lhs.albumCount == rhs.albumCount && lhs.message.stableVersion == rhs.message.stableVersion
    }

    // Include text and link posts alongside photos and non-round videos.
    static func make(message: EngineMessage, albumCount: Int) -> ExplorePost? {
        guard let peer = message.enginePeers[message.id.peerId], case let .channel(channel) = peer, case .broadcast = channel.info else {
            return nil
        }
        // Explore only surfaces public channels. Leave spoilers in Telegram's native viewer
        // until this feed can render their concealment and reveal interaction.
        let isPublic = !(channel.username ?? "").isEmpty || channel.usernames.contains(where: { $0.flags.contains(.isActive) && !$0.username.isEmpty })
        guard isPublic, !message.attributes.contains(where: { attribute in
            if attribute is MediaSpoilerMessageAttribute { return true }
            if let entities = attribute as? TextEntitiesMessageAttribute {
                return entities.entities.contains(where: { if case .Spoiler = $0.type { return true }; return false })
            }
            return false
        }) else {
            return nil
        }
        for media in message.engineMedia {
            switch media {
            case let .image(image):
                return ExplorePost(message: message, peer: peer, kind: .photo(image), albumCount: albumCount)
            case let .file(file):
                if file.isVideo && !file.isInstantVideo {
                    var duration: Double?
                    for attribute in file.attributes {
                        if case let .Video(value, _, _, _, _, _) = attribute {
                            duration = value
                        }
                    }
                    return ExplorePost(message: message, peer: peer, kind: .video(file, duration: duration), albumCount: albumCount)
                }
            default:
                break
            }
        }
        // Do not turn unsupported or restricted media into a misleading text-only card.
        let hasOnlyTextOrLink = message.engineMedia.allSatisfy { media in
            if case .webpage = media { return true }
            return false
        }
        if hasOnlyTextOrLink && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ExplorePost(message: message, peer: peer, kind: .text, albumCount: 1)
        }
        return nil
    }
}

enum ExploreFeedKind: Int {
    case channels = 0
    case discover = 1
}

final class ExploreFeedContext {
    struct State: Equatable {
        var posts: [ExplorePost] = []
        var isLoading: Bool = false
        var isFullyLoaded: Bool = false
        var didLoadOnce: Bool = false
    }

    private static let globalPageLimit: Int32 = 40
    private static let maxRequestsPerLoad = 3
    private static let minNewTilesPerLoad = 12
    private static let discoverChannelsPerPage = 6
    private static let discoverPostsPerChannel: Int32 = 10
    private static let maxRecommendationSeeds = 5

    private let context: AccountContext
    let kind: ExploreFeedKind

    private(set) var state = State()
    private let statePromise = ValuePromise<State>(State(), ignoreRepeated: true)
    var stateSignal: Signal<State, NoError> {
        return self.statePromise.get()
    }

    private let loadDisposable = MetaDisposable()
    private var requestToken = 0
    private var seenIds = Set<EngineMessage.Id>()
    private var seenAlbums = Set<String>()

    private var searchState: SearchMessagesState?
    private var discoverCandidates: [EnginePeer.Id]?
    private var discoverIndex = 0

    // Joined channels seen in Your Channels; they seed Discover's recommendations.
    var seedChannelIds: () -> [EnginePeer.Id] = { [] }

    init(context: AccountContext, kind: ExploreFeedKind) {
        self.context = context
        self.kind = kind
    }

    deinit {
        self.loadDisposable.dispose()
    }

    private func setState(_ f: (inout State) -> Void) {
        f(&self.state)
        self.statePromise.set(self.state)
    }

    func refresh() {
        self.requestToken += 1
        self.loadDisposable.set(nil)
        self.seenIds.removeAll()
        self.seenAlbums.removeAll()
        self.searchState = nil
        self.discoverCandidates = nil
        self.discoverIndex = 0
        self.setState { $0 = State() }
        self.loadMore()
    }

    func loadMore() {
        if self.state.isLoading || self.state.isFullyLoaded {
            return
        }
        self.setState { $0.isLoading = true }
        let token = self.requestToken
        switch self.kind {
        case .channels:
            self.loadChannelsPage(attempt: 0, addedCount: 0, token: token)
        case .discover:
            self.loadDiscoverPage(token: token)
        }
    }

    // Collapses albums to their first unseen post and drops posts already shown in this feed.
    private func accept(messages: [EngineMessage], requireJoined: Bool?) -> [ExplorePost] {
        var albumCounts: [String: Int] = [:]
        for message in messages {
            if let groupingKey = message.groupingKey {
                albumCounts["\(message.id.peerId.toInt64()):\(groupingKey)", default: 0] += 1
            }
        }
        var result: [ExplorePost] = []
        for message in messages {
            if self.seenIds.contains(message.id) {
                continue
            }
            var albumKey: String?
            if let groupingKey = message.groupingKey {
                let key = "\(message.id.peerId.toInt64()):\(groupingKey)"
                if self.seenAlbums.contains(key) {
                    continue
                }
                albumKey = key
            }
            guard let post = ExplorePost.make(message: message, albumCount: albumKey.flatMap { albumCounts[$0] } ?? 1) else {
                continue
            }
            if let requireJoined, case let .channel(channel) = post.peer {
                let isJoined: Bool
                if case .member = channel.participationStatus {
                    isJoined = true
                } else {
                    isJoined = false
                }
                if isJoined != requireJoined {
                    continue
                }
            }
            self.seenIds.insert(message.id)
            if let albumKey {
                self.seenAlbums.insert(albumKey)
            }
            result.append(post)
        }
        return result
    }

    private func finishLoad(token: Int, posts: [ExplorePost], isFullyLoaded: Bool) {
        guard token == self.requestToken else {
            return
        }
        self.setState { state in
            state.posts.append(contentsOf: posts)
            state.isLoading = false
            state.isFullyLoaded = isFullyLoaded
            state.didLoadOnce = true
        }
    }

    // Your Channels: global media search over broadcasts, up to 3 requests until at least 12 new tiles or an empty page.
    private func loadChannelsPage(attempt: Int, addedCount: Int, token: Int) {
        let location = SearchMessagesLocation.general(scope: .channels, groupId: nil, tags: nil, minDate: nil, maxDate: nil, folderId: nil, communityId: nil)
        self.loadDisposable.set((self.context.engine.messages.searchMessages(location: location, query: "", state: self.searchState, limit: ExploreFeedContext.globalPageLimit)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] result, searchState in
            guard let self, token == self.requestToken else {
                return
            }
            self.searchState = searchState
            let messages = result.messages.map(EngineMessage.init).sorted(by: { $0.timestamp > $1.timestamp })
            let posts = self.accept(messages: messages, requireJoined: true)
            let isFullyLoaded = result.messages.isEmpty || result.completed
            let totalAdded = addedCount + posts.count

            if !isFullyLoaded && totalAdded < ExploreFeedContext.minNewTilesPerLoad && attempt + 1 < ExploreFeedContext.maxRequestsPerLoad {
                self.setState { $0.posts.append(contentsOf: posts) }
                self.loadChannelsPage(attempt: attempt + 1, addedCount: totalAdded, token: token)
            } else {
                self.finishLoad(token: token, posts: posts, isFullyLoaded: isFullyLoaded)
            }
        }))
    }

    private func recommendations(peerId: EnginePeer.Id?) -> Signal<[EnginePeer.Id], NoError> {
        let engine = self.context.engine
        // Fetch first (it completes without values), then read the stored list once.
        let requestSignal = engine.peers.requestRecommendedChannels(peerId: peerId)
        let request = Signal<RecommendedChannels?, NoError> { subscriber in
            return requestSignal.start(completed: {
                subscriber.putCompletion()
            })
        }
        return (request |> then(engine.peers.recommendedChannels(peerId: peerId) |> take(1)))
        |> map { recommended -> [EnginePeer.Id] in
            return recommended?.channels.map { $0.peer.id } ?? []
        }
        |> timeout(15.0, queue: .mainQueue(), alternate: .single([]))
    }

    // Discover: recommendations from joined channels plus Telegram's general list, then each page loads the
    // latest posts of the next 6 channels. Joined channels are left out.
    private func loadDiscoverPage(token: Int) {
        guard let candidates = self.discoverCandidates else {
            let seeds = Array(self.seedChannelIds().prefix(ExploreFeedContext.maxRecommendationSeeds))
            let signals = ([nil] + seeds.map(Optional.init)).map { self.recommendations(peerId: $0) }
            self.loadDisposable.set((combineLatest(signals)
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] lists in
                guard let self, token == self.requestToken else {
                    return
                }
                // Seeded recommendations first, then the general list; each channel once.
                var result: [EnginePeer.Id] = []
                for list in lists.dropFirst() + lists.prefix(1) {
                    for peerId in list where !result.contains(peerId) {
                        result.append(peerId)
                    }
                }
                self.discoverCandidates = result
                self.loadDiscoverPage(token: token)
            }))
            return
        }

        let page = Array(candidates.dropFirst(self.discoverIndex).prefix(ExploreFeedContext.discoverChannelsPerPage))
        if page.isEmpty {
            self.finishLoad(token: token, posts: [], isFullyLoaded: true)
            return
        }
        self.discoverIndex += page.count

        let signals = page.map { peerId -> Signal<[EngineMessage], NoError> in
            let location = SearchMessagesLocation.peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil)
            return self.context.engine.messages.searchMessages(location: location, query: "", state: nil, limit: ExploreFeedContext.discoverPostsPerChannel)
            |> take(1)
            |> map { result, _ -> [EngineMessage] in
                return result.messages.map(EngineMessage.init).sorted(by: { $0.timestamp > $1.timestamp })
            }
            |> timeout(15.0, queue: .mainQueue(), alternate: .single([]))
        }
        self.loadDisposable.set((combineLatest(signals)
        |> deliverOnMainQueue).start(next: { [weak self] lists in
            guard let self, token == self.requestToken else {
                return
            }
            // Interleave channels so one channel never fills a whole block.
            var interleaved: [EngineMessage] = []
            let maxCount = lists.map(\.count).max() ?? 0
            for index in 0 ..< maxCount {
                for list in lists where index < list.count {
                    interleaved.append(list[index])
                }
            }
            let posts = self.accept(messages: interleaved, requireJoined: false)
            let isFullyLoaded = self.discoverIndex >= candidates.count
            if posts.isEmpty && !isFullyLoaded {
                self.loadDiscoverPage(token: token)
            } else {
                self.finishLoad(token: token, posts: posts, isFullyLoaded: isFullyLoaded)
            }
        }))
    }
}
