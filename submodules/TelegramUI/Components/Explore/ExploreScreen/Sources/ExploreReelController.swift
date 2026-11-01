import Foundation
import UIKit
import AVFoundation
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PhotoResources
import AvatarNode

// The full-screen vertical reel viewer: one post per screen, snap paging, only the active post plays.
final class ExploreReelController: ViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private static let nextPageDistance = 4
    private static let unmutedKey = "tt-explore-reels-unmuted"

    private let context: AccountContext
    private let feed: ExploreFeedContext
    private let relevanceSource: ExploreSimilarity.Candidate
    private var posts: [ExplorePost]
    private var activeIndex = 0
    private var isMuted = UserDefaults.standard.string(forKey: ExploreReelController.unmutedKey) != "1"
    private var feedDisposable: Disposable?
    private let shareDisposable = MetaDisposable()
    private let linkDisposable = MetaDisposable()

    private var collectionView: UICollectionView!
    private let togetherButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private var didAnimateIn = false

    var exploreTogether: ((ExplorePost, Int?, String?) -> Void)?
    var openPost: ((ExplorePost) -> Void)?
    var openDiscussion: ((ExplorePost) -> Void)?

    init(context: AccountContext, feed: ExploreFeedContext, startPost: ExplorePost, otherPosts: [ExplorePost]) {
        self.context = context
        self.feed = feed
        let source = Self.similarityCandidate(startPost)
        self.relevanceSource = source
        var known = Set([startPost.id])
        let remaining = (feed.state.posts + otherPosts).filter { known.insert($0.id).inserted }
        let order = ExploreSimilarity.rankedIndices(source: source, candidates: remaining.map(Self.similarityCandidate))
        self.posts = [startPost] + order.map { remaining[$0] }

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = .Hide
        // A plain push: a modal container would claim vertical pans for its own swipe-to-dismiss.
        self.navigationPresentation = .default

        // Rank each new batch against the opened post, but never move pages the
        // viewer already knows about while the user is swiping through them.
        self.feedDisposable = (feed.stateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self, self.isNodeLoaded else {
                return
            }
            let known = Set(self.posts.map(\.id))
            let added = state.posts.filter { !known.contains($0.id) }
            if !added.isEmpty {
                let start = self.posts.count
                let previousChannels = self.posts.suffix(2).map { $0.peer.id.toInt64() }
                let order = ExploreSimilarity.rankedIndices(source: self.relevanceSource, candidates: added.map(Self.similarityCandidate), precedingChannels: previousChannels)
                self.posts.append(contentsOf: order.map { added[$0] })
                self.collectionView.insertItems(at: (start ..< self.posts.count).map { IndexPath(item: $0, section: 0) })
                self.updateCounter()
            }
        })
    }

    private static func similarityCandidate(_ post: ExplorePost) -> ExploreSimilarity.Candidate {
        let isVideo: Bool
        if case .video = post.kind { isVideo = true } else { isVideo = false }
        return ExploreSimilarity.Candidate(text: post.message.text, channel: post.peer.id.toInt64(), isVideo: isVideo)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.feedDisposable?.dispose()
        self.shareDisposable.dispose()
        self.linkDisposable.dispose()
    }

    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(self.closePressed)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(self.previousPost)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(self.nextPost)),
            UIKeyCommand(input: "m", modifierFlags: [], action: #selector(self.toggleSound))
        ]
    }

    @objc private func previousPost() {
        self.moveToPost(index: self.activeIndex - 1)
    }

    @objc private func nextPost() {
        self.moveToPost(index: self.activeIndex + 1)
    }

    @objc private func toggleSound() {
        guard self.posts.indices.contains(self.activeIndex), case .video = self.posts[self.activeIndex].kind else { return }
        self.isMuted.toggle()
        UserDefaults.standard.set(self.isMuted ? "0" : "1", forKey: ExploreReelController.unmutedKey)
        for case let cell as ExploreReelCell in self.collectionView.visibleCells {
            cell.setMuted(self.isMuted)
        }
    }

    private func moveToPost(index: Int) {
        guard self.posts.indices.contains(index), self.collectionView.bounds.height > 0.0 else { return }
        self.collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
        self.setActive(index: index)
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.context.sharedContext.currentPresentationData.with { $0 }.theme.list.plainBackgroundColor
        let view = self.displayNode.view
        view.accessibilityViewIsModal = true
        view.accessibilityLabel = ExploreStrings.string("ExploreFeedTitle")

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0.0
        layout.minimumInteritemSpacing = 0.0
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.backgroundColor = self.displayNode.backgroundColor
        self.collectionView.isPagingEnabled = true
        // Vertical paging belongs to the reels, not to the navigation's drag-to-go-back or modal dismiss.
        self.collectionView.disablesInteractiveTransitionGestureRecognizer = true
        self.collectionView.disablesInteractiveModalDismiss = true
        view.disablesInteractiveTransitionGestureRecognizer = true
        view.disablesInteractiveModalDismiss = true
        self.collectionView.showsVerticalScrollIndicator = false
        self.collectionView.contentInsetAdjustmentBehavior = .never
        self.collectionView.decelerationRate = .fast
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.register(ExploreReelCell.self, forCellWithReuseIdentifier: ExploreReelCell.reuseIdentifier)
        view.addSubview(self.collectionView)

        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.0, weight: .semibold)), for: .normal)
        self.closeButton.tintColor = .white
        self.closeButton.accessibilityLabel = ExploreStrings.string("ExploreClose")
        self.closeButton.layer.shadowColor = UIColor.black.cgColor
        self.closeButton.layer.shadowOpacity = 0.4
        self.closeButton.layer.shadowRadius = 3.0
        self.closeButton.layer.shadowOffset = .zero
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        view.addSubview(self.closeButton)
        var togetherConfiguration = UIButton.Configuration.tinted()
        togetherConfiguration.title = "Together"
        togetherConfiguration.image = UIImage(systemName: "person.2", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold))
        togetherConfiguration.imagePadding = 7.0
        togetherConfiguration.cornerStyle = .capsule
        self.togetherButton.configuration = togetherConfiguration
        self.togetherButton.accessibilityLabel = "Explore with a group topic"
        self.togetherButton.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
        self.togetherButton.addTarget(self, action: #selector(self.togetherPressed), for: .touchUpInside)
        view.addSubview(self.togetherButton)

        self.counterLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15.0, weight: .semibold)
        self.counterLabel.textColor = .white
        self.counterLabel.textAlignment = .center
        self.counterLabel.layer.shadowColor = UIColor.black.cgColor
        self.counterLabel.layer.shadowOpacity = 0.4
        self.counterLabel.layer.shadowRadius = 3.0
        self.counterLabel.layer.shadowOffset = .zero
        view.addSubview(self.counterLabel)

        self.updateCounter()
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let size = layout.size
        let previousSize = self.collectionView.bounds.size
        self.collectionView.frame = CGRect(origin: .zero, size: size)
        if previousSize != size, let flowLayout = self.collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.itemSize = size
            flowLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            self.collectionView.contentOffset = CGPoint(x: 0.0, y: CGFloat(self.activeIndex) * size.height)
        }
        let topInset = max(layout.safeInsets.top, layout.statusBarHeight ?? 0.0, 20.0)
        let isRTL = self.view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let leftEdge = max(8.0, layout.safeInsets.left + 4.0)
        let rightEdge = max(8.0, layout.safeInsets.right + 4.0)
        self.closeButton.frame = CGRect(x: isRTL ? size.width - rightEdge - 44.0 : leftEdge, y: topInset + 4.0, width: 44.0, height: 44.0)
        var togetherConfiguration = self.togetherButton.configuration
        togetherConfiguration?.title = nil
        togetherConfiguration?.image = UIImage(systemName: "person.2.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold))
        togetherConfiguration?.baseForegroundColor = .white
        self.togetherButton.configuration = togetherConfiguration
        self.togetherButton.frame = CGRect(x: isRTL ? leftEdge : size.width - rightEdge - 44.0, y: topInset + 4.0, width: 44.0, height: 44.0)
        let counterLeft = isRTL ? self.togetherButton.frame.maxX : self.closeButton.frame.maxX
        let counterRight = isRTL ? self.closeButton.frame.minX : self.togetherButton.frame.minX
        self.counterLabel.frame = CGRect(x: counterLeft, y: topInset + 4.0, width: max(0.0, counterRight - counterLeft), height: 44.0)
        for case let cell as ExploreReelCell in self.collectionView.visibleCells {
            cell.update(safeInsets: UIEdgeInsets(top: topInset, left: layout.safeInsets.left, bottom: max(layout.safeInsets.bottom, 16.0), right: layout.safeInsets.right))
        }
        self.reelSafeInsets = UIEdgeInsets(top: topInset, left: layout.safeInsets.left, bottom: max(layout.safeInsets.bottom, 16.0), right: layout.safeInsets.right)
    }

    private var reelSafeInsets = UIEdgeInsets()

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !self.didAnimateIn {
            self.didAnimateIn = true
            // Use the navigation transition alone; a second whole-screen fade washes out the reader.
            self.setActive(index: 0)
        } else {
            self.setActive(index: self.activeIndex)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        for case let cell as ExploreReelCell in self.collectionView.visibleCells {
            cell.setActive(false)
        }
    }

    private func updateCounter() {
        let current = min(self.activeIndex + 1, self.posts.count)
        self.counterLabel.text = "\(current) / \(self.posts.count)"
        let theme = self.context.sharedContext.currentPresentationData.with { $0 }.theme
        let isText: Bool
        if self.posts.indices.contains(self.activeIndex), case .text = self.posts[self.activeIndex].kind { isText = true } else { isText = false }
        self.closeButton.tintColor = isText ? theme.list.itemPrimaryTextColor : .white
        self.closeButton.backgroundColor = (isText ? theme.list.itemPrimaryTextColor : UIColor.white).withAlphaComponent(0.07)
        self.closeButton.layer.cornerRadius = 22.0
        self.closeButton.layer.shadowOpacity = 0.0
        self.counterLabel.textColor = isText ? theme.list.itemSecondaryTextColor : UIColor.white.withAlphaComponent(0.65)
        if self.posts.indices.contains(self.activeIndex) {
            let post = self.posts[self.activeIndex]
            self.togetherButton.isHidden = post.peer.isCopyProtectionEnabled || post.message._asMessage().isCopyProtected()
            self.togetherButton.tintColor = isText ? theme.list.itemAccentColor : UIColor(rgb: 0x64baff)
        }
        self.counterLabel.accessibilityLabel = "Post \(current) of \(self.posts.count)"
    }

    private func setActive(index: Int) {
        guard index >= 0 && index < self.posts.count else {
            return
        }
        let changed = index != self.activeIndex
        self.activeIndex = index
        for case let cell as ExploreReelCell in self.collectionView.visibleCells {
            if let indexPath = self.collectionView.indexPath(for: cell) {
                cell.setActive(indexPath.item == index)
            }
        }
        if changed && !UIAccessibility.isReduceMotionEnabled {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
        self.updateCounter()
        if index >= self.posts.count - ExploreReelController.nextPageDistance {
            self.feed.loadMore()
        }
    }

    @objc private func togetherPressed() {
        guard self.posts.indices.contains(self.activeIndex) else { return }
        let post = self.posts[self.activeIndex]
        let cell = self.collectionView.cellForItem(at: IndexPath(item: self.activeIndex, section: 0)) as? ExploreReelCell
        cell?.pauseForTogether()
        self.exploreTogether?(post, cell?.currentVideoMoment, nil)
        // UIKit dialogs do not trigger viewDidAppear when cancelled; keep playback paused deliberately.
    }

    @objc private func closePressed() {
        self.close()
    }

    private func share(post: ExplorePost, quote: String? = nil, timestamp: Int? = nil) {
        // Grouped messages need all album members, which are not necessarily in the loaded page.
        guard post.message.groupingKey == nil, !post.message._asMessage().isCopyProtected(), !post.peer.isCopyProtectionEnabled else { return }
        self.shareDisposable.set((self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: post.peer.id))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self, let peer, !peer.isCopyProtectionEnabled, self.posts.indices.contains(self.activeIndex), self.posts[self.activeIndex].id == post.id else { return }
            let presentShare: (ShareControllerSubject) -> Void = { [weak self] subject in
                guard let self, self.view.window != nil, self.posts.indices.contains(self.activeIndex), self.posts[self.activeIndex].id == post.id else { return }
                for case let cell as ExploreReelCell in self.collectionView.visibleCells { cell.pauseForOverlay() }
                let controller = self.context.sharedContext.makeShareScreen(context: self.context, params: ShareControllerParams(subject: subject, dismissed: { [weak self] _ in
                    guard let self else { return }
                    for case let cell as ExploreReelCell in self.collectionView.visibleCells {
                        cell.resumeAfterOverlay()
                    }
                    self.setActive(index: self.activeIndex)
                }))
                self.present(controller, in: .window(.root))
            }
            if quote != nil || timestamp != nil {
                self.linkDisposable.set((self.context.engine.messages.exportMessageLink(peerId: post.id.peerId, messageId: post.id)
                |> deliverOnMainQueue).start(next: { link in
                    guard let link, var components = URLComponents(string: link) else {
                        // Forwarding preserves attribution when a public link cannot be exported.
                        presentShare(.messages([post.message._asMessage()]))
                        return
                    }
                    if let timestamp {
                        var items = components.queryItems ?? []
                        items.removeAll { $0.name == "t" }
                        items.append(URLQueryItem(name: "t", value: "\(timestamp)"))
                        components.queryItems = items
                    }
                    let url = components.string ?? link
                    if let quote { presentShare(.quote(text: quote, url: url)) }
                    else { presentShare(.url(url)) }
                }))
            } else {
                presentShare(.messages([post.message._asMessage()]))
            }
        }))
    }

    private func close() {
        for case let cell as ExploreReelCell in self.collectionView.visibleCells {
            cell.setActive(false)
        }
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        } else {
            self.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.posts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ExploreReelCell.reuseIdentifier, for: indexPath) as! ExploreReelCell
        let post = self.posts[indexPath.item]
        cell.configure(context: self.context, post: post, isMuted: self.isMuted)
        cell.update(safeInsets: self.reelSafeInsets)
        cell.toggleMute = { [weak self] in
            guard let self else {
                return
            }
            self.toggleSound()
        }
        cell.sharePost = { [weak self] in
            self?.share(post: post)
        }
        cell.exploreQuote = { [weak self] quote in self?.exploreTogether?(post, nil, quote) }
        cell.shareQuote = { [weak self] quote in self?.share(post: post, quote: quote) }
        cell.shareMoment = { [weak self] seconds in self?.share(post: post, timestamp: seconds) }
        cell.discussPost = { [weak self] in
            guard let self else { return }
            for case let visible as ExploreReelCell in self.collectionView.visibleCells { visible.setActive(false) }
            self.openDiscussion?(post)
        }
        cell.openInChannel = { [weak self] in
            guard let self else {
                return
            }
            // Remove the viewer before navigating to the source message.
            if let navigationController = self.navigationController as? NavigationController {
                let _ = navigationController.popViewController(animated: false)
            }
            self.openPost?(post)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ExploreReelCell)?.setActive(indexPath.item == self.activeIndex && self.didAnimateIn)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ExploreReelCell)?.setActive(false)
    }

    // A reel becomes active once at least 60% of it is on screen.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let height = scrollView.bounds.height
        // Layout passes also move the offset; only the user's own scrolling changes the active reel.
        guard height > 0.0, scrollView.isDragging || scrollView.isDecelerating else {
            return
        }
        let position = scrollView.contentOffset.y / height
        let index = Int(position.rounded())
        if abs(position - CGFloat(index)) <= 0.4 && index != self.activeIndex {
            self.setActive(index: index)
        }
    }
}

