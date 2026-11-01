import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData

public final class ExploreScreen: ViewController {
    public var openDiscussion: ((EngineMessage.Id) -> Void)?
    public var openTogetherTopic: ((EnginePeer.Id, Int64, EngineMessage.Id?, String?) -> Void)?
    private let togetherStore: ExploreTogetherStore
    private let togetherView: ExploreTogetherListView
    private var togetherCoordinator: ExploreTogetherCoordinator!
    private var togetherSubscription: Disposable?
    private var togetherPreviews: [String: ExploreTogetherContext] = [:]
    private var togetherPreviewSubscriptions: [Disposable] = []
    private static let tabStorageKey = "tt-explore-tab"

    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private let feeds: [ExploreFeedContext]
    private var feedViews: [ExploreFeedView] = []
    private let editorialTitle = UILabel()
    private let editorialSubtitle = UILabel()
    private let segmentedControl: UISegmentedControl
    private var selectedIndex: Int
    private var validLayout: ContainerViewLayout?

    public init(context: AccountContext) {
        self.context = context
        self.togetherStore = ExploreTogetherStore(accountId: context.account.id.int64)
        self.togetherView = ExploreTogetherListView(context: context)
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        let channels = ExploreFeedContext(context: context, kind: .channels)
        let discover = ExploreFeedContext(context: context, kind: .discover)
        self.feeds = [channels, discover]
        discover.seedChannelIds = { [weak channels] in
            var result: [EnginePeer.Id] = []
            for post in channels?.state.posts ?? [] where !result.contains(post.peer.id) {
                result.append(post.peer.id)
            }
            return result
        }

        self.segmentedControl = UISegmentedControl(items: [ExploreStrings.string("ExploreTabChannels"), ExploreStrings.string("ExploreTabDiscover"), "Together"])
        let storedIndex = UserDefaults.standard.string(forKey: ExploreScreen.tabStorageKey).flatMap(Int.init) ?? 0
        self.selectedIndex = (0 ..< 3).contains(storedIndex) ? storedIndex : 0

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.togetherCoordinator = ExploreTogetherCoordinator(context: context, store: self.togetherStore)
        self.togetherCoordinator.host = self
        self.togetherCoordinator.openTopic = { [weak self] peerId, threadId, messageId, draft in self?.openTogetherTopic?(peerId, threadId, messageId, draft) }
        self.togetherCoordinator.publicPosts = { [weak self] in
            var ids = Set<EngineMessage.Id>()
            return self?.feeds.flatMap { $0.state.posts }.filter { ids.insert($0.id).inserted } ?? []
        }
        self.togetherCoordinator.openPost = { [weak self] post in
            guard let self else { return }
            self.openReel(feed: self.feeds[self.selectedIndex == 1 ? 1 : 0], post: post)
        }
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = ExploreStrings.string("ExploreTitle")
        self.tabBarItem.title = ExploreStrings.string("ExploreTitle")
        self.tabBarItem.image = exploreTabIcon(symbolName: "safari")
        self.tabBarItem.selectedImage = exploreTabIcon(symbolName: "safari.fill")

        let refreshItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(self.refreshPressed))
        refreshItem.accessibilityLabel = ExploreStrings.string("ExploreRefresh")
        self.navigationItem.rightBarButtonItem = refreshItem

        self.scrollToTop = { [weak self] in
            if self?.selectedIndex == 2 { self?.togetherView.table.setContentOffset(.zero, animated: !UIAccessibility.isReduceMotionEnabled) }
            else { self?.currentFeedView?.scrollToTop() }
        }

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self, presentationData.theme !== self.presentationData.theme else {
                return
            }
            self.presentationData = presentationData
            self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
            if self.isNodeLoaded {
                self.applyTheme()
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.togetherSubscription?.dispose()
        self.togetherPreviewSubscriptions.forEach { $0.dispose() }
    }

