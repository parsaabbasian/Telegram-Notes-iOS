import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import AvatarNode

struct TogetherRow {
    var title: String
    var detail: String
    var peer: EnginePeer?
    var symbol: String = "bubble.left.and.bubble.right"
    var action: (() -> Void)?
}

private final class TogetherCell: UITableViewCell {
    private let avatar = AvatarNode(font: UIFont.systemFont(ofSize: 18.0, weight: .semibold))
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        self.contentView.addSubview(self.avatar.view)
        self.textLabel?.font = .preferredFont(forTextStyle: .headline)
        self.textLabel?.numberOfLines = 2
        self.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        self.detailTextLabel?.numberOfLines = 3
        self.textLabel?.adjustsFontForContentSizeCategory = true
        self.detailTextLabel?.adjustsFontForContentSizeCategory = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ row: TogetherRow, context: AccountContext) {
        let theme = context.sharedContext.currentPresentationData.with { $0 }.theme
        self.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.textLabel?.textColor = theme.list.itemPrimaryTextColor
        self.detailTextLabel?.textColor = theme.list.itemSecondaryTextColor
        self.textLabel?.text = row.title
        self.detailTextLabel?.text = row.detail
        self.avatar.isHidden = row.peer == nil
        if let peer = row.peer { self.avatar.setPeer(context: context, theme: theme, peer: peer, displayDimensions: CGSize(width: 44.0, height: 44.0)) }
        self.imageView?.image = row.peer == nil ? UIImage(systemName: row.symbol) : nil
        self.imageView?.tintColor = theme.list.itemAccentColor
        self.accessoryType = row.action == nil ? .none : .disclosureIndicator
        self.selectionStyle = row.action == nil ? .none : .default
        self.accessibilityLabel = row.title + ", " + row.detail
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let rtl = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        self.avatar.frame = CGRect(x: rtl ? self.contentView.bounds.width - 60.0 : 16.0, y: 18.0, width: 44.0, height: 44.0)
        if !self.avatar.isHidden {
            let x: CGFloat = rtl ? 16.0 : 74.0
            let width = max(0.0, self.contentView.bounds.width - 90.0)
            let titleHeight = min(UIFont.preferredFont(forTextStyle: .headline).lineHeight * 2.0, self.textLabel?.sizeThatFits(CGSize(width: width, height: 100.0)).height ?? 24.0)
            self.textLabel?.frame = CGRect(x: x, y: 14.0, width: width, height: titleHeight)
            self.detailTextLabel?.frame = CGRect(x: x, y: 18.0 + titleHeight, width: width, height: max(0.0, self.contentView.bounds.height - titleHeight - 30.0))
        }
    }
}

final class ExploreTogetherListView: UIView, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    let table = UITableView(frame: .zero, style: .insetGrouped)
    var rows: [TogetherRow] = [] { didSet { self.table.reloadData() } }
    var refresh: (() -> Void)?
    private let refreshControl = UIRefreshControl()
    private var textSizeObserver: NSObjectProtocol?
    init(context: AccountContext) {
        self.context = context
        super.init(frame: .zero)
        self.table.dataSource = self
        self.table.delegate = self
        self.table.rowHeight = 124.0
        self.table.contentInsetAdjustmentBehavior = .never
        self.table.register(TogetherCell.self, forCellReuseIdentifier: "together")
        self.table.refreshControl = self.refreshControl
        self.refreshControl.addTarget(self, action: #selector(self.refreshPressed), for: .valueChanged)
        self.addSubview(self.table)
        self.updateTheme()
        self.textSizeObserver = NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateTheme() }
    }
    deinit { if let observer = self.textSizeObserver { NotificationCenter.default.removeObserver(observer) } }
    required init?(coder: NSCoder) { fatalError() }
    func updateTheme() {
        let theme = self.context.sharedContext.currentPresentationData.with { $0 }.theme
        self.table.backgroundColor = theme.list.blocksBackgroundColor
        self.table.rowHeight = max(124.0, UIFont.preferredFont(forTextStyle: .headline).lineHeight * 2.0 + UIFont.preferredFont(forTextStyle: .subheadline).lineHeight * 3.0 + 32.0)
        self.table.separatorColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.08)
        self.table.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.table.reloadData()
    }
    func endRefreshing() { self.refreshControl.endRefreshing() }
    @objc private func refreshPressed() { self.refresh?(); self.refreshControl.endRefreshing() }
    override func layoutSubviews() { super.layoutSubviews(); self.table.frame = self.bounds }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { self.rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "together", for: indexPath) as! TogetherCell
        cell.update(self.rows[indexPath.row], context: self.context)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.rows[indexPath.row].action?()
    }
}