final class ExploreReelCell: UICollectionViewCell, UIGestureRecognizerDelegate, UITextViewDelegate {
    static let reuseIdentifier = "ExploreReelCell"

    private let imageNode = TransformImageNode()
    private let playerView = ExploreReelPlayerView()
    private let contextSurface = UIView()
    private let readingSurface = UIView()
    private let sourceAvatar = AvatarNode(font: UIFont.systemFont(ofSize: 16.0, weight: .semibold))
    private let sourceDate = UILabel()
    private let quoteHint = UILabel()
    private var isTextPost = false
    private let readingScrollView = UIScrollView()
    private let reelScrim: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [UIColor(white: 0.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.72).cgColor]
        return layer
    }()
    private let readingLabel = UITextView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let scrim = CAGradientLayer()
    private let titleLabel = UILabel()
    private let captionScrollView = UIScrollView()
    private let captionLabel = UILabel()
    private let captionToggle = UIButton(type: .system)
    private let viewsLabel = UILabel()
    private let viewsIcon = UIImageView(image: UIImage(systemName: "eye.fill"))
    private let muteButton = UIButton(type: .system)
    private let openButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let discussButton = UIButton(type: .system)
    private var isMediaExpanded = false
    private let expandButton = UIButton(type: .system)
    private let momentButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let pausedIcon = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44.0)))

    private var context: AccountContext?
    private var post: ExplorePost?
    private var imageDimensions = CGSize()
    private var reelSafeInsets = UIEdgeInsets()
    private var isActive = false
    private var isPausedByUser = false
    private var isOverlayPresented = false
    private var isCaptionExpanded = false
    private let fetchDisposable = MetaDisposable()
    private let dataDisposable = MetaDisposable()

    var toggleMute: (() -> Void)?
    var openInChannel: (() -> Void)?
    var sharePost: (() -> Void)?
    var exploreQuote: ((String) -> Void)?
    var currentVideoMoment: Int? { if let post = self.post, case .video = post.kind { return self.playerView.currentSeconds }; return nil }
    var shareQuote: ((String) -> Void)?
    var shareMoment: ((Int) -> Void)?
    var discussPost: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.backgroundColor = .black
        for surface in [self.contextSurface, self.readingSurface] {
            surface.layer.cornerRadius = 26.0
            surface.layer.cornerCurve = .continuous
            self.contentView.addSubview(surface)
        }
        self.contentView.addSubview(self.sourceAvatar.view)
        self.sourceDate.font = UIFont.systemFont(ofSize: 12.0, weight: .regular)
        self.contentView.addSubview(self.sourceDate)
        self.quoteHint.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        self.quoteHint.textAlignment = .center
        self.quoteHint.text = "Select a passage to quote it in a chat"
        self.contentView.addSubview(self.quoteHint)
        self.contentView.addSubview(self.imageNode.view)
        self.contentView.addSubview(self.playerView)
        self.contentView.layer.insertSublayer(self.reelScrim, above: self.playerView.layer)
        self.readingScrollView.alwaysBounceVertical = true
        self.readingScrollView.showsVerticalScrollIndicator = true
        self.readingLabel.isEditable = false
        self.readingLabel.isScrollEnabled = false
        self.readingLabel.backgroundColor = .clear
        self.readingLabel.textContainerInset = .zero
        self.readingLabel.textContainer.lineFragmentPadding = 0.0
        self.readingLabel.delegate = self
        self.readingLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: 19.0))
        self.readingLabel.adjustsFontForContentSizeCategory = true
        self.readingScrollView.addSubview(self.readingLabel)
        self.contentView.addSubview(self.readingScrollView)

        self.activityIndicator.color = .white
        self.activityIndicator.hidesWhenStopped = true
        self.contentView.addSubview(self.activityIndicator)

        self.scrim.colors = [UIColor(white: 0.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.6).cgColor]
        self.contentView.layer.addSublayer(self.scrim)

        self.titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        self.titleLabel.adjustsFontForContentSizeCategory = true
        self.titleLabel.textColor = .white
        self.captionLabel.font = UIFont.preferredFont(forTextStyle: .body)
        self.captionLabel.adjustsFontForContentSizeCategory = true
        self.captionLabel.textColor = UIColor(white: 1.0, alpha: 0.96)
        self.captionLabel.numberOfLines = 0
        self.captionScrollView.showsVerticalScrollIndicator = true
        self.captionScrollView.addSubview(self.captionLabel)
        self.contentView.addSubview(self.captionScrollView)
        self.captionToggle.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.captionToggle.titleLabel?.adjustsFontForContentSizeCategory = true
        self.captionToggle.contentHorizontalAlignment = .leading
        self.captionToggle.addTarget(self, action: #selector(self.captionTogglePressed), for: .touchUpInside)
        self.contentView.addSubview(self.captionToggle)
        self.viewsLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .semibold)
        self.viewsLabel.textColor = .white
        self.viewsLabel.textAlignment = .center
        self.viewsIcon.contentMode = .scaleAspectFit
        self.viewsIcon.isAccessibilityElement = false
        self.contentView.addSubview(self.viewsIcon)
        for view in [self.titleLabel, self.viewsLabel] {
            self.contentView.addSubview(view)
        }

        for button in [self.muteButton, self.openButton, self.shareButton, self.playButton, self.discussButton, self.momentButton, self.expandButton] {
            button.layer.cornerRadius = 14.0
            button.clipsToBounds = true
            self.contentView.addSubview(button)
        }
        self.configureAction(self.openButton, symbol: "arrow.up.right.square", title: ExploreStrings.string("ExplorePostAction"))
        self.openButton.accessibilityLabel = ExploreStrings.string("ExploreOpenChannel")
        self.openButton.addTarget(self, action: #selector(self.openPressed), for: .touchUpInside)
        self.configureAction(self.shareButton, symbol: "paperplane", title: ExploreStrings.string("ExploreShare"))
        self.shareButton.accessibilityLabel = ExploreStrings.string("ExploreShare")
        self.shareButton.addTarget(self, action: #selector(self.sharePressed), for: .touchUpInside)
        self.configureAction(self.expandButton, symbol: "arrow.up.left.and.arrow.down.right", title: ExploreStrings.string("ExploreExpandMedia"))
        self.expandButton.addTarget(self, action: #selector(self.expandPressed), for: .touchUpInside)
        self.configureAction(self.discussButton, symbol: "bubble.left.and.bubble.right", title: ExploreStrings.string("ExploreDiscuss"))
        self.discussButton.addTarget(self, action: #selector(self.discussPressed), for: .touchUpInside)
        self.configureAction(self.momentButton, symbol: "clock.arrow.circlepath", title: ExploreStrings.string("ExploreMoment"))
        self.momentButton.accessibilityLabel = "Send this video moment to a chat"
        self.momentButton.addTarget(self, action: #selector(self.momentPressed), for: .touchUpInside)
        self.muteButton.addTarget(self, action: #selector(self.mutePressed), for: .touchUpInside)
        self.playButton.addTarget(self, action: #selector(self.tapped), for: .touchUpInside)
        self.updatePlayButton()

        self.progressView.trackTintColor = UIColor.white.withAlphaComponent(0.25)
        self.progressView.progressTintColor = .white
        self.progressView.isUserInteractionEnabled = false
        self.progressView.isAccessibilityElement = false
        self.contentView.addSubview(self.progressView)
        self.playerView.progressChanged = { [weak self] progress in
            self?.progressView.setProgress(progress, animated: false)
        }

        self.pausedIcon.tintColor = UIColor(white: 1.0, alpha: 0.85)
        self.pausedIcon.isHidden = true
        self.contentView.addSubview(self.pausedIcon)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.tapped))
        tap.delegate = self
        self.contentView.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(self.held(_:)))
        hold.minimumPressDuration = 0.25
        hold.delegate = self
        self.contentView.addGestureRecognizer(hold)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== self.contentView {
            if current is UIControl || current === self.captionScrollView || current === self.readingScrollView {
                return false
            }
            view = current.superview
        }
        return true
    }

    private func configureAction(_ button: UIButton, symbol: String, title: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21.0, weight: .medium))
        let transport = button === self.playButton || button === self.muteButton || button === self.expandButton
        configuration.title = transport ? nil : title
        button.accessibilityLabel = title
        configuration.imagePlacement = transport ? .leading : .top
        configuration.imagePadding = 2.0
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 3.0, leading: 2.0, bottom: 3.0, trailing: 2.0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
            return attributes
        }
        button.configuration = configuration
    }

    private func updatePlayButton() {
        let key = self.isPausedByUser ? "ExplorePlay" : "ExplorePause"
        self.configureAction(self.playButton, symbol: self.isPausedByUser ? "play.fill" : "pause.fill", title: ExploreStrings.string(key))
        self.playButton.accessibilityLabel = ExploreStrings.string(key)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.fetchDisposable.dispose()
        self.dataDisposable.dispose()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.fetchDisposable.set(nil)
        self.dataDisposable.set(nil)
        self.playerView.reset()
        self.activityIndicator.stopAnimating()
        self.isActive = false
        self.isPausedByUser = false
        self.isOverlayPresented = false
        self.isCaptionExpanded = false
        self.captionScrollView.contentOffset = .zero
        self.progressView.progress = 0.0
        self.updatePlayButton()
        self.pausedIcon.isHidden = true
    }

    func configure(context: AccountContext, post: ExplorePost, isMuted: Bool) {
        self.context = context
        self.post = post
        let message = post.message._asMessage()
        let theme = context.sharedContext.currentPresentationData.with { $0 }.theme
        let isText: Bool
        if case .text = post.kind { isText = true } else { isText = false }
        self.isMediaExpanded = false
        self.configureAction(self.expandButton, symbol: "arrow.up.left.and.arrow.down.right", title: ExploreStrings.string("ExploreExpandMedia"))
        self.expandButton.isHidden = isText
        self.readingScrollView.isHidden = !isText
        self.imageNode.view.isHidden = isText
        self.playerView.isHidden = isText
        self.scrim.isHidden = true
        self.isTextPost = isText
        self.contentView.backgroundColor = isText ? theme.list.blocksBackgroundColor : UIColor(rgb: 0x080f18)
        self.contextSurface.backgroundColor = isText ? theme.list.itemBlocksBackgroundColor : UIColor(rgb: 0x142130)
        self.contextSurface.layer.borderWidth = 0.5
        self.contextSurface.layer.borderColor = (isText ? theme.list.itemPrimaryTextColor : UIColor.white).withAlphaComponent(0.07).cgColor
        self.readingSurface.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.readingSurface.isHidden = !isText
        self.sourceAvatar.setPeer(context: context, theme: theme, peer: post.peer, displayDimensions: CGSize(width: 40.0, height: 40.0))
        self.sourceDate.text = DateFormatter.localizedString(from: Date(timeIntervalSince1970: Double(post.message.timestamp)), dateStyle: .medium, timeStyle: .short)
        self.sourceDate.textColor = isText ? theme.list.itemSecondaryTextColor : UIColor.white.withAlphaComponent(0.55)
        self.quoteHint.textColor = theme.list.itemSecondaryTextColor
        self.readingLabel.textColor = theme.list.itemPrimaryTextColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5.0
        paragraph.paragraphSpacing = 8.0
        self.readingLabel.attributedText = NSAttributedString(string: post.message.text.trimmingCharacters(in: .whitespacesAndNewlines), attributes: [.font: self.readingLabel.font ?? UIFont.systemFont(ofSize: 19.0), .foregroundColor: theme.list.itemPrimaryTextColor, .paragraphStyle: paragraph])
        self.readingScrollView.contentOffset = .zero
        self.titleLabel.textColor = isText ? theme.list.itemPrimaryTextColor : .white
        self.viewsLabel.textColor = isText ? theme.list.itemSecondaryTextColor : UIColor.white.withAlphaComponent(0.55)
        self.viewsIcon.tintColor = self.viewsLabel.textColor
        let actionTint = isText ? theme.list.itemAccentColor : UIColor(rgb: 0x64baff)
        let actionBackground = isText ? theme.list.itemAccentColor.withAlphaComponent(0.07) : UIColor.white.withAlphaComponent(0.06)
        for button in [self.openButton, self.shareButton, self.muteButton, self.playButton, self.discussButton, self.momentButton, self.expandButton] {
            button.tintColor = actionTint
            button.backgroundColor = actionBackground
        }
        self.shareButton.backgroundColor = theme.list.itemAccentColor
        self.shareButton.tintColor = .white
        self.captionToggle.tintColor = actionTint
        self.captionLabel.textColor = isText ? theme.list.itemPrimaryTextColor : UIColor.white.withAlphaComponent(0.9)
        self.shareButton.isHidden = post.message.groupingKey != nil || post.message._asMessage().isCopyProtected() || post.peer.isCopyProtectionEnabled

        self.readingLabel.isSelectable = !self.shareButton.isHidden
        self.discussButton.isHidden = !post.message.attributes.contains { ($0 as? ReplyThreadMessageAttribute)?.commentsPeerId != nil }
        self.momentButton.isHidden = true
        switch post.kind {
        case let .photo(image):
            self.imageDimensions = image.representations.last?.dimensions.cgSize ?? CGSize(width: 1.0, height: 1.0)
            self.imageNode.setSignal(mediaGridMessagePhoto(account: context.account, userLocation: .peer(post.id.peerId), photoReference: .message(message: MessageReference(message), media: image), fullRepresentationSize: CGSize(width: 1280.0, height: 1280.0)))
            self.muteButton.isHidden = true
            self.playButton.isHidden = true
            self.progressView.isHidden = true
        case let .video(file, _):
            self.momentButton.isHidden = self.shareButton.isHidden
            self.imageDimensions = file.dimensions?.cgSize ?? CGSize(width: 1.0, height: 1.0)
            self.imageNode.setSignal(chatMessageVideoThumbnail(account: context.account, userLocation: .peer(post.id.peerId), fileReference: .message(message: MessageReference(message), media: file)))
            self.muteButton.isHidden = false
            self.playButton.isHidden = false
            self.progressView.isHidden = false
        case .text:
            self.imageDimensions = .zero
            self.imageNode.setSignal(.complete())
            self.muteButton.isHidden = true
            self.playButton.isHidden = true
            self.progressView.isHidden = true
        }
        self.setMuted(isMuted)

        self.titleLabel.text = post.peer.compactDisplayTitle
        let text = post.message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.captionLabel.text = isText || text.isEmpty ? nil : text
        self.captionScrollView.isHidden = self.captionLabel.text == nil
        self.isCaptionExpanded = false
        self.captionScrollView.contentOffset = .zero
        self.updatePlayButton()
        if let viewCount = post.viewCount {
            self.viewsLabel.text = compactNumericCountString(viewCount)
            self.viewsLabel.accessibilityLabel = "\(viewCount) \(ExploreStrings.string("ExploreViews"))"
            self.viewsIcon.isHidden = false
        } else {
            self.viewsLabel.text = nil
            self.viewsIcon.isHidden = true
        }
        self.accessibilityLabel = [post.peer.compactDisplayTitle, self.captionLabel.text].compactMap { $0 }.joined(separator: ", ")
        self.setNeedsLayout()
    }

    func update(safeInsets: UIEdgeInsets) {
        self.reelSafeInsets = safeInsets
        self.setNeedsLayout()
    }

    func setMuted(_ isMuted: Bool) {
        self.playerView.isMuted = isMuted
        self.configureAction(self.muteButton, symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: ExploreStrings.string("ExploreSound"))
        self.muteButton.accessibilityLabel = ExploreStrings.string(isMuted ? "ExploreUnmute" : "ExploreMute")
    }

    // Only the active reel loads and plays its video.
    func setActive(_ isActive: Bool) {
        if self.isActive == isActive {
            return
        }
        self.isActive = isActive
        if isActive {
            self.pausedIcon.isHidden = !self.isPausedByUser
            self.startVideoIfNeeded()
        } else {
            self.playerView.pause()
        }
    }

    func pauseForTogether() {
        self.isPausedByUser = true
        self.playerView.pause()
        self.updatePlayButton()
    }

    func pauseForOverlay() {
        self.isOverlayPresented = true
        self.playerView.pause()
    }

    func resumeAfterOverlay() {
        self.isOverlayPresented = false
        if self.isActive && !self.isPausedByUser {
            self.playerView.play()
        }
    }

    private func startVideoIfNeeded() {
        guard let context = self.context, let post = self.post, case let .video(file, _) = post.kind else {
            return
        }
        if self.playerView.hasItem {
            if !self.isPausedByUser && !self.isOverlayPresented {
                self.playerView.play()
            }
            return
        }
        let message = post.message._asMessage()
        let reference = FileMediaReference.message(message: MessageReference(message), media: file)
        self.activityIndicator.startAnimating()
        self.fetchDisposable.set(context.engine.resources.fetch(reference: reference.resourceReference(file.resource), userLocation: .peer(post.id.peerId), userContentType: .video).start())
        self.dataDisposable.set((context.engine.resources.data(resource: EngineMediaResource(file.resource), pathExtension: "mp4")
        |> filter { $0.isComplete }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else {
                return
            }
            self.activityIndicator.stopAnimating()
            self.playerView.load(url: URL(fileURLWithPath: data.path))
            if self.isActive && !self.isPausedByUser && !self.isOverlayPresented {
                self.playerView.play()
            }
        }))
    }

    @objc private func tapped() {
        guard self.isActive, case .video = self.post?.kind else {
            return
        }
        self.isPausedByUser.toggle()
        self.pausedIcon.isHidden = !self.isPausedByUser
        self.updatePlayButton()
        if self.isPausedByUser {
            self.playerView.pause()
        } else {
            self.playerView.play()
        }
    }

    // Holding pauses, letting go resumes.
    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard self.isActive, !self.isPausedByUser else {
            return
        }
        switch recognizer.state {
        case .began:
            self.playerView.pause()
        case .ended, .cancelled, .failed:
            self.playerView.play()
        default:
            break
        }
    }

    @objc private func captionTogglePressed() {
        self.isCaptionExpanded.toggle()
        if !self.isCaptionExpanded { self.captionScrollView.setContentOffset(.zero, animated: false) }
        self.setNeedsLayout()
    }

    @objc private func mutePressed() {
        self.toggleMute?()
    }

    @objc private func openPressed() {
        self.openInChannel?()
    }

    @objc private func sharePressed() {
        self.sharePost?()
    }

    @objc private func expandPressed() {
        self.isMediaExpanded.toggle()
        self.configureAction(self.expandButton, symbol: self.isMediaExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", title: ExploreStrings.string(self.isMediaExpanded ? "ExploreShowContext" : "ExploreExpandMedia"))
        self.setNeedsLayout()
    }

    @objc private func discussPressed() { self.discussPost?() }
    @objc private func momentPressed() { self.shareMoment?(self.playerView.currentSeconds) }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard !self.shareButton.isHidden, range.length > 0,
              let textRange = Range(range, in: textView.text) else { return UIMenu(children: suggestedActions) }
        let quote = String(textView.text[textRange])
        let action = UIAction(title: ExploreStrings.string("ExploreQuote"), image: UIImage(systemName: "paperplane")) { [weak self] _ in
            self?.shareQuote?(quote)
        }
        let together = UIAction(title: "Explore this quote with…", image: UIImage(systemName: "person.2")) { [weak self] _ in self?.exploreQuote?(quote) }
        return UIMenu(children: [action, together] + suggestedActions)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        let inset = max(20.0, self.reelSafeInsets.left + 16.0)
        let rightInset = max(20.0, self.reelSafeInsets.right + 16.0)
        let width = max(0.0, bounds.width - inset - rightInset)
        let isRTL = self.contentView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let top = self.reelSafeInsets.top + 58.0
        let bottom = bounds.height - self.reelSafeInsets.bottom - 12.0
        let compact = bounds.height < 500.0
        self.titleLabel.isHidden = self.isMediaExpanded
        self.captionScrollView.isHidden = self.isMediaExpanded || self.captionLabel.text == nil
        self.viewsLabel.isHidden = self.isMediaExpanded
        self.viewsIcon.isHidden = self.isMediaExpanded || self.viewsLabel.text == nil
        self.openButton.isHidden = self.isMediaExpanded
        self.discussButton.isHidden = self.isMediaExpanded || !(self.post?.message.attributes.contains { ($0 as? ReplyThreadMessageAttribute)?.commentsPeerId != nil } ?? false)
        self.shareButton.isHidden = self.isMediaExpanded || self.post?.message.groupingKey != nil || self.post?.message._asMessage().isCopyProtected() == true || self.post?.peer.isCopyProtectionEnabled == true
        self.momentButton.isHidden = self.shareButton.isHidden || self.playButton.isHidden
        let buttons = [self.openButton, self.discussButton, self.shareButton, self.momentButton].filter { !$0.isHidden }
        let actionY = bottom - 58.0
        self.contextSurface.isHidden = self.isMediaExpanded
        self.sourceAvatar.isHidden = self.isMediaExpanded
        self.sourceDate.isHidden = self.isMediaExpanded
        self.quoteHint.isHidden = !self.isTextPost || self.shareButton.isHidden
        let buttonWidth = (width - CGFloat(max(0, buttons.count - 1)) * 8.0) / CGFloat(max(1, buttons.count))
        for (index, button) in buttons.enumerated() {
            var configuration = button.configuration
            configuration?.imagePlacement = buttons.count <= 3 ? .leading : .top
            configuration?.imagePadding = buttons.count <= 3 ? 6.0 : 4.0
            configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = UIFont.systemFont(ofSize: buttons.count <= 3 ? 14.0 : 12.0, weight: .semibold)
                return result
            }
            button.configuration = configuration
            let visualIndex = isRTL ? buttons.count - 1 - index : index
            button.frame = CGRect(x: inset + CGFloat(visualIndex) * (buttonWidth + 8.0), y: actionY, width: buttonWidth, height: 50.0)
        }
        let titleHeight = self.titleLabel.font.lineHeight + 4.0
        let captionFullHeight = self.captionLabel.text == nil ? CGFloat(0.0) : self.captionLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let collapsedHeight = self.captionLabel.font.lineHeight * (compact ? 1.0 : 2.0)
        let needsToggle = captionFullHeight > collapsedHeight + 1.0
        self.captionToggle.isHidden = !needsToggle || self.isMediaExpanded
        let captionHeight = min(captionFullHeight, self.isCaptionExpanded ? bounds.height * 0.25 : collapsedHeight)
        let sourceHeight = max(48.0, titleHeight + 18.0)
        let contextHeight = sourceHeight + 4.0 + captionHeight + (needsToggle ? 44.0 : 8.0)
        let contextY = max(top + 48.0, actionY - contextHeight - 8.0)
        let sourceY = self.isTextPost ? top + 4.0 : contextY
        let sourceTextX = isRTL ? inset : inset + 52.0
        self.sourceAvatar.frame = CGRect(x: isRTL ? bounds.width - rightInset - 40.0 : inset, y: sourceY, width: 40.0, height: 40.0)
        self.titleLabel.frame = CGRect(x: sourceTextX, y: sourceY, width: max(0.0, width - 52.0), height: titleHeight)
        self.sourceDate.frame = CGRect(x: sourceTextX, y: sourceY + titleHeight + 1.0, width: max(0.0, width - 52.0), height: 17.0)
        self.viewsLabel.isHidden = true
        self.viewsIcon.isHidden = true
        self.contextSurface.frame = CGRect(x: inset - 16.0, y: self.isTextPost ? actionY - 14.0 : contextY - 16.0, width: width + 32.0, height: bottom + 8.0 - (self.isTextPost ? actionY - 14.0 : contextY - 16.0))
        self.captionScrollView.frame = CGRect(x: inset, y: contextY + sourceHeight + 4.0, width: width, height: captionHeight)
        self.captionLabel.frame = CGRect(x: 0.0, y: 0.0, width: width, height: captionFullHeight)
        self.captionScrollView.contentSize = CGSize(width: width, height: captionFullHeight)
        self.captionScrollView.isScrollEnabled = self.isCaptionExpanded && captionFullHeight > captionHeight
        self.captionToggle.setTitle(ExploreStrings.string(self.isCaptionExpanded ? "ExploreCaptionLess" : "ExploreCaptionMore"), for: .normal)
        self.captionToggle.frame = CGRect(x: inset, y: self.captionScrollView.frame.maxY, width: width, height: 44.0)

        let mediaBottom = self.isMediaExpanded ? bottom - 52.0 : max(top, contextY - 72.0)
        // Use the full safe width for media; text keeps a comfortable reading inset.
        let mediaLeft = max(8.0, self.reelSafeInsets.left)
        let mediaWidth = max(0.0, bounds.width - mediaLeft - max(8.0, self.reelSafeInsets.right))
        let mediaArea = CGSize(width: mediaWidth, height: max(0.0, mediaBottom - top))
        let fitted = self.imageDimensions.width > 0.0 ? self.imageDimensions.aspectFitted(mediaArea) : mediaArea
        let mediaFrame = CGRect(x: mediaLeft + (mediaWidth - fitted.width) * 0.5, y: top + (mediaArea.height - fitted.height) * 0.5, width: fitted.width, height: fitted.height)
        let apply = self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: fitted, boundingSize: fitted, intrinsicInsets: UIEdgeInsets()))
        apply()
        self.imageNode.frame = mediaFrame
        self.playerView.frame = mediaFrame
        self.activityIndicator.center = CGPoint(x: mediaFrame.midX, y: mediaFrame.midY)
        self.pausedIcon.sizeToFit()
        self.pausedIcon.center = self.activityIndicator.center
        // A quiet transport row, with full-size touch targets instead of stacked miniature labels.
        for button in [self.playButton, self.muteButton, self.expandButton] {
            var configuration = button.configuration
            configuration?.title = nil
            configuration?.imagePlacement = .leading
            configuration?.imagePadding = 0.0
            button.configuration = configuration
            button.backgroundColor = .clear
        }
        self.expandButton.accessibilityLabel = ExploreStrings.string(self.isMediaExpanded ? "ExploreShowContext" : "ExploreExpandMedia")
        self.playButton.frame = CGRect(x: isRTL ? bounds.width - rightInset - 44.0 : inset, y: mediaBottom + 4.0, width: 44.0, height: 44.0)
        self.muteButton.frame = CGRect(x: isRTL ? inset : bounds.width - rightInset - 44.0, y: mediaBottom + 4.0, width: 44.0, height: 44.0)
        self.expandButton.frame = CGRect(x: isRTL ? inset + 52.0 : bounds.width - rightInset - 96.0, y: mediaBottom + 4.0, width: 44.0, height: 44.0)
        self.progressView.frame = CGRect(x: inset, y: mediaBottom, width: width, height: 3.0)
        let readingTop = sourceY + sourceHeight + 10.0
        self.readingSurface.frame = CGRect(x: inset - 16.0, y: readingTop, width: width + 32.0, height: max(0.0, actionY - 48.0 - readingTop))
        self.readingScrollView.frame = CGRect(x: inset + 2.0, y: self.readingSurface.frame.minY + 16.0, width: width - 4.0, height: max(0.0, self.readingSurface.frame.height - 32.0))
        self.quoteHint.frame = CGRect(x: inset, y: actionY - 42.0, width: width, height: 20.0)
        let readingSize = self.readingLabel.sizeThatFits(CGSize(width: self.readingScrollView.bounds.width, height: .greatestFiniteMagnitude))
        self.readingLabel.frame = CGRect(x: 0.0, y: 8.0, width: self.readingScrollView.bounds.width, height: readingSize.height)
        self.readingScrollView.contentSize = CGSize(width: self.readingScrollView.bounds.width, height: readingSize.height + 16.0)
        self.readingScrollView.isScrollEnabled = self.readingScrollView.contentSize.height > self.readingScrollView.bounds.height

        self.reelScrim.isHidden = self.isTextPost || self.isMediaExpanded
        if self.isTextPost {
            self.configureAction(self.openButton, symbol: "arrow.up.right.square", title: ExploreStrings.string("ExplorePostAction"))
            self.configureAction(self.shareButton, symbol: "paperplane", title: ExploreStrings.string("ExploreShare"))
            self.configureAction(self.discussButton, symbol: "bubble.left.and.bubble.right", title: ExploreStrings.string("ExploreDiscuss"))
            self.configureAction(self.momentButton, symbol: "clock.arrow.circlepath", title: ExploreStrings.string("ExploreMoment"))
            return
        }

        // Reel layout: edge-to-edge media, text straight on a fade, one rail of icons.
        let reelSize = self.imageDimensions.width > 0.0 ? self.imageDimensions.aspectFitted(bounds.size) : bounds.size
        let reelFrame = CGRect(x: floor((bounds.width - reelSize.width) * 0.5), y: floor((bounds.height - reelSize.height) * 0.5), width: reelSize.width, height: reelSize.height)
        let applyReel = self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: reelSize, boundingSize: reelSize, intrinsicInsets: UIEdgeInsets()))
        applyReel()
        self.imageNode.frame = reelFrame
        self.playerView.frame = reelFrame
        self.activityIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
        self.pausedIcon.center = self.activityIndicator.center
        self.progressView.frame = CGRect(x: 0.0, y: bounds.height - self.reelSafeInsets.bottom - 2.0, width: bounds.width, height: 2.0)
        self.contextSurface.isHidden = true
        self.playButton.isHidden = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.reelScrim.frame = CGRect(x: 0.0, y: bounds.height * 0.5, width: bounds.width, height: bounds.height * 0.5)
        CATransaction.commit()

        let railSide: CGFloat = 44.0
        let railX = isRTL ? max(8.0, self.reelSafeInsets.left + 8.0) : bounds.width - railSide - max(8.0, self.reelSafeInsets.right + 8.0)
        var railY = bottom - railSide - 8.0
        let rail: [(UIButton, String)] = [(self.shareButton, "paperplane"), (self.openButton, "arrow.up.right.square"), (self.discussButton, "bubble.left.and.bubble.right"), (self.momentButton, "clock.arrow.circlepath"), (self.expandButton, ""), (self.muteButton, "")]
        for (button, symbol) in rail where !button.isHidden {
            var configuration = button.configuration
            if !symbol.isEmpty {
                configuration?.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22.0, weight: .medium))
            }
            configuration?.title = nil
            configuration?.imagePadding = 0.0
            configuration?.baseForegroundColor = .white
            configuration?.background.backgroundColor = .clear
            button.configuration = configuration
            button.backgroundColor = .clear
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.5
            button.layer.shadowRadius = 4.0
            button.layer.shadowOffset = .zero
            button.clipsToBounds = false
            button.frame = CGRect(x: railX, y: railY, width: railSide, height: railSide)
            railY -= railSide + 8.0
        }

        if !self.isMediaExpanded {
            let textX = isRTL ? railX + railSide + 8.0 : inset
            let textWidth = max(0.0, bounds.width - inset - railSide - 16.0)
            let fullCaption = self.captionLabel.text == nil ? CGFloat(0.0) : self.captionLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
            let shownCaption = min(fullCaption, self.isCaptionExpanded ? bounds.height * 0.3 : self.captionLabel.font.lineHeight * 2.0)
            let hasToggle = fullCaption > self.captionLabel.font.lineHeight * 2.0 + 1.0
            var textY = bottom - 8.0
            if hasToggle {
                textY -= 32.0
                self.captionToggle.frame = CGRect(x: textX, y: textY, width: textWidth, height: 32.0)
            }
            textY -= shownCaption
            self.captionScrollView.frame = CGRect(x: textX, y: textY, width: textWidth, height: shownCaption)
            self.captionLabel.frame = CGRect(x: 0.0, y: 0.0, width: textWidth, height: fullCaption)
            self.captionScrollView.contentSize = CGSize(width: textWidth, height: fullCaption)
            self.sourceAvatar.frame = CGRect(x: isRTL ? textX + textWidth - 36.0 : textX, y: textY - 44.0, width: 36.0, height: 36.0)
            let nameX = isRTL ? textX : textX + 44.0
            self.titleLabel.frame = CGRect(x: nameX, y: textY - 44.0, width: max(0.0, textWidth - 44.0), height: titleHeight)
            self.sourceDate.frame = CGRect(x: nameX, y: textY - 44.0 + titleHeight, width: max(0.0, textWidth - 44.0), height: 16.0)
            self.sourceDate.isHidden = !self.isCaptionExpanded
            if !self.isCaptionExpanded {
                self.titleLabel.frame.origin.y = textY - 44.0 + (36.0 - titleHeight) * 0.5
            }
        }
    }
}