    private var currentFeedView: ExploreFeedView? {
        return self.feedViews.indices.contains(self.selectedIndex) ? self.feedViews[self.selectedIndex] : nil
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.view.clipsToBounds = true

        for feed in self.feeds {
            let feedView = ExploreFeedView(context: self.context, feed: feed, presentationData: self.presentationData)
            feedView.openPost = { [weak self, weak feed] post in
                guard let self, let feed else {
                    return
                }
                self.openReel(feed: feed, post: post)
            }
            feedView.openDiscover = { [weak self] in
                self?.select(index: ExploreFeedKind.discover.rawValue, animated: true)
            }
            self.displayNode.view.addSubview(feedView)
            self.feedViews.append(feedView)
        }

        self.displayNode.view.addSubview(self.togetherView)
        self.togetherView.refresh = { [weak self] in self?.togetherPreviews.values.forEach { $0.refresh() } }
        self.togetherSubscription = (self.togetherStore.signal |> deliverOnMainQueue).start(next: { [weak self] _ in self?.reloadTogether() })
        self.editorialTitle.text = self.selectedIndex == 2 ? "Explore together" : "Your next conversation"
        self.editorialTitle.font = UIFont.systemFont(ofSize: 27.0, weight: .bold)
        self.editorialTitle.adjustsFontSizeToFitWidth = true
        self.editorialTitle.minimumScaleFactor = 0.75
        self.editorialSubtitle.text = self.selectedIndex == 2 ? "Discover, discuss, decide—with your group." : "Discover a post. Bring it to a chat."
        self.editorialSubtitle.font = UIFont.systemFont(ofSize: 14.0)
        self.displayNode.view.addSubview(self.editorialTitle)
        self.displayNode.view.addSubview(self.editorialSubtitle)
        self.segmentedControl.selectedSegmentIndex = self.selectedIndex
        self.segmentedControl.addTarget(self, action: #selector(self.segmentChanged), for: .valueChanged)
        self.displayNode.view.addSubview(self.segmentedControl)

        self.applyTheme()
        self.displayNodeDidLoad()
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.blocksBackgroundColor
        self.editorialTitle.textColor = theme.list.itemPrimaryTextColor
        self.editorialSubtitle.textColor = theme.list.itemSecondaryTextColor
        self.togetherView.updateTheme()
        self.segmentedControl.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        for feedView in self.feedViews {
            feedView.update(presentationData: self.presentationData)
        }
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.currentFeedView?.activate()
        if self.selectedIndex == 2 { self.togetherPreviews.values.forEach { $0.start() } }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.togetherPreviews.values.forEach { $0.stop() }
    }

    private func reloadTogether() {
        self.togetherPreviewSubscriptions.forEach { $0.dispose() }
        self.togetherPreviewSubscriptions.removeAll()
        self.togetherPreviews.values.forEach { $0.stop() }
        self.togetherPreviews.removeAll()
        for reference in self.togetherStore.references {
            let preview = ExploreTogetherContext(context: self.context, reference: reference)
            self.togetherPreviews[reference.key] = preview
            self.togetherPreviewSubscriptions.append((preview.signal |> deliverOnMainQueue).start(next: { [weak self] _ in self?.renderTogether() }))
            if self.selectedIndex == 2 && self.view.window != nil { preview.start() }
        }
        self.renderTogether()
    }

    private func renderTogether() {
        var rows = [TogetherRow(title: "Start exploring together", detail: "Choose a group topic or create one. Friends can contribute from any Telegram app.", symbol: "plus.bubble", action: { [weak self] in self?.togetherCoordinator.choose() })]
        for reference in self.togetherStore.references {
            let state = self.togetherPreviews[reference.key]?.state
            let recent = state?.messages.first
            let detail = state?.unavailable == true ? "Topic unavailable · open to check access" : [reference.groupTitle, recent.map { ($0.author?.compactDisplayTitle ?? "") + ": " + ($0.text.isEmpty ? "Media or poll" : $0.text) } ?? "Open your shared exploration"].joined(separator: "\n")
            rows.append(TogetherRow(title: state?.title ?? reference.title, detail: detail, peer: state?.peer, action: { [weak self] in self?.togetherCoordinator.show(reference) }))
        }
        self.togetherView.rows = rows
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        self.layoutContent(transition: transition)
    }

    private func layoutContent(transition: ContainedViewLayoutTransition) {
        guard let layout = self.validLayout else {
            return
        }
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        let sideInset = max(16.0, layout.safeInsets.left)
        transition.updateFrame(view: self.editorialTitle, frame: CGRect(x: sideInset + 4.0, y: topInset + 10.0, width: layout.size.width - sideInset * 2.0 - 8.0, height: 34.0))
        transition.updateFrame(view: self.editorialSubtitle, frame: CGRect(x: sideInset + 4.0, y: topInset + 49.0, width: layout.size.width - sideInset * 2.0 - 8.0, height: 22.0))
        let segmentHeight: CGFloat = 36.0
        transition.updateFrame(view: self.segmentedControl, frame: CGRect(x: sideInset, y: topInset + 84.0, width: layout.size.width - sideInset * 2.0, height: segmentHeight))

        let feedTop = topInset + 84.0 + segmentHeight + 4.0
        let feedSize = CGSize(width: layout.size.width, height: layout.size.height - feedTop)
        self.togetherView.frame = CGRect(x: CGFloat(2 - self.selectedIndex) * layout.size.width, y: feedTop, width: feedSize.width, height: feedSize.height)
        self.togetherView.table.contentInset.bottom = layout.intrinsicInsets.bottom
        for (index, feedView) in self.feedViews.enumerated() {
            let offset = CGFloat(index - self.selectedIndex) * layout.size.width
            transition.updateFrame(view: feedView, frame: CGRect(origin: CGPoint(x: offset, y: feedTop), size: feedSize))
            feedView.update(bottomInset: layout.intrinsicInsets.bottom, sideInset: layout.safeInsets.left)
        }
    }

    @objc private func segmentChanged() {
        self.select(index: self.segmentedControl.selectedSegmentIndex, animated: true)
    }

    private func select(index: Int, animated: Bool) {
        if index == self.selectedIndex {
            return
        }
        self.selectedIndex = index
        self.segmentedControl.selectedSegmentIndex = index
        UserDefaults.standard.set("\(index)", forKey: ExploreScreen.tabStorageKey)
        UISelectionFeedbackGenerator().selectionChanged()
        let transition: ContainedViewLayoutTransition = animated && !UIAccessibility.isReduceMotionEnabled ? .animated(duration: 0.4, curve: .spring) : .immediate
        self.layoutContent(transition: transition)
        self.currentFeedView?.activate()
        self.editorialTitle.text = index == 2 ? "Explore together" : "Your next conversation"
        self.editorialSubtitle.text = index == 2 ? "Discover, discuss, decide—with your group." : "Discover a post. Bring it to a chat."
        self.togetherPreviews.values.forEach { if index == 2 { $0.start() } else { $0.stop() } }
    }

    @objc private func refreshPressed() {
        if self.selectedIndex == 2 { self.togetherPreviews.values.forEach { $0.refresh() } } else { self.currentFeedView?.refresh() }
    }

    private func openReel(feed: ExploreFeedContext, post: ExplorePost) {
        let otherPosts = self.feeds.filter { $0 !== feed }.flatMap { $0.state.posts }
        let controller = ExploreReelController(context: self.context, feed: feed, startPost: post, otherPosts: otherPosts)
        controller.openPost = { [weak self] post in
            self?.open(post: post)
        }
        controller.exploreTogether = { [weak self] post, timestamp, quote in self?.togetherCoordinator.choose(source: post, timestamp: timestamp, quote: quote) }
        controller.openDiscussion = { [weak self] post in
            self?.openDiscussion?(post.id)
        }
        // Pushed on the root navigation so it covers the tab bar and receives every touch.
        (self.navigationController as? NavigationController)?.pushViewController(controller)
    }

    private func open(post: ExplorePost) {
        guard let navigationController = self.navigationController as? NavigationController else {
            return
        }
        self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(
            navigationController: navigationController,
            context: self.context,
            chatLocation: .peer(post.peer),
            subject: .message(id: .id(post.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false),
            keepStack: .always,
            useExisting: false,
            purposefulAction: {},
            peekData: nil
        ))
    }
}

final class ExploreFeedView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private let context: AccountContext
    private let feed: ExploreFeedContext
    private var presentationData: PresentationData

