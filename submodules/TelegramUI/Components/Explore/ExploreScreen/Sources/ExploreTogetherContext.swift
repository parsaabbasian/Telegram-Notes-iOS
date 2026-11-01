import Foundation
import TelegramCore
import AccountContext
import SwiftSignalKit

final class ExploreTogetherStore {
    private let key: String
    private let promise = ValuePromise<[ExplorationReference]>([], ignoreRepeated: true)
    private(set) var references: [ExplorationReference]
    var signal: Signal<[ExplorationReference], NoError> { self.promise.get() }

    init(accountId: Int64) {
        self.key = ExplorationReference.storageKey(accountId: accountId)
        self.references = UserDefaults.standard.data(forKey: self.key).flatMap { try? JSONDecoder().decode([ExplorationReference].self, from: $0) } ?? []
        self.promise.set(self.references)
    }

    func save(_ reference: ExplorationReference) {
        self.references = TogetherRelevance.upserting(reference, into: self.references)
        self.persist()
    }

    func remove(_ reference: ExplorationReference) {
        self.references.removeAll { $0.key == reference.key }
        self.persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(self.references) { UserDefaults.standard.set(data, forKey: self.key) }
        self.promise.set(self.references)
    }
}

final class ExploreTogetherContext {
    struct State: Equatable {
        var messages: [EngineMessage] = []
        var pins: [EngineMessage] = []
        var peer: EnginePeer?
        var title: String
        var isLoading = false
        var isClosed = false
        var unavailable = false
        var moreMessages = false
        var morePins = false
    }
    let reference: ExplorationReference
    private let context: AccountContext
    private let promise: ValuePromise<State>
    private(set) var state: State
    var signal: Signal<State, NoError> { self.promise.get() }
    private let requests = MetaDisposable()
    private let updates = MetaDisposable()
    private let messageUpdates = MetaDisposable()
    private let peerUpdates = MetaDisposable()
    private let deletions = MetaDisposable()
    private var refreshTimer: SwiftSignalKit.Timer?
    private var messageState: SearchMessagesState?
    private var pinState: SearchMessagesState?
    private var active = false
    private var cachedMessageIds = Set<EngineMessage.Id>()
    private var missingTopic = false
    private var lastThread: MessageHistoryThreadData?

    init(context: AccountContext, reference: ExplorationReference) {
        self.context = context
        self.reference = reference
        self.state = State(title: reference.title)
        self.promise = ValuePromise(self.state)
    }
    deinit { self.stop() }