// A looping AVPlayer layer; videos start muted until the user unmutes.
final class ExploreReelPlayerView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var timeObserver: Any?
    var progressChanged: ((Float) -> Void)?

    var isMuted = true {
        didSet {
            self.player?.isMuted = self.isMuted
        }
    }

    var currentSeconds: Int {
        let value = self.player?.currentTime().seconds ?? 0.0
        return value.isFinite ? max(0, Int(value)) : 0
    }

    var hasItem: Bool {
        return self.player != nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        (self.layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.reset()
    }

    func load(url: URL) {
        self.reset()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = self.isMuted
        self.looper = AVPlayerLooper(player: player, templateItem: item)
        self.player = player
        self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak player] time in
            guard time.seconds.isFinite, let duration = player?.currentItem?.duration.seconds, duration.isFinite, duration > 0.0 else {
                self?.progressChanged?(0.0)
                return
            }
            self?.progressChanged?(Float(max(0.0, min(1.0, time.seconds / duration))))
        }
        (self.layer as? AVPlayerLayer)?.player = player
    }

    func play() {
        self.player?.play()
    }

    func pause() {
        self.player?.pause()
    }

    func reset() {
        self.player?.pause()
        if let timeObserver = self.timeObserver {
            self.player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        self.looper = nil
        self.player = nil
        self.progressChanged?(0.0)
        (self.layer as? AVPlayerLayer)?.player = nil
    }
}
