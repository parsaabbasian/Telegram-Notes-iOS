import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramNotes

// A photo or video from the day a memory comes from.
public final class TelegramMemoryItem: Equatable {
    public enum Content {
        case photo(EngineMessage, TelegramMediaImage)
        case video(EngineMessage, TelegramMediaFile)
        // Demo mode draws its own pictures, because the sample contacts have no chats.
        case demo(UIImage)
    }

    public let id: String
    public let content: Content
    public let timestamp: Int32

    public init(id: String, content: Content, timestamp: Int32) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }

    public var isVideo: Bool {
        if case .video = self.content {
            return true
        }
        return false
    }

    public static func ==(lhs: TelegramMemoryItem, rhs: TelegramMemoryItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// Everything one person and you shared on this day in one earlier year.
public final class TelegramMemory: Equatable {
    public let peer: EnginePeer
    public let yearsAgo: Int
    public let items: [TelegramMemoryItem]

    public init(peer: EnginePeer, yearsAgo: Int, items: [TelegramMemoryItem]) {
        self.peer = peer
        self.yearsAgo = yearsAgo
        self.items = items
    }

    public var id: String {
        return "\(self.peer.id.toInt64())-\(self.yearsAgo)"
    }

    public var peerName: String {
        return self.peer.compactDisplayTitle
    }

    public var title: String {
        return self.yearsAgo == 1 ? TelegramMemoriesStrings.string("MemoriesYearAgo") : TelegramMemoriesStrings.format("MemoriesYearsAgo", self.yearsAgo)
    }

    public var shortTitle: String {
        return self.yearsAgo == 1 ? TelegramMemoriesStrings.string("MemoriesYearAgoShort") : TelegramMemoriesStrings.format("MemoriesYearsAgoShort", self.yearsAgo)
    }

    public var countText: String {
        let videos = self.items.filter(\.isVideo).count
        let photos = self.items.count - videos
        if videos == 0 {
            return photos == 1 ? TelegramMemoriesStrings.string("MemoriesPhoto") : TelegramMemoriesStrings.format("MemoriesPhotos", photos)
        } else if photos == 0 {
            return videos == 1 ? TelegramMemoriesStrings.string("MemoriesVideo") : TelegramMemoriesStrings.format("MemoriesVideos", videos)
        } else {
            return TelegramMemoriesStrings.format("MemoriesMoments", self.items.count)
        }
    }

    public var subtitle: String {
        return TelegramMemoriesStrings.format("MemoriesWith", self.peerName) + " · " + self.countText
    }

    public static func ==(lhs: TelegramMemory, rhs: TelegramMemory) -> Bool {
        return lhs.id == rhs.id && lhs.items == rhs.items
    }
}

// Finds today's memories in the account's private chats. The search runs on the device through Telegram's
// existing message search, and nothing new is stored on a server.
public final class TelegramMemoriesStore {
    private static var stores: [EnginePeer.Id: TelegramMemoriesStore] = [:]

    public static func shared(context: AccountContext) -> TelegramMemoriesStore {
        if let current = self.stores[context.account.peerId] {
            return current
        }
        let store = TelegramMemoriesStore(context: context)
        self.stores[context.account.peerId] = store
        return store
    }

    private let context: AccountContext
    private let searchDisposable = MetaDisposable()
    private let sendDisposables = DisposableSet()

    private var allMemories: [TelegramMemory] = []
    private var searchedDayKey: String?
    // Hidden people and a day hidden on purpose are remembered. Demo mode forgets them at launch, like the sample Notes.
    private var hiddenPeerIds: Set<Int64>
    private var hiddenDayKey: String?

    private let memoriesPromise = ValuePromise<[TelegramMemory]>([], ignoreRepeated: true)
    public var memoriesSignal: Signal<[TelegramMemory], NoError> {
        return self.memoriesPromise.get()
    }
    public private(set) var memories: [TelegramMemory] = []

    private var hiddenPeersKey: String {
        return "TelegramMemories.hiddenPeers.\(self.context.account.peerId.toInt64())"
    }
    private var hiddenDayDefaultsKey: String {
        return "TelegramMemories.hiddenDay.\(self.context.account.peerId.toInt64())"
    }

    private init(context: AccountContext) {
        self.context = context
        if TelegramNotesStore.isDemoMode {
            self.hiddenPeerIds = []
            self.hiddenDayKey = nil
        } else {
            let defaults = UserDefaults.standard
            self.hiddenPeerIds = Set((defaults.array(forKey: "TelegramMemories.hiddenPeers.\(context.account.peerId.toInt64())") as? [NSNumber] ?? []).map(\.int64Value))
            self.hiddenDayKey = defaults.string(forKey: "TelegramMemories.hiddenDay.\(context.account.peerId.toInt64())")
        }
    }

    deinit {
        self.searchDisposable.dispose()
        self.sendDisposables.dispose()
    }

    // Looks for today's memories once a day. Calling it again on the same day does nothing.
    public func refresh() {
        let now = Date()
        let calendar = Calendar.current
        let dayKey = TelegramMemoryCalendar.dayKey(now: now, calendar: calendar)
        if dayKey == self.searchedDayKey {
            return
        }
        self.searchedDayKey = dayKey
        let windows = TelegramMemoryCalendar.windows(now: now, calendar: calendar)

        if TelegramNotesStore.isDemoMode {
            self.allMemories = TelegramMemoryDemo.memories(windows: windows)
            self.publish()
            return
        }

        // One search per year, one after another, so opening the app does not fire ten requests at once.
        let engine = self.context.engine
        var chained: Signal<[(TelegramMemoryWindow, [EngineMessage])], NoError> = .single([])
        for window in windows {
            chained = chained
            |> mapToSignal { found -> Signal<[(TelegramMemoryWindow, [EngineMessage])], NoError> in
                return engine.messages.searchMessages(location: .general(scope: .privateChats, groupId: nil, tags: .photoOrVideo, minDate: window.start, maxDate: window.end, folderId: nil, communityId: nil), query: "", state: nil)
                |> take(1)
                |> map { result, _ -> [(TelegramMemoryWindow, [EngineMessage])] in
                    return found + [(window, result.messages.map(EngineMessage.init))]
                }
            }
        }
        let accountPeerId = self.context.account.peerId
        self.searchDisposable.set((chained
        |> deliverOnMainQueue).startStrict(next: { [weak self] found in
            guard let self else {
                return
            }
            self.allMemories = TelegramMemoriesStore.memories(from: found, accountPeerId: accountPeerId)
            self.publish()
        }))
    }

    private static func memories(from found: [(TelegramMemoryWindow, [EngineMessage])], accountPeerId: EnginePeer.Id) -> [TelegramMemory] {
        var byKey: [String: TelegramMemory] = [:]
        var candidates: [TelegramMemoryCandidate] = []
        for (window, messages) in found {
            var itemsByPeer: [EnginePeer.Id: [TelegramMemoryItem]] = [:]
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for message in messages where window.contains(message.timestamp) {
                let peerId = message.id.peerId
                // People only: no Saved Messages, groups, channels, bots or secret chats.
                guard peerId != accountPeerId, peerId.namespace == Namespaces.Peer.CloudUser, let peer = message.peers[peerId].flatMap(EnginePeer.init) else {
                    continue
                }
                if case let .user(user) = peer, user.botInfo != nil {
                    continue
                }
                let item: TelegramMemoryItem?
                if let image = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage {
                    item = TelegramMemoryItem(id: "\(peerId.toInt64())-\(message.id.id)", content: .photo(message, image), timestamp: message.timestamp)
                } else if let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, file.isVideo, !file.isAnimated, !file.isInstantVideo {
                    item = TelegramMemoryItem(id: "\(peerId.toInt64())-\(message.id.id)", content: .video(message, file), timestamp: message.timestamp)
                } else {
                    item = nil
                }
                if let item {
                    itemsByPeer[peerId, default: []].append(item)
                    peers[peerId] = peer
                }
            }
            for (peerId, items) in itemsByPeer {
                guard let peer = peers[peerId] else {
                    continue
                }
                let sortedItems = items.sorted(by: { $0.timestamp < $1.timestamp })
                let memory = TelegramMemory(peer: peer, yearsAgo: window.yearsAgo, items: Array(sortedItems.prefix(TelegramMemoryRanking.maxItems)))
                byKey[memory.id] = memory
                candidates.append(TelegramMemoryCandidate(key: peerId.toInt64(), yearsAgo: window.yearsAgo, itemCount: items.count))
            }
        }
        return TelegramMemoryRanking.sorted(candidates).compactMap { byKey["\($0.key)-\($0.yearsAgo)"] }
    }

    private func publish() {
        let dayKey = TelegramMemoryCalendar.dayKey(now: Date(), calendar: Calendar.current)
        if self.hiddenDayKey == dayKey {
            self.memories = []
        } else {
            self.memories = self.allMemories.filter { !self.hiddenPeerIds.contains($0.peer.id.toInt64()) }
        }
        self.memoriesPromise.set(self.memories)
    }

    public func hideForToday() {
        self.hiddenDayKey = TelegramMemoryCalendar.dayKey(now: Date(), calendar: Calendar.current)
        if !TelegramNotesStore.isDemoMode {
            UserDefaults.standard.set(self.hiddenDayKey, forKey: self.hiddenDayDefaultsKey)
        }
        self.publish()
    }

    public func hideMemories(with peerId: EnginePeer.Id) {
        self.hiddenPeerIds.insert(peerId.toInt64())
        if !TelegramNotesStore.isDemoMode {
            UserDefaults.standard.set(self.hiddenPeerIds.map { NSNumber(value: $0) }, forKey: self.hiddenPeersKey)
        }
        self.publish()
    }

    // Sends the memory back to the person it is with, as an album with its day as the caption.
    public func send(_ memory: TelegramMemory, completion: @escaping (Bool) -> Void) {
        let caption = "📸 " + memory.title
        var messages: [EnqueueMessage] = []
        let groupingKey: Int64? = memory.items.count > 1 ? Int64.random(in: 1 ... Int64.max) : nil
        for item in memory.items {
            let mediaReference: AnyMediaReference
            switch item.content {
            case let .photo(message, image):
                mediaReference = .message(message: MessageReference(message._asMessage()), media: image)
            case let .video(message, file):
                mediaReference = .message(message: MessageReference(message._asMessage()), media: file)
            case .demo:
                continue
            }
            messages.append(.message(text: messages.isEmpty ? caption : "", attributes: [], inlineStickers: [:], mediaReference: mediaReference, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: []))
        }
        if messages.isEmpty {
            // A demo memory goes nowhere: its contact is fictional.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                completion(true)
            }
            return
        }
        self.sendDisposables.add((enqueueMessages(account: self.context.account, peerId: memory.peer.id, messages: messages)
        |> deliverOnMainQueue).startStrict(next: { ids in
            completion(ids.contains(where: { $0 != nil }))
        }))
    }
}