// The coordinator owns only navigation and local references. Telegram's topic composer
// owns sends, draft persistence, resend, polls and pinning permissions.
final class ExploreTogetherCoordinator {
    let context: AccountContext
    let store: ExploreTogetherStore
    weak var host: ViewController?
    var openTopic: ((EnginePeer.Id, Int64, EngineMessage.Id?, String?) -> Void)?
    var publicPosts: (() -> [ExplorePost])?
    var openPost: ((ExplorePost) -> Void)?
    private let operation = MetaDisposable()
    private let selection = MetaDisposable()
    private var busy = false {
        didSet {
            self.busyIndicator?.removeFromSuperview()
            self.busyIndicator = nil
            if self.busy, let view = self.presenter?.view {
                let indicator = UIActivityIndicatorView(style: .large)
                indicator.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                indicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
                indicator.accessibilityLabel = "Preparing exploration"
                indicator.startAnimating()
                view.addSubview(indicator)
                self.busyIndicator = indicator
            }
        }
    }
    private var busyIndicator: UIActivityIndicatorView?

    init(context: AccountContext, store: ExploreTogetherStore) { self.context = context; self.store = store }
    deinit { self.operation.dispose(); self.selection.dispose(); self.busyIndicator?.removeFromSuperview() }
    var presenter: ViewController? { (self.host?.navigationController as? NavigationController)?.viewControllers.last as? ViewController ?? self.host }

    func alert(_ text: String) {
        let alert = UIAlertController(title: "Explore Together", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.presenter?.present(alert, animated: true)
    }
    func choose(source: ExplorePost? = nil, timestamp: Int? = nil, quote: String? = nil) {
        guard !self.busy else { return }
        let alert = UIAlertController(title: "Explore together", message: "Keep discoveries in a group topic. Friends can contribute using any Telegram app.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Use an existing topic", style: .default, handler: { [weak self] _ in self?.selectTopic(create: false, source: source, timestamp: timestamp, quote: quote) }))
        alert.addAction(UIAlertAction(title: "Create a new topic", style: .default, handler: { [weak self] _ in self?.selectTopic(create: true, source: source, timestamp: timestamp, quote: quote) }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.presenter?.present(alert, animated: true)
    }

    private func selectTopic(create: Bool, source: ExplorePost?, timestamp: Int?, quote: String?, retainedComment: String = "") {
        guard let navigation = self.host?.navigationController as? NavigationController else { return }
        let picker = self.context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: self.context, filter: [.onlyGroups, .onlyWriteable, .excludeSecretChats], hasFilters: false, hasChatListSelector: false, hasContactSelector: false, hasGlobalSearch: false, title: create ? "Choose a group with Topics" : "Choose a group topic", selectForumThreads: !create))
        picker.peerSelected = { [weak self, weak picker] peer, threadId in
            guard let self, !self.busy else { return }
            guard case let .channel(channel) = peer, channel.flags.contains(.isForum), channel.participationStatus == .member, channel.hasPermission(.sendText) else {
                self.alert("Choose a group you belong to with Topics enabled and permission to write. Together never enables Topics or joins a group for you.")
                return
            }
            if create {
                guard channel.hasPermission(.createTopics) else { self.alert("You don’t have permission to create a topic in this group. Choose an existing topic instead."); return }
                if navigation.viewControllers.last === picker { let _ = navigation.popViewController(animated: false) }
                self.confirm(peer: peer, reference: nil, source: source, timestamp: timestamp, quote: quote)
            } else if let threadId {
                self.busy = true
                self.selection.set((self.context.engine.peers.fetchForumChannelTopic(id: peer.id, threadId: threadId) |> deliverOnMainQueue).start(next: { [weak self, weak picker] result in
                    guard let self, case let .result(info) = result else { return }
                    self.busy = false
                    guard let info else { self.alert("This topic is unavailable. Choose another topic."); return }
                    if navigation.viewControllers.last === picker { let _ = navigation.popViewController(animated: false) }
                    let reference = ExplorationReference(groupId: peer.id.toInt64(), topicId: threadId, title: info.title, groupTitle: peer.compactDisplayTitle)
                    self.confirm(peer: peer, reference: reference, source: source, timestamp: timestamp, quote: quote, retainedComment: retainedComment)
                }))
            } else { self.alert("Select a topic inside this group.") }
        }
        navigation.pushViewController(picker)
    }