    func start() {
        guard !self.active else { return }
        self.active = true
        self.state.messages = []
        self.messageState = nil
        self.pinState = nil
        self.state.pins = []
        self.cachedMessageIds.removeAll()
        let peerId = EnginePeer.Id(self.reference.groupId)
        self.peerUpdates.set((self.context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else { return }
            self.state.peer = peer
            if case let .channel(channel) = peer {
                self.state.unavailable = self.missingTopic || channel.participationStatus != .member || !channel.flags.contains(.isForum)
            } else { self.state.unavailable = true }
            self.emit()
        }))
        self.updates.set((self.context.engine.messages.peerThreads(peerId: peerId, isMonoforum: false) |> deliverOnMainQueue).start(next: { [weak self] threads, loading in
            guard let self else { return }
            if let thread = threads.first(where: { $0.id == self.reference.topicId })?.data, thread != self.lastThread {
                self.missingTopic = false
                let hadThread = self.lastThread != nil
                self.lastThread = thread
                self.state.title = thread.info.title
                self.state.isClosed = thread.isClosed
                self.emit()
                if hadThread { self.refresh() }
            } else if !loading && self.lastThread != nil && !threads.contains(where: { $0.id == self.reference.topicId }) {
                self.missingTopic = true
                self.state.unavailable = true
                self.emit()
            }
        }))
        self.deletions.set((self.context.account.stateManager.deletedMessages |> deliverOnMainQueue).start(next: { [weak self] deleted in
            guard let self else { return }
            let removed = Set(deleted.compactMap { item -> EngineMessage.Id? in if case let .messageId(id) = item { return id }; return nil })
            self.state.messages.removeAll { removed.contains($0.id) }
            self.state.pins.removeAll { removed.contains($0.id) }
            self.emit()
        }))
        self.refreshTimer = SwiftSignalKit.Timer(timeout: 30.0, repeat: true, completion: { [weak self] in self?.refresh() }, queue: .mainQueue())
        self.refreshTimer?.start()
        self.refresh()
    }

    func stop() {
        self.active = false
        self.refreshTimer?.invalidate()
        self.refreshTimer = nil
        self.deletions.set(nil)
        self.requests.set(nil)
        self.updates.set(nil)
        self.messageUpdates.set(nil)
        self.peerUpdates.set(nil)
        self.state.isLoading = false
    }

    func refresh() {
        guard self.active, !self.state.isLoading else { return }
        self.load(pinsOnly: false, append: false)
    }
    func loadMore(pins: Bool) {
        guard self.active, !self.state.isLoading else { return }
        self.load(pinsOnly: pins, append: true)
    }
    private func load(pinsOnly: Bool, append: Bool) {
        self.state.isLoading = true
        self.emit()
        let location: (Bool) -> SearchMessagesLocation = { pins in
            .peer(peerId: EnginePeer.Id(self.reference.groupId), fromId: nil, tags: pins ? .pinned : nil, reactions: nil, threadId: self.reference.topicId, minDate: nil, maxDate: nil)
        }
        let messages = self.context.engine.messages.searchMessages(location: location(false), query: "", state: append && !pinsOnly ? self.messageState : nil, limit: 50)
        let pins = self.context.engine.messages.searchMessages(location: location(true), query: "", state: append && pinsOnly ? self.pinState : nil, limit: 50)
        self.requests.set((combineLatest(messages, pins) |> deliverOnMainQueue).start(next: { [weak self] messageResult, pinResult in
            guard let self else { return }
            let merge: ([EngineMessage], [EngineMessage]) -> [EngineMessage] = { old, new in
                var ids = Set<EngineMessage.Id>()
                return (old + new).filter { ids.insert($0.id).inserted }.sorted { $0.timestamp > $1.timestamp }
            }
            if !append || !pinsOnly {
                self.state.messages = merge(messageResult.0.messages.map(EngineMessage.init), self.state.messages)
                if append || self.messageState == nil {
                    self.messageState = messageResult.1
                    self.state.moreMessages = !messageResult.0.completed
                }
            }
            if !append || pinsOnly {
                let latest = pinResult.0.messages.map(EngineMessage.init)
                if pinResult.0.completed {
                    self.state.pins = latest
                    self.pinState = pinResult.1
                    self.state.morePins = false
                } else {
                    let oldest = latest.map { $0.id.id }.min()
                    let older = append ? self.state.pins : self.state.pins.filter { old in oldest.map { old.id.id < $0 } ?? false }
                    self.state.pins = merge(latest, older)
                    if append || self.pinState == nil {
                        self.pinState = pinResult.1
                        self.state.morePins = true
                    }
                }
            }
            self.state.isLoading = false
            self.emit()
            // Subscribe to the displayed messages so edits and deletions update the cards.
            let ids = Set((self.state.messages + self.state.pins).map(\.id))
            self.messageUpdates.set((self.context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Messages(ids: ids)) |> deliverOnMainQueue).start(next: { [weak self] current in
                guard let self else { return }
                // An absent record counts as a deletion only after Postbox supplied it once.
                let deleted = self.cachedMessageIds.intersection(ids).subtracting(current.keys)
                self.cachedMessageIds.formUnion(current.keys)
                self.state.messages = self.state.messages.filter { !deleted.contains($0.id) }.map { current[$0.id] ?? $0 }
                self.state.pins = self.state.pins.filter { !deleted.contains($0.id) }.map { current[$0.id] ?? $0 }.filter { $0.tags.contains(.pinned) }
                self.emit()
            }))
        }))
    }
    private func emit() { self.promise.set(self.state) }
}
