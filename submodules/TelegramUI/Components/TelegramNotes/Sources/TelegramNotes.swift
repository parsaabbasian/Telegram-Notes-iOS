import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData

public struct TelegramNote: Equatable {
    public let peerId: EnginePeer.Id
    public let storyId: Int32
    public let text: String
    public let timestamp: Int32
    public let expirationTimestamp: Int32
    public var isSpoiler: Bool = false
    public var isRevealed: Bool = false
    public var poll: TelegramNotePoll? = nil
    public var audience: TelegramNoteAudience = .contacts
    public var reaction: String? = nil

    public func fractionLeft(now: Int32) -> CGFloat {
        return TelegramNoteTimer.fractionLeft(timestamp: self.timestamp, expiration: self.expirationTimestamp, now: now)
    }
}

public extension TelegramNoteAudience {
    var title: String {
        switch self {
        case .contacts:
            return TelegramNotesStrings.string("NotesAudienceContacts")
        case .closeFriends:
            return TelegramNotesStrings.string("NotesAudienceCloseFriends")
        case let .folder(_, title):
            return title
        }
    }
}

public final class TelegramNotesStore {
    public enum PublishState: Equatable {
        case idle
        case publishing
        case failed
        case unavailable
    }

    private static var stores: [EnginePeer.Id: TelegramNotesStore] = [:]

    public static func shared(context: AccountContext) -> TelegramNotesStore {
        assert(Thread.isMainThread)
        if let current = self.stores[context.account.peerId], current.context === context {
            return current
        }
        let store = TelegramNotesStore(context: context)
        self.stores[context.account.peerId] = store
        return store
    }

    private let context: AccountContext

    private var subscriptionsDisposable: Disposable?
    private var peerContexts: [EnginePeer.Id: (context: PeerExpiringStoryListContext, disposable: Disposable)] = [:]
    private var rawNotes: [EnginePeer.Id: TelegramNote] = [:]
    private var demoNote: TelegramNote?
    private var demoNoteSerial: Int32 = -100
    // The concept prototype keeps Notes on the device, so it needs neither Premium nor a server.
    public static let isDemoMode = true

    // Fictional sample contacts for the concept demo. They exist only in memory on this device.
    private struct DemoContact {
        let id: Int64
        let firstName: String
        let note: String
        let period: Int32
        let elapsed: Int32
        var isSpoiler: Bool = false
        var poll: TelegramNotePoll? = nil
        var audience: TelegramNoteAudience = .contacts
    }

    private static let demoStart = Int32(Date().timeIntervalSince1970)

    private static let demoContacts: [DemoContact] = [
        DemoContact(id: 9000000001, firstName: "Mia", note: "Lunch? 🍜", period: 1 * 60 * 60, elapsed: 20 * 60, audience: .closeFriends),
        DemoContact(id: 9000000002, firstName: "Leo", note: "Coding 💻", period: 24 * 60 * 60, elapsed: 16 * 60 * 60),
        DemoContact(id: 9000000003, firstName: "Sara", note: "Won! 🎉", period: 8 * 60 * 60, elapsed: 3 * 60 * 60, isSpoiler: true),
        DemoContact(id: 9000000004, firstName: "Noah", note: "🍕 or 💪?", period: 72 * 60 * 60, elapsed: 60 * 60 * 60, poll: TelegramNotePoll(options: ["Pizza 🍕", "Gym 💪"], votes: [14, 9]))
    ]