    private let collectionView: UICollectionView
    private let refreshControl = UIRefreshControl()
    private let emptyView = ExploreEmptyView()
    private var posts: [ExplorePost] = []
    private var state = ExploreFeedContext.State()
    private var stateDisposable: Disposable?
    private var didActivate = false

    var openPost: ((ExplorePost) -> Void)?
    var openDiscover: (() -> Void)?

    init(context: AccountContext, feed: ExploreFeedContext, presentationData: PresentationData) {
        self.context = context
        self.feed = feed
        self.presentationData = presentationData
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: ExploreGridLayout())

        super.init(frame: .zero)

        self.collectionView.backgroundColor = .clear
        self.collectionView.alwaysBounceVertical = true
        self.collectionView.contentInsetAdjustmentBehavior = .never
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.register(ExploreTileCell.self, forCellWithReuseIdentifier: ExploreTileCell.reuseIdentifier)
        self.collectionView.register(ExploreSkeletonCell.self, forCellWithReuseIdentifier: ExploreSkeletonCell.reuseIdentifier)
        self.collectionView.refreshControl = self.refreshControl
        self.refreshControl.addTarget(self, action: #selector(self.refreshPulled), for: .valueChanged)
        self.addSubview(self.collectionView)

        self.emptyView.isHidden = true
        self.emptyView.action = { [weak self] in
            guard let self else {
                return
            }
            if self.feed.kind == .channels {
                self.openDiscover?()
            } else {
                self.refresh()
            }
        }
        self.addSubview(self.emptyView)

        self.stateDisposable = (feed.stateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.apply(state: state)
        })
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.stateDisposable?.dispose()
    }

    func activate() {
        if !self.didActivate {
            self.didActivate = true
            self.feed.loadMore()
        }
    }

    func refresh() {
        self.didActivate = true
        self.scrollToTop()
        self.feed.refresh()
    }

    func scrollToTop() {
        self.collectionView.setContentOffset(CGPoint(x: 0.0, y: -self.collectionView.contentInset.top), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func refreshPulled() {
        self.feed.refresh()
    }

    func update(presentationData: PresentationData) {
        self.presentationData = presentationData
        self.refreshControl.tintColor = presentationData.theme.list.itemSecondaryTextColor
        self.emptyView.update(theme: presentationData.theme)
        self.collectionView.reloadData()
    }

    func update(bottomInset: CGFloat, sideInset: CGFloat) {
        self.collectionView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: bottomInset, right: 0.0)
        self.collectionView.verticalScrollIndicatorInsets = self.collectionView.contentInset
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.collectionView.frame = self.bounds
        self.emptyView.frame = self.bounds.insetBy(dx: 32.0, dy: 0.0).offsetBy(dx: 0.0, dy: -40.0)
    }

    private var showsSkeleton: Bool {
        return self.posts.isEmpty && !self.state.didLoadOnce
    }

    private func apply(state: ExploreFeedContext.State) {
        let previousCount = self.posts.count
        self.state = state
        (self.collectionView.collectionViewLayout as? ExploreGridLayout)?.posts = state.posts
        if !state.isLoading {
            self.refreshControl.endRefreshing()
        }

        if state.posts.count > previousCount && previousCount > 0 && state.posts.prefix(previousCount) == self.posts[...] {
            self.posts = state.posts
            // Card positions remain stable when more results arrive.
            let firstChanged = (previousCount / ExploreGridLayout.blockSize) * ExploreGridLayout.blockSize
            let reloaded = (firstChanged ..< previousCount).map { IndexPath(item: $0, section: 0) }
            let inserted = (previousCount ..< state.posts.count).map { IndexPath(item: $0, section: 0) }
            self.collectionView.performBatchUpdates({
                self.collectionView.reloadItems(at: reloaded)
                self.collectionView.insertItems(at: inserted)
            })
        } else {
            self.posts = state.posts
            self.collectionView.reloadData()
        }

        let isEmpty = state.didLoadOnce && !state.isLoading && state.posts.isEmpty
        self.emptyView.isHidden = !isEmpty
        if isEmpty {
            switch self.feed.kind {
            case .channels:
                self.emptyView.configure(icon: "photo.on.rectangle.angled", title: ExploreStrings.string("ExploreEmptyChannelsTitle"), text: ExploreStrings.string("ExploreEmptyChannels"), action: ExploreStrings.string("ExploreOpenDiscover"))
            case .discover:
                self.emptyView.configure(icon: "sparkles", title: ExploreStrings.string("ExploreEmptyDiscoverTitle"), text: ExploreStrings.string("ExploreEmptyDiscover"), action: ExploreStrings.string("ExploreRefresh"))
            }
            self.emptyView.update(theme: self.presentationData.theme)
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // Two skeleton blocks while the first page loads.
        return self.showsSkeleton ? ExploreGridLayout.blockSize * 2 : self.posts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if self.showsSkeleton {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ExploreSkeletonCell.reuseIdentifier, for: indexPath)
            cell.backgroundColor = self.presentationData.theme.list.mediaPlaceholderColor
            cell.isAccessibilityElement = false
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ExploreTileCell.reuseIdentifier, for: indexPath) as! ExploreTileCell
        let isLarge = ExploreGridLayout.isLarge(index: indexPath.item, count: self.posts.count)
        cell.update(context: self.context, theme: self.presentationData.theme, post: self.posts[indexPath.item], isLarge: isLarge)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !self.showsSkeleton, indexPath.item < self.posts.count else {
            return
        }
        self.openPost?(self.posts[indexPath.item])
    }

    // Loads the next page well before the end: the preload margin is 3 screens.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let remaining = scrollView.contentSize.height - (scrollView.contentOffset.y + scrollView.bounds.height)
        if remaining < scrollView.bounds.height * 3.0 && self.state.didLoadOnce {
            self.feed.loadMore()
        }
    }
}

