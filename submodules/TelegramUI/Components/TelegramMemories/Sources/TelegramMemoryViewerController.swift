import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AvatarNode
import TelegramNotes

// A button that reports when its menu opens and closes, so the viewer can pause while it is up.
private final class MemoryMenuButton: UIButton {
    var menuVisibilityChanged: ((Bool) -> Void)?

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        self.menuVisibilityChanged?(true)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        self.menuVisibilityChanged?(false)
    }
}

// Today's memories, full screen and one photo at a time, like a Story. The main action sends the memory back
// to the person it is with, which is what turns an old photo into a new conversation.
public final class TelegramMemoryViewerController: UIViewController {
    private static let itemDuration: Double = 5.0

    public static func present(context: AccountContext, memories: [TelegramMemory], theme: PresentationTheme, sourceView: UIView?, windowScene: UIWindowScene) {
        guard !memories.isEmpty else {
            return
        }
        let viewer = TelegramMemoryViewerController(context: context, memories: memories, theme: theme)
        if let sourceView, let window = sourceView.window {
            viewer.sourceFrame = sourceView.convert(sourceView.bounds, to: window)
            viewer.sourceCornerRadius = sourceView.layer.cornerRadius
        }
        viewer.sourceView = sourceView
        TelegramNoteHostWindow.present(viewer, windowScene: windowScene, animated: false)
    }

    private let context: AccountContext
    private let store: TelegramMemoriesStore
    private let theme: PresentationTheme
    private var memories: [TelegramMemory]
    private weak var sourceView: UIView?
    private var sourceFrame: CGRect?
    private var sourceCornerRadius: CGFloat = 11.0

    private var memoryIndex = 0
    private var itemIndex = 0
    private var progress: Double = 0.0
    private var sentMemoryIds = Set<String>()
    private var isSending = false
    private var pauseReasons = Set<String>()
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var isClosing = false
    private var hasAppeared = false