    private static func demoPeerId(_ id: Int64) -> EnginePeer.Id {
        return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id))
    }

    // Emoji avatars in the style of Telegram's emoji profile photos, so no real person's picture is used.
    private static let demoAvatarStyles: [Int64: (emoji: String, top: UInt32, bottom: UInt32)] = [
        0: ("🙋🏻", 0xB8F2E6, 0x52D1B8),
        9000000001: ("👩🏻‍🎨", 0xFFD1E8, 0xF59AC6),
        9000000002: ("👨🏽‍💻", 0xBDE3FF, 0x6FB1F7),
        9000000003: ("👩🏼‍✈️", 0xFFE6B8, 0xFDB777),
        9000000004: ("🧑🏾‍🚀", 0xD4CCFF, 0x9C8CF2)
    ]
    private static var demoAvatarCache: [Int64: UIImage] = [:]

    public static func demoAvatarImage(peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> UIImage? {
        guard self.isDemoMode else {
            return nil
        }
        let id = peerId == accountPeerId ? 0 : peerId.id._internalGetInt64Value()
        if let cached = self.demoAvatarCache[id] {
            return cached
        }
        guard let style = self.demoAvatarStyles[id] else {
            return nil
        }
        // A portrait in Documents/demo-avatars/<name>.png or .jpg replaces the emoji avatar without a rebuild.
        if let name = self.demoContacts.first(where: { $0.id == id })?.firstName.lowercased() {
            let directory = NSHomeDirectory() + "/Documents/demo-avatars/"
            for pathExtension in ["png", "jpg", "jpeg"] {
                if let portrait = UIImage(contentsOfFile: directory + name + "." + pathExtension), portrait.size.width > 0.0, portrait.size.height > 0.0 {
                    let side: CGFloat = 180.0
                    let scale = max(side / portrait.size.width, side / portrait.size.height)
                    let drawSize = CGSize(width: portrait.size.width * scale, height: portrait.size.height * scale)
                    let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
                        portrait.draw(in: CGRect(x: (side - drawSize.width) * 0.5, y: (side - drawSize.height) * 0.5, width: drawSize.width, height: drawSize.height))
                    }
                    self.demoAvatarCache[id] = image
                    return image
                }
            }
        }
        let side: CGFloat = 120.0
        let color: (UInt32) -> CGColor = { value in
            return UIColor(red: CGFloat((value >> 16) & 0xff) / 255.0, green: CGFloat((value >> 8) & 0xff) / 255.0, blue: CGFloat(value & 0xff) / 255.0, alpha: 1.0).cgColor
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { rendererContext in
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(style.top), color(style.bottom)] as CFArray, locations: [0.0, 1.0]) {
                rendererContext.cgContext.drawLinearGradient(gradient, start: CGPoint(), end: CGPoint(x: 0.0, y: side), options: [])
            }
            let emoji = NSAttributedString(string: style.emoji, attributes: [.font: UIFont.systemFont(ofSize: 76.0)])
            let emojiSize = emoji.size()
            emoji.draw(at: CGPoint(x: (side - emojiSize.width) * 0.5, y: (side - emojiSize.height) * 0.5 + 2.0))
        }
        self.demoAvatarCache[id] = image
        return image
    }

    public static var demoContactPeers: [EnginePeer] {
        return self.demoContacts.map { contact in
            return EnginePeer(TelegramUser(id: self.demoPeerId(contact.id), accessHash: nil, firstName: contact.firstName, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil, linkedCommunityId: nil))
        }
    }
    private var expiryTimer: SwiftSignalKit.Timer?
    private let publishDisposable = MetaDisposable()
    private var seenBubbleStoryIds = Set<Int32>()

    public private(set) var notes: [EnginePeer.Id: TelegramNote] = [:]
    private let notesPromise = ValuePromise<[EnginePeer.Id: TelegramNote]>([:], ignoreRepeated: true)
    public var notesSignal: Signal<[EnginePeer.Id: TelegramNote], NoError> {
        return self.notesPromise.get()
    }

    // Moves on once a minute, so a countdown ring keeps up while nothing else changes.
    private var minutesElapsed: Int32 = 0
    private let minuteTickPromise = ValuePromise<Int32>(0, ignoreRepeated: true)
    public var minuteTickSignal: Signal<Int32, NoError> {
        return self.minuteTickPromise.get()
    }

    public private(set) var publishState: PublishState = .idle
    private let publishStatePromise = ValuePromise<PublishState>(.idle, ignoreRepeated: true)
    public var publishStateSignal: Signal<PublishState, NoError> {
        return self.publishStatePromise.get()
    }

    // Set by the chat list, which owns the presentation context for the composer.
    public var openComposer: (() -> Void)?
    public var openNoteCard: ((EnginePeer) -> Void)?
    // The account's bubble in the row, which a shared Note flies to.
    public weak var accountBubbleView: UIView?

    public var accountNote: TelegramNote? {
        return self.notes[self.context.account.peerId]
    }

    private init(context: AccountContext) {
        self.context = context

        let accountPeerId = context.account.peerId
        self.updatePeers([accountPeerId])

        self.subscriptionsDisposable = (context.engine.messages.storySubscriptions(isHidden: false)
        |> deliverOnMainQueue).start(next: { [weak self] subscriptions in
            guard let self else {
                return
            }
            var peerIds: [EnginePeer.Id] = [accountPeerId]
            for item in subscriptions.items {
                // Notes come from contacts only.
                if case .user = item.peer, !peerIds.contains(item.peer.id) {
                    peerIds.append(item.peer.id)
                }
            }
            self.updatePeers(peerIds)
        })

        self.expiryTimer = SwiftSignalKit.Timer(timeout: 60.0, repeat: true, completion: { [weak self] in
            guard let self else {
                return
            }
            self.recompute()
            self.minutesElapsed += 1
            self.minuteTickPromise.set(self.minutesElapsed)
        }, queue: .mainQueue())
        self.expiryTimer?.start()
    }

    deinit {
        self.subscriptionsDisposable?.dispose()
        self.expiryTimer?.invalidate()
        self.publishDisposable.dispose()
        for (_, value) in self.peerContexts {
            value.disposable.dispose()
        }
    }

    private func updatePeers(_ peerIds: [EnginePeer.Id]) {
        let peerIdSet = Set(peerIds)
        for (peerId, value) in self.peerContexts where !peerIdSet.contains(peerId) {
            value.disposable.dispose()
            self.peerContexts.removeValue(forKey: peerId)
            self.rawNotes.removeValue(forKey: peerId)
        }
        for peerId in peerIds where self.peerContexts[peerId] == nil {
            let listContext = PeerExpiringStoryListContext(account: self.context.account, peerId: peerId)
            let disposable = (listContext.state
            |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let self else {
                    return
                }
                var latest: TelegramNote?
                for item in state.items {
                    guard case let .item(story) = item, !story.isExpired, let text = TelegramNoteCaption.noteText(caption: story.text) else {
                        continue
                    }
                    if latest == nil || story.timestamp > latest!.timestamp {
                        latest = TelegramNote(peerId: peerId, storyId: story.id, text: text, timestamp: story.timestamp, expirationTimestamp: story.expirationTimestamp)
                    }
                }
                self.rawNotes[peerId] = latest
                self.recompute()
            })
            self.peerContexts[peerId] = (listContext, disposable)
        }
        self.recompute()
    }

    private func recompute() {
        let now = Int32(Date().timeIntervalSince1970)
        var notes = self.rawNotes.filter { $0.value.expirationTimestamp > now }
        if let demoNote = self.demoNote {
            notes[demoNote.peerId] = demoNote
        }
        if TelegramNotesStore.isDemoMode {
            let start = TelegramNotesStore.demoStart
            for (index, contact) in TelegramNotesStore.demoContacts.enumerated() {
                let peerId = TelegramNotesStore.demoPeerId(contact.id)
                let timestamp = start - contact.elapsed
                var note = TelegramNote(peerId: peerId, storyId: Int32(-2 - index), text: contact.note, timestamp: timestamp, expirationTimestamp: timestamp + contact.period)
                note.isSpoiler = contact.isSpoiler
                note.poll = contact.poll
                note.audience = contact.audience
                notes[peerId] = note
            }
        }
        for (peerId, note) in notes {
            var updated = note
            updated.isRevealed = self.revealedNoteIds.contains(note.storyId)
            updated.reaction = self.reactions[note.storyId]
            if let index = self.pollChoices[note.storyId], let poll = note.poll {
                updated.poll = poll.voted(index: index)
            }
            notes[peerId] = updated
        }
        notes = notes.filter { $0.value.expirationTimestamp > now }
        self.notes = notes
        self.notesPromise.set(self.notes)
    }

    private func setPublishState(_ state: PublishState) {
        self.publishState = state
        self.publishStatePromise.set(state)
    }

    // True only the first time a bubble for this Note is shown, which drives the one-time pop haptic.
    public func markBubbleSeen(storyId: Int32) -> Bool {
        return self.seenBubbleStoryIds.insert(storyId).inserted
    }

    // The countdown, reveal, vote and reaction state of Notes on this device.
    private var revealedNoteIds = Set<Int32>()
    private var reactions: [Int32: String] = [:]
    private var pollChoices: [Int32: Int] = [:]

    public func reveal(note: TelegramNote) {
        if self.revealedNoteIds.insert(note.storyId).inserted {
            self.recompute()
        }
    }

    public func setReaction(_ reaction: String?, note: TelegramNote) {
        self.reactions[note.storyId] = reaction
        self.recompute()
    }

    public func vote(note: TelegramNote, index: Int) {
        guard self.pollChoices[note.storyId] == nil else {
            return
        }
        self.pollChoices[note.storyId] = index
        self.recompute()
    }

    public var supportsNoteOptions: Bool {
        return TelegramNotesStore.isDemoMode
    }

    // Contacts, Close Friends and the account's own chat folders. The prototype adds samples when it has no folders.
    public func audienceOptions() -> Signal<[TelegramNoteAudience], NoError> {
        return self.context.engine.peers.currentChatListFilters()
        |> take(1)
        |> map { filters -> [TelegramNoteAudience] in
            var folders: [TelegramNoteAudience] = []
            for filter in filters {
                if case let .filter(id, title, _, _) = filter {
                    folders.append(.folder(id: id, title: title.text))
                }
            }
            if folders.isEmpty && TelegramNotesStore.isDemoMode {
                folders = [.folder(id: -1, title: TelegramNotesStrings.string("NotesAudienceSampleFamily")), .folder(id: -2, title: TelegramNotesStrings.string("NotesAudienceSampleWork"))]
            }
            return [.contacts, .closeFriends] + folders
        }
    }

    // The prototype's Note lands once its flight to the avatar is over.
    public func landDemoNote(text: String, options: TelegramNoteOptions) {
        let now = Int32(Date().timeIntervalSince1970)
        self.demoNoteSerial -= 1
        var note = TelegramNote(peerId: self.context.account.peerId, storyId: self.demoNoteSerial, text: text, timestamp: now, expirationTimestamp: now + options.period)
        note.isSpoiler = options.isSpoiler
        note.poll = options.poll
        note.audience = options.audience
        self.demoNote = note
        self.recompute()
    }

    public func publish(text: String, theme: PresentationTheme, completion: @escaping (Bool) -> Void) {
        guard let text = TelegramNoteCaption.validated(text), self.publishState != .publishing else {
            completion(false)
            return
        }
        if TelegramNotesStore.isDemoMode {
            // Prototype: the Note stays on this device. Nothing is uploaded and contacts see nothing.
            completion(true)
            return
        }
        guard let data = TelegramNoteRenderer.render(text: text, theme: theme).jpegData(compressionQuality: 0.9) else {
            completion(false)
            return
        }
        self.setPublishState(.publishing)

        let accountPeerId = self.context.account.peerId
        let previous = self.notes[accountPeerId]
        let engine = self.context.engine
        let caption = TelegramNoteCaption.caption(text: text)

        // A Note cannot go out when the account may not post a Story right now; say so instead of spinning.
        self.publishDisposable.set((engine.messages.checkStoriesUploadAvailability(target: .myStories)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] availability in
            guard let self else {
                return
            }
            guard case .available = availability else {
                self.setPublishState(.unavailable)
                completion(false)
                return
            }

            let upload = engine.messages.uploadStory(
                target: .myStories,
                media: .image(dimensions: PixelDimensions(width: Int32(TelegramNoteCaption.imageSize.width), height: Int32(TelegramNoteCaption.imageSize.height)), data: data, stickers: []),
                mediaAreas: [],
                text: caption,
                entities: [],
                pin: false,
                privacy: EngineStoryPrivacy(base: .contacts, additionallyIncludePeers: []),
                isForwardingDisabled: false,
                period: Int(TelegramNoteCaption.period),
                randomId: Int64.random(in: Int64.min ... Int64.max),
                forwardInfo: nil,
                folders: [],
                music: nil
            )

            // The manager reports (stableId, storyId) the moment the server accepts the Story. The list refresh
            // can lag by a minute, so the Note is shown from this event. Subscribed first so it cannot be missed.
            let events = Promise<(Int32, Int32)?>()
            events.set(engine.messages.allStoriesUploadEvents() |> map(Optional.init))

            self.publishDisposable.set((upload
            |> take(1)
            |> mapToSignal { stableId -> Signal<Int32?, NoError> in
                return events.get()
                |> filter { $0?.0 == stableId }
                |> take(1)
                |> map { $0?.1 }
                |> timeout(90.0, queue: .mainQueue(), alternate: .single(nil))
                |> afterNext { storyId in
                    if storyId == nil {
                        engine.messages.cancelStoryUpload(stableId: stableId)
                    }
                }
            }
            |> deliverOnMainQueue).start(next: { [weak self] storyId in
                guard let self else {
                    return
                }
                if let storyId {
                    let now = Int32(Date().timeIntervalSince1970)
                    self.rawNotes[accountPeerId] = TelegramNote(peerId: accountPeerId, storyId: storyId, text: text, timestamp: now, expirationTimestamp: now + TelegramNoteCaption.period)
                    self.recompute()
                    if let previous {
                        let _ = engine.messages.deleteStories(peerId: accountPeerId, ids: [previous.storyId]).start()
                    }
                    self.setPublishState(.idle)
                    completion(true)
                } else {
                    self.setPublishState(.failed)
                    completion(false)
                }
            }))
        }))
    }

    public func deleteAccountNote() {
        if self.demoNote != nil {
            self.demoNote = nil
            self.recompute()
            return
        }
        let accountPeerId = self.context.account.peerId
        guard let note = self.notes[accountPeerId] else {
            return
        }
        self.rawNotes.removeValue(forKey: accountPeerId)
        self.recompute()
        let _ = self.context.engine.messages.deleteStories(peerId: accountPeerId, ids: [note.storyId]).start()
    }
}