    private func confirm(peer: EnginePeer, reference: ExplorationReference?, source: ExplorePost?, timestamp: Int?, quote: String?, retainedComment: String = "") {
        let sourceDescription = source.map { "\nSource: \($0.peer.compactDisplayTitle)" } ?? ""
        let timestampDescription = timestamp.map { "\nVideo moment: \($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? ""
        let alert = UIAlertController(title: reference == nil ? "Create exploration" : "Explore in \(reference!.title)", message: "Group: \(peer.compactDisplayTitle)\(sourceDescription)\(timestampDescription)\n\n\(reference == nil ? "This creates a group topic after confirmation. " : "")Your contribution opens as a draft in the topic. Review it and tap Send there.", preferredStyle: .alert)
        if reference == nil { alert.addTextField { $0.placeholder = "What are you exploring together?"; $0.autocapitalizationType = .sentences } }
        if source != nil { alert.addTextField { $0.placeholder = "Why are you sharing this? (optional)"; $0.text = retainedComment } }
        alert.addAction(UIAlertAction(title: reference == nil ? "Create topic" : source == nil ? "Add to Together" : "Review in topic", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, !self.busy, let alert else { return }
            let title = reference?.title ?? alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty, title.count <= 128 else { self.alert("Use an exploration title between 1 and 128 characters."); return }
            let comment = source == nil ? "" : alert.textFields?.last?.text ?? ""
            self.prepare(peer: peer, reference: reference, title: title, source: source, timestamp: timestamp, quote: quote, comment: comment)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.presenter?.present(alert, animated: true)
    }

    private func prepare(peer: EnginePeer, reference: ExplorationReference?, title: String, source: ExplorePost?, timestamp: Int?, quote: String?, comment: String) {
        self.busy = true
        let proceed: (String?) -> Void = { [weak self] draft in
            guard let self else { return }
            if let reference {
                self.busy = false
                self.store.save(reference)
                if let draft { self.openTopic?(peer.id, reference.topicId, nil, draft) }
                else { self.show(reference) }
            } else {
                self.operation.set((self.context.engine.peers.createForumChannelTopic(id: peer.id, title: title, iconColor: 0x6fb9f0, iconFileId: nil) |> deliverOnMainQueue).start(next: { [weak self] threadId in
                    guard let self else { return }
                    self.busy = false
                    let reference = ExplorationReference(groupId: peer.id.toInt64(), topicId: threadId, title: title, groupTitle: peer.compactDisplayTitle)
                    self.store.save(reference)
                    if let draft { self.openTopic?(peer.id, threadId, nil, draft) }
                    else { self.show(reference) }
                }, error: { [weak self] _ in
                    self?.busy = false
                    self?.retry("Telegram did not confirm creation. Check the group for the topic before trying again; nothing was sent. Your contribution can be reviewed again.", action: { [weak self] in
                        self?.selectTopic(create: false, source: source, timestamp: timestamp, quote: quote, retainedComment: comment)
                    })
                }))
            }
        }
        // Recheck destination and source before any mutation, then export the actual server link.
        self.selection.set((self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peer.id)) |> deliverOnMainQueue).start(next: { [weak self] freshPeer in
            guard let self else { return }
            guard case let .channel(channel) = freshPeer, channel.participationStatus == .member, channel.flags.contains(.isForum), channel.hasPermission(.sendText), reference != nil || channel.hasPermission(.createTopics) else {
                self.busy = false; self.alert("Your access to this group has changed. Nothing was sent."); return
            }
            guard let source else { proceed(nil); return }
            guard !source.message._asMessage().isCopyProtected(), !source.peer.isCopyProtectionEnabled else { self.busy = false; self.alert("This channel restricts sharing."); return }
            let freshMessage: Signal<EngineMessage?, NoError> = self.context.engine.messages.getMessagesLoadIfNecessary([source.id], strategy: .cloud(skipLocal: true))
            |> filter { result in if case .result = result { return true }; return false }
            |> map { result -> EngineMessage? in if case let .result(messages) = result { return messages.first.map(EngineMessage.init) }; return nil }
            |> `catch` { _ -> Signal<EngineMessage?, NoError> in return .single(nil) }
            self.operation.set((combineLatest(self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: source.peer.id)), self.context.engine.messages.exportMessageLink(peerId: source.id.peerId, messageId: source.id), freshMessage) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] freshSource, link, freshMessage in
                guard let self else { return }
                guard let freshMessage, !freshMessage._asMessage().isCopyProtected(), let verifiedSource = ExplorePost.make(message: freshMessage, albumCount: source.albumCount), !verifiedSource.peer.isCopyProtectionEnabled, quote.map({ freshMessage.text.contains($0) }) ?? true, let freshSource, !freshSource.isCopyProtectionEnabled, let link, var components = URLComponents(string: link) else {
                    self.busy = false
                    self.retry("The source is unavailable or cannot be shared. Your comment is retained.", action: { [weak self] in self?.prepare(peer: peer, reference: reference, title: title, source: source, timestamp: timestamp, quote: quote, comment: comment) })
                    return
                }
                if let timestamp {
                    var items = components.queryItems ?? []
                    items.removeAll { $0.name == "t" }
                    items.append(URLQueryItem(name: "t", value: "\(max(0, timestamp))"))
                    components.queryItems = items
                }
                let draft = TogetherRelevance.contributionText(channel: verifiedSource.peer.compactDisplayTitle, link: components.string ?? link, quote: quote, comment: comment)
                // Deliver on the next turn before replacing the request disposable for creation.
                Queue.mainQueue().async { proceed(draft) }
            }))
        }))
    }
    private func retry(_ text: String, action: @escaping () -> Void) {
        let alert = UIAlertController(title: "Couldn’t continue", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default, handler: { _ in action() }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.presenter?.present(alert, animated: true)
    }
    func show(_ reference: ExplorationReference) {
        guard let navigation = self.host?.navigationController as? NavigationController else { return }
        navigation.pushViewController(ExploreTogetherDetailController(coordinator: self, reference: reference))
    }
    func forget(_ reference: ExplorationReference) {
        let alert = UIAlertController(title: "Remove from Together?", message: "This removes the shortcut on this device. The group, topic and messages stay in Telegram.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Remove shortcut", style: .destructive, handler: { [weak self] _ in self?.store.remove(reference) }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.presenter?.present(alert, animated: true)
    }
}

final class ExploreTogetherDetailController: ViewController, UISearchBarDelegate {
    private let coordinator: ExploreTogetherCoordinator
    private let reference: ExplorationReference
    private let topic: ExploreTogetherContext
    private let list: ExploreTogetherListView
    private let segments = UISegmentedControl(items: ["Discover", "Contributions", "Decisions & pins"])
    private let search = UISearchBar()
    private var subscription: Disposable?
    private var state: ExploreTogetherContext.State

    init(coordinator: ExploreTogetherCoordinator, reference: ExplorationReference) {
        self.coordinator = coordinator
        self.reference = reference
        self.topic = ExploreTogetherContext(context: coordinator.context, reference: reference)
        self.state = self.topic.state
        self.list = ExploreTogetherListView(context: coordinator.context)
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: coordinator.context.sharedContext.currentPresentationData.with { $0 }))
        self.title = reference.title
        self.segments.apportionsSegmentWidthsByContent = true
        self.segments.selectedSegmentIndex = 1
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Chat", style: .plain, target: self, action: #selector(self.openChat))
    }
    required init(coder: NSCoder) { fatalError() }
    deinit { self.subscription?.dispose() }
    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.coordinator.context.sharedContext.currentPresentationData.with { $0 }.theme.list.blocksBackgroundColor
        self.displayNode.view.addSubview(self.list)
        self.displayNode.view.addSubview(self.segments)
        self.search.searchBarStyle = .minimal
        self.search.placeholder = "Search loaded contributions and pins"
        self.search.delegate = self
        self.search.autocapitalizationType = .none
        self.search.accessibilityLabel = "Search this exploration"
        self.displayNode.view.addSubview(self.search)
        self.list.table.keyboardDismissMode = .onDrag
        self.segments.addTarget(self, action: #selector(self.rebuild), for: .valueChanged)
        self.list.refresh = { [weak self] in self?.topic.refresh() }
        self.subscription = (self.topic.signal |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            self.state = state
            self.title = state.title
            self.rebuild()
        })
        self.displayNodeDidLoad()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); self.list.updateTheme(); self.search.overrideUserInterfaceStyle = self.coordinator.context.sharedContext.currentPresentationData.with { $0 }.theme.overallDarkAppearance ? .dark : .light; self.topic.start() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); self.topic.stop() }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.segments.frame = CGRect(x: 16.0 + layout.safeInsets.left, y: top + 8.0, width: layout.size.width - 32.0 - layout.safeInsets.left - layout.safeInsets.right, height: 36.0)
        self.search.frame = CGRect(x: layout.safeInsets.left + 8.0, y: top + 48.0, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right - 16.0, height: 56.0)
        self.list.frame = CGRect(x: 0.0, y: top + 104.0, width: layout.size.width, height: max(0.0, layout.size.height - top - 104.0))
        self.list.table.contentInset.bottom = layout.intrinsicInsets.bottom
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { self.rebuild() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
    private func draftDecision() {
        guard !self.state.isClosed, !self.state.unavailable else { return }
        let alert = UIAlertController(title: "Draft a decision", message: "Topic: \(self.state.title)\nGroup: \(self.reference.groupTitle)\n\nReview this in the topic before sending. It is a proposal until your group agrees; pin it using Telegram’s native actions.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Proposed decision"; $0.autocapitalizationType = .sentences }
        alert.addTextField { $0.placeholder = "Next step or owner (optional)"; $0.autocapitalizationType = .sentences }
        alert.addAction(UIAlertAction(title: "Review in topic", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let next = alert?.textFields?.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let draft = "Proposed decision: \(self.state.title)\n\n\(text)" + (next.isEmpty ? "" : "\n\nNext step: \(next)")
            self.coordinator.openTopic?(EnginePeer.Id(self.reference.groupId), self.reference.topicId, nil, draft)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(alert, animated: true)
    }
    @objc private func openChat() { self.coordinator.openTopic?(EnginePeer.Id(self.reference.groupId), self.reference.topicId, nil, nil) }
    @objc private func rebuild() {
        var rows = [TogetherRow]()
        let query = self.search.text ?? ""
        self.search.placeholder = self.segments.selectedSegmentIndex == 0 ? "Filter loaded public discoveries" : "Search loaded contributions and pins"
        if self.state.unavailable {
            rows.append(TogetherRow(title: "Topic unavailable", detail: "Access may have changed. Open the topic in Telegram to check.", peer: self.state.peer))
        } else if self.state.isClosed {
            rows.append(TogetherRow(title: "This topic is closed", detail: "You can read its contributions. An authorized member must reopen it before new messages can be sent.", peer: self.state.peer))
        }
        if self.segments.selectedSegmentIndex == 0 {
            let posts = self.coordinator.publicPosts?() ?? []
            // Only public forwards/links deliberately contributed to this topic seed relevance.
            let chosen = posts.filter { post in self.state.messages.contains { message in
                if message.forwardInfo?.sourceMessageId == post.id { return true }
                guard case let .channel(channel) = post.peer, let username = channel.username, !username.isEmpty else { return false }
                return TogetherRelevance.containsPublicSource(message.text, username: username, messageId: post.id.id)
            } }
            let matches = TogetherRelevance.ranked(title: self.state.title, publicSourceTexts: chosen.map { $0.message.text }, candidates: posts.map { ExploreSimilarity.Candidate(text: $0.message.text, channel: $0.peer.id.toInt64(), isVideo: false) })
            rows.append(TogetherRow(title: "Discover for “\(self.state.title)”", detail: "Matches use your topic title and shared public sources. Private comments and browsing history aren’t used.", peer: self.state.peer, symbol: "sparkles"))
            var visibleMatches = 0
            for match in matches.prefix(40) {
                let post = posts[match.index]
                guard TogetherRelevance.matchesSearch(query, text: post.peer.compactDisplayTitle + " " + post.message.text) else { continue }
                visibleMatches += 1
                rows.append(TogetherRow(title: post.peer.compactDisplayTitle, detail: "Matches: \(match.terms.prefix(3).joined(separator: ", "))\n\(post.message.text)", peer: post.peer, action: { [weak self] in self?.coordinator.openPost?(post) }))
            }
            if !matches.isEmpty && visibleMatches == 0 { rows.append(TogetherRow(title: "No discoveries match this search", detail: "Try another word or clear the search to see relevant public posts.", symbol: "magnifyingglass")) }
            if matches.isEmpty { rows.append(TogetherRow(title: "No relevant posts yet", detail: "Browse Discover in Explore to load more public posts, then return here. You can also share a public source to this topic.", symbol: "magnifyingglass")) }
        } else {
            let pins = self.segments.selectedSegmentIndex == 2
            rows.append(TogetherRow(title: pins ? "Keep the outcome" : "\(self.state.title) · \(self.reference.groupTitle)", detail: pins ? "Open the topic to create a poll, write your decision, or pin a message. Telegram checks who can pin." : "Posts, moments and comments from your Telegram topic. Tap a contribution to reply in context.", peer: self.state.peer, action: { [weak self] in self?.openChat() }))
            if pins && !self.state.isClosed && !self.state.unavailable {
                rows.append(TogetherRow(title: "Draft a decision", detail: "Propose an outcome and a next step, then review in the topic.", symbol: "square.and.pencil", action: { [weak self] in self?.draftDecision() }))
            }
            let messages = (pins ? self.state.pins : self.state.messages).filter { TogetherRelevance.matchesSearch(query, text: ($0.author?.compactDisplayTitle ?? "") + " " + $0.text) }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && messages.isEmpty {
                rows.append(TogetherRow(title: "No matches in loaded messages", detail: "Try another word or load earlier messages below. Search stays on this device.", symbol: "magnifyingglass"))
            }
            for message in messages {
                let text = message.text.isEmpty ? (message.media.isEmpty ? "Topic activity" : "Media or poll · open in Telegram") : message.text
                rows.append(TogetherRow(title: message.author?.compactDisplayTitle ?? self.reference.groupTitle, detail: text, peer: message.author, action: { [weak self] in
                    guard let self else { return }
                    self.coordinator.openTopic?(EnginePeer.Id(self.reference.groupId), self.reference.topicId, message.id, nil)
                }))
            }
            let empty = pins ? self.state.pins.isEmpty : self.state.messages.isEmpty
            if empty { rows.append(TogetherRow(title: self.state.isLoading ? "Loading…" : pins ? "No pinned decisions yet" : "Start the exploration", detail: pins ? "Pin a useful outcome in the topic to keep it here." : "Add a public post using Explore with… or open the topic to contribute.", symbol: pins ? "pin" : "paperplane")) }
            if pins ? self.state.morePins : self.state.moreMessages { rows.append(TogetherRow(title: self.state.isLoading ? "Loading…" : "Load earlier messages", detail: "", symbol: "arrow.down", action: { [weak self] in self?.topic.loadMore(pins: pins) })) }
        }
        rows.append(TogetherRow(title: "Remove shortcut", detail: "Only removes this exploration from Together on this device.", symbol: "minus.circle", action: { [weak self] in guard let self else { return }; self.coordinator.forget(self.reference) }))
        self.list.rows = rows
        if !self.state.isLoading { self.list.endRefreshing() }
    }
}