    private let backgroundView = TelegramMemoryImageView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let dimView = UIView()
    private let photoContainer = UIView()
    private let photoView = TelegramMemoryImageView()
    private let chromeView = UIView()
    private var progressTracks: [UIView] = []
    private var progressFills: [UIView] = []
    private let avatarImageView = UIImageView()
    private let avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 15.0))
    private let nameLabel = UILabel()
    private let dateLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .custom)
    private let moreButton = MemoryMenuButton(type: .system)

    private init(context: AccountContext, memories: [TelegramMemory], theme: PresentationTheme) {
        self.context = context
        self.store = TelegramMemoriesStore.shared(context: context)
        self.memories = memories
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.displayLink?.invalidate()
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    private var memory: TelegramMemory {
        return self.memories[self.memoryIndex]
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black

        self.view.addSubview(self.backgroundView)
        self.view.addSubview(self.blurView)
        self.dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.35)
        self.view.addSubview(self.dimView)

        self.photoContainer.clipsToBounds = true
        self.photoContainer.layer.cornerCurve = .continuous
        self.photoContainer.layer.cornerRadius = 24.0
        self.photoContainer.addSubview(self.photoView)
        self.view.addSubview(self.photoContainer)

        self.view.addSubview(self.chromeView)
        makeTouchable(self.chromeView)
        self.avatarImageView.clipsToBounds = true
        self.avatarImageView.layer.cornerRadius = 18.0
        self.chromeView.addSubview(self.avatarImageView)
        self.chromeView.addSubview(self.avatarNode.view)
        self.nameLabel.font = Font.semibold(16.0)
        self.nameLabel.textColor = .white
        self.chromeView.addSubview(self.nameLabel)
        self.dateLabel.font = Font.regular(13.0)
        self.dateLabel.textColor = UIColor(white: 1.0, alpha: 0.72)
        self.chromeView.addSubview(self.dateLabel)

        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)), for: .normal)
        self.closeButton.tintColor = .white
        self.closeButton.accessibilityLabel = TelegramMemoriesStrings.string("MemoriesClose")
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        makeTouchable(self.closeButton)
        self.chromeView.addSubview(self.closeButton)

        self.sendButton.addTarget(self, action: #selector(self.sendPressed), for: .touchUpInside)
        makeTouchable(self.sendButton)
        self.chromeView.addSubview(self.sendButton)

        self.moreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)), for: .normal)
        self.moreButton.tintColor = .white
        self.moreButton.backgroundColor = UIColor(white: 1.0, alpha: 0.18)
        self.moreButton.layer.cornerRadius = 25.0
        self.moreButton.accessibilityLabel = TelegramMemoriesStrings.string("MemoriesMore")
        self.moreButton.showsMenuAsPrimaryAction = true
        self.moreButton.menuVisibilityChanged = { [weak self] isVisible in
            self?.setPaused(isVisible, reason: "menu")
        }
        self.chromeView.addSubview(self.moreButton)

        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:))))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.longPressed(_:)))
        longPress.minimumPressDuration = 0.2
        self.view.addGestureRecognizer(longPress)
        self.view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panned(_:))))

        self.showCurrent()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.layoutViews()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !self.hasAppeared else {
            return
        }
        self.hasAppeared = true
        self.view.layoutIfNeeded()
        let finalFrame = self.photoContainer.frame
        self.backgroundView.alpha = 0.0
        self.blurView.alpha = 0.0
        self.dimView.alpha = 0.0
        self.chromeView.alpha = 0.0
        self.view.backgroundColor = .clear
        if let sourceFrame = self.sourceFrame, !UIAccessibility.isReduceMotionEnabled {
            self.photoContainer.frame = self.view.convert(sourceFrame, from: nil)
            self.photoView.frame = self.photoContainer.bounds
            self.photoContainer.layer.cornerRadius = self.sourceCornerRadius
            self.sourceView?.alpha = 0.0
        } else {
            self.photoContainer.alpha = 0.0
        }
        UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
            self.photoContainer.frame = finalFrame
            self.photoView.frame = self.photoContainer.bounds
            self.photoContainer.layer.cornerRadius = 24.0
            self.photoContainer.alpha = 1.0
            self.backgroundView.alpha = 1.0
            self.blurView.alpha = 1.0
            self.dimView.alpha = 1.0
            self.view.backgroundColor = .black
        }, completion: { _ in
            self.sourceView?.alpha = 1.0
        })
        UIView.animate(withDuration: 0.3, delay: 0.18, options: [.curveEaseOut], animations: {
            self.chromeView.alpha = 1.0
        })
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.startTimer()
    }

    private func layoutViews() {
        let bounds = self.view.bounds
        let safe = self.view.safeAreaInsets
        self.backgroundView.frame = bounds.insetBy(dx: -40.0, dy: -40.0)
        self.blurView.frame = bounds
        self.dimView.frame = bounds
        self.chromeView.frame = bounds

        let top = max(safe.top, 20.0) + 8.0
        let barSpacing: CGFloat = 4.0
        let barCount = CGFloat(max(1, self.progressTracks.count))
        let barWidth = (bounds.width - 24.0 - barSpacing * (barCount - 1.0)) / barCount
        for (index, track) in self.progressTracks.enumerated() {
            track.frame = CGRect(x: 12.0 + CGFloat(index) * (barWidth + barSpacing), y: top, width: barWidth, height: 3.0)
        }
        self.layoutProgress()

        let headerY = top + 14.0
        let avatarFrame = CGRect(x: 16.0, y: headerY, width: 36.0, height: 36.0)
        self.avatarImageView.frame = avatarFrame
        self.avatarNode.frame = avatarFrame
        self.nameLabel.frame = CGRect(x: avatarFrame.maxX + 10.0, y: headerY, width: bounds.width - avatarFrame.maxX - 70.0, height: 20.0)
        self.dateLabel.frame = CGRect(x: avatarFrame.maxX + 10.0, y: headerY + 19.0, width: bounds.width - avatarFrame.maxX - 70.0, height: 17.0)
        self.closeButton.frame = CGRect(x: bounds.width - 52.0, y: headerY - 4.0, width: 44.0, height: 44.0)

        let bottom = bounds.height - max(safe.bottom, 16.0) - 8.0
        let buttonHeight: CGFloat = 50.0
        self.moreButton.frame = CGRect(x: bounds.width - 16.0 - buttonHeight, y: bottom - buttonHeight, width: buttonHeight, height: buttonHeight)
        self.sendButton.frame = CGRect(x: 16.0, y: bottom - buttonHeight, width: self.moreButton.frame.minX - 10.0 - 16.0, height: buttonHeight)

        guard !self.isClosing, self.photoContainer.transform.isIdentity else {
            return
        }
        let areaTop = avatarFrame.maxY + 16.0
        let areaBottom = self.sendButton.frame.minY - 18.0
        let maxWidth = bounds.width - 24.0
        let maxHeight = max(1.0, areaBottom - areaTop)
        let aspect = max(0.2, self.photoView.aspectRatio)
        var size = CGSize(width: maxWidth, height: maxWidth / aspect)
        if size.height > maxHeight {
            size = CGSize(width: maxHeight * aspect, height: maxHeight)
        }
        self.photoContainer.frame = CGRect(x: (bounds.width - size.width) * 0.5, y: areaTop + (maxHeight - size.height) * 0.5, width: size.width, height: size.height)
        self.photoView.frame = self.photoContainer.bounds
    }

    private func layoutProgress() {
        for (index, fill) in self.progressFills.enumerated() {
            let track = self.progressTracks[index]
            let fraction: CGFloat
            if index < self.itemIndex {
                fraction = 1.0
            } else if index == self.itemIndex {
                fraction = CGFloat(min(1.0, self.progress))
            } else {
                fraction = 0.0
            }
            fill.frame = CGRect(x: 0.0, y: 0.0, width: track.bounds.width * fraction, height: track.bounds.height)
        }
    }

    // Shows the current photo and the details of the memory it belongs to.
    private func showCurrent() {
        let memory = self.memory
        let item = memory.items[self.itemIndex]
        self.photoView.update(context: self.context, item: item, fullSize: true)
        self.backgroundView.update(context: self.context, item: item, fullSize: false)

        if self.progressTracks.count != memory.items.count {
            self.progressTracks.forEach { $0.removeFromSuperview() }
            self.progressTracks = []
            self.progressFills = []
            for _ in memory.items {
                let track = UIView()
                track.backgroundColor = UIColor(white: 1.0, alpha: 0.3)
                track.layer.cornerRadius = 1.5
                track.clipsToBounds = true
                let fill = UIView()
                fill.backgroundColor = .white
                track.addSubview(fill)
                self.chromeView.addSubview(track)
                self.progressTracks.append(track)
                self.progressFills.append(fill)
            }
        }

        let peer = memory.peer
        if let image = TelegramNotesStore.demoAvatarImage(peerId: peer.id, accountPeerId: self.context.account.peerId) {
            self.avatarImageView.image = image
            self.avatarImageView.isHidden = false
            self.avatarNode.isHidden = true
        } else {
            self.avatarImageView.isHidden = true
            self.avatarNode.isHidden = false
            self.avatarNode.setPeer(context: self.context, theme: self.theme, peer: peer)
        }
        self.nameLabel.text = memory.peerName
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        self.dateLabel.text = memory.shortTitle + " · " + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.timestamp)))

        self.updateSendButton()
        self.updateMenu()
        self.view.setNeedsLayout()
    }

    private func updateSendButton() {
        let memory = self.memory
        let isSent = self.sentMemoryIds.contains(memory.id)
        let title = isSent ? TelegramMemoriesStrings.string("MemoriesSent") : TelegramMemoriesStrings.format("MemoriesSendTo", memory.peerName)
        self.setSendButton(title: title, icon: isSent ? "checkmark" : "paperplane.fill", background: isSent ? UIColor(white: 1.0, alpha: 0.18) : self.theme.list.itemAccentColor)
        self.sendButton.isUserInteractionEnabled = !isSent && !self.isSending
    }

    private func setSendButton(title: String, icon: String, background: UIColor) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = background
        configuration.baseForegroundColor = .white
        configuration.showsActivityIndicator = self.isSending
        if !self.isSending {
            configuration.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.0, weight: .semibold))
            configuration.imagePadding = 8.0
            configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: Font.semibold(17.0)]))
        }
        self.sendButton.configuration = configuration
        self.sendButton.accessibilityLabel = title
    }

    private func updateMenu() {
        let memory = self.memory
        let hidePerson = UIAction(title: TelegramMemoriesStrings.format("MemoriesHidePerson", memory.peerName), image: UIImage(systemName: "eye.slash")) { [weak self] _ in
            self?.hideCurrentPerson()
        }
        let hideToday = UIAction(title: TelegramMemoriesStrings.string("MemoriesHideToday"), image: UIImage(systemName: "moon.zzz")) { [weak self] _ in
            guard let self else {
                return
            }
            self.store.hideForToday()
            self.close()
        }
        self.moreButton.menu = UIMenu(children: [hidePerson, hideToday])
    }

    // MARK: Playback

    private func startTimer() {
        guard self.displayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        defer {
            self.lastTick = displayLink.timestamp
        }
        guard let lastTick = self.lastTick, self.pauseReasons.isEmpty, !self.isClosing else {
            return
        }
        // A long gap between frames (the app in the background) pauses the memory rather than skipping photos.
        self.progress += min(displayLink.timestamp - lastTick, 0.1) / TelegramMemoryViewerController.itemDuration
        if self.progress >= 1.0 {
            self.goForward()
        } else {
            self.layoutProgress()
        }
    }

    private func setPaused(_ isPaused: Bool, reason: String) {
        if isPaused {
            self.pauseReasons.insert(reason)
        } else {
            self.pauseReasons.remove(reason)
        }
    }

    private func goForward() {
        let memory = self.memory
        self.progress = 0.0
        if self.itemIndex + 1 < memory.items.count {
            self.itemIndex += 1
        } else if self.memoryIndex + 1 < self.memories.count {
            self.memoryIndex += 1
            self.itemIndex = 0
        } else {
            self.close()
            return
        }
        self.showCurrent()
    }

    private func goBack() {
        self.progress = 0.0
        if self.itemIndex > 0 {
            self.itemIndex -= 1
        } else if self.memoryIndex > 0 {
            self.memoryIndex -= 1
            self.itemIndex = self.memories[self.memoryIndex].items.count - 1
        }
        self.showCurrent()
    }

    // MARK: Actions

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self.view)
        if self.sendButton.frame.contains(location) || self.moreButton.frame.contains(location) || self.closeButton.frame.contains(location) {
            return
        }
        if location.x < self.view.bounds.width * 0.3 {
            self.goBack()
        } else {
            self.goForward()
        }
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.setPaused(true, reason: "hold")
            UIView.animate(withDuration: 0.2) {
                self.chromeView.alpha = 0.0
            }
        case .ended, .cancelled, .failed:
            self.setPaused(false, reason: "hold")
            UIView.animate(withDuration: 0.2) {
                self.chromeView.alpha = 1.0
            }
        default:
            break
        }
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self.view)
        switch recognizer.state {
        case .began:
            self.setPaused(true, reason: "pan")
        case .changed:
            let offset = max(0.0, translation.y)
            let scale = max(0.82, 1.0 - offset / 1600.0)
            self.photoContainer.transform = CGAffineTransform(translationX: translation.x * 0.3, y: offset).scaledBy(x: scale, y: scale)
            let fade = max(0.0, 1.0 - offset / 400.0)
            self.chromeView.alpha = fade
            self.dimView.alpha = fade
            self.blurView.alpha = fade
            self.backgroundView.alpha = fade
            self.view.backgroundColor = UIColor(white: 0.0, alpha: fade)
        case .ended, .cancelled, .failed:
            let velocity = recognizer.velocity(in: self.view).y
            if translation.y > 120.0 || velocity > 900.0 {
                self.close()
            } else {
                self.setPaused(false, reason: "pan")
                UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: [], animations: {
                    self.photoContainer.transform = .identity
                    self.chromeView.alpha = 1.0
                    self.dimView.alpha = 1.0
                    self.blurView.alpha = 1.0
                    self.backgroundView.alpha = 1.0
                    self.view.backgroundColor = .black
                })
            }
        default:
            break
        }
    }

    @objc private func sendPressed() {
        let memory = self.memory
        guard !self.isSending, !self.sentMemoryIds.contains(memory.id) else {
            return
        }
        self.isSending = true
        self.setPaused(true, reason: "send")
        self.updateSendButton()
        self.store.send(memory, completion: { [weak self] success in
            guard let self else {
                return
            }
            self.isSending = false
            if success {
                self.sentMemoryIds.insert(memory.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            if self.memory.id == memory.id {
                self.updateSendButton()
                if !success {
                    self.setSendButton(title: TelegramMemoriesStrings.string("MemoriesSendFailed"), icon: "exclamationmark.circle", background: self.theme.list.itemAccentColor)
                }
                if success {
                    self.sendButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                    UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: [], animations: {
                        self.sendButton.transform = .identity
                    })
                }
            }
            self.setPaused(false, reason: "send")
        })
    }

    private func hideCurrentPerson() {
        let peerId = self.memory.peer.id
        self.store.hideMemories(with: peerId)
        self.memories.removeAll(where: { $0.peer.id == peerId })
        if self.memories.isEmpty {
            self.close()
            return
        }
        self.memoryIndex = min(self.memoryIndex, self.memories.count - 1)
        self.itemIndex = 0
        self.progress = 0.0
        self.showCurrent()
    }

    @objc private func closePressed() {
        self.close()
    }

    // Shrinks the photo back into the card it came from, when that card is still on screen.
    private func close() {
        guard !self.isClosing else {
            return
        }
        self.isClosing = true
        self.displayLink?.invalidate()
        self.displayLink = nil
        let targetFrame: CGRect?
        if let sourceView = self.sourceView, let window = sourceView.window, !UIAccessibility.isReduceMotionEnabled {
            targetFrame = self.view.convert(sourceView.convert(sourceView.bounds, to: window), from: nil)
            sourceView.alpha = 0.0
        } else {
            targetFrame = nil
        }
        let currentFrame = self.photoContainer.frame
        self.photoContainer.transform = .identity
        self.photoContainer.frame = currentFrame
        UIView.animate(withDuration: 0.38, delay: 0.0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0, options: [], animations: {
            if let targetFrame {
                self.photoContainer.frame = targetFrame
                self.photoView.frame = self.photoContainer.bounds
                self.photoContainer.layer.cornerRadius = self.sourceCornerRadius
            } else {
                self.photoContainer.alpha = 0.0
                self.photoContainer.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            }
            self.chromeView.alpha = 0.0
            self.dimView.alpha = 0.0
            self.blurView.alpha = 0.0
            self.backgroundView.alpha = 0.0
            self.view.backgroundColor = .clear
        }, completion: { _ in
            self.sourceView?.alpha = 1.0
            self.dismiss(animated: false, completion: {
                TelegramNoteHostWindow.remove()
            })
        })
    }
}