final class ExploreEmptyView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let button = UIButton(type: .system)

    var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.iconView.contentMode = .scaleAspectFit
        self.titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.accessibilityTraits = .header
        self.textLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.textLabel.textAlignment = .center
        self.textLabel.numberOfLines = 0
        self.button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [self.iconView, self.titleLabel, self.textLabel, self.button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10.0
        stack.setCustomSpacing(16.0, after: self.iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.iconView.heightAnchor.constraint(equalToConstant: 48.0),
            self.iconView.widthAnchor.constraint(equalToConstant: 64.0),
            self.button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0)
        ])
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func configure(icon: String, title: String, text: String, action: String) {
        self.iconView.image = UIImage(systemName: icon)
        self.titleLabel.text = title
        self.textLabel.text = text
        self.button.setTitle(action, for: .normal)
    }

    func update(theme: PresentationTheme) {
        self.iconView.tintColor = theme.list.itemSecondaryTextColor
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.textLabel.textColor = theme.list.itemSecondaryTextColor
        self.button.tintColor = theme.list.itemAccentColor
    }

    @objc private func buttonPressed() {
        self.action?()
    }
}

// The tab bar masks its icons with the image's bitmap, which a symbol image does not have until it is drawn,
// so the symbol is rasterized at the size of Telegram's own tab icons.
private func exploreTabIcon(symbolName: String) -> UIImage? {
    guard let symbol = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 23.0, weight: .medium)) else {
        return nil
    }
    let size = CGSize(width: 30.0, height: 30.0)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
        let symbolSize = symbol.size
        symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(x: (size.width - symbolSize.width) * 0.5, y: (size.height - symbolSize.height) * 0.5, width: symbolSize.width, height: symbolSize.height))
    }
    return image.withRenderingMode(.alwaysTemplate)
}
