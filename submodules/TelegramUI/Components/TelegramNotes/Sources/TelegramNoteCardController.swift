import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import InvisibleInkDustNode
import TelegramPresentationData

// What opens when a friend's Note is tapped: the whole Note, its time left, and Telegram's ways to answer it.
public final class TelegramNoteCardController: UIViewController, UITextFieldDelegate, UIAdaptivePresentationControllerDelegate {
    private static let reactions = ["❤️", "👍", "🔥", "😂", "😮", "🎉"]

    private let store: TelegramNotesStore
    private let theme: PresentationTheme
    private let peerTitle: String
    private let avatarImage: UIImage?
    private var note: TelegramNote

    private let bubbleView = NoteCardBubbleView()
    private var bubbleHeightConstraint: NSLayoutConstraint?
    private let textHolderNode = ASDisplayNode()
    private let textLabel = UILabel()
    private let hintLabel = UILabel()
    private var dustNode: InvisibleInkDustNode?
    private let pollStack = UIStackView()
    private var pollRows: [PollRowView] = []
    private let reactionStack = UIStackView()
    private var reactionButtons: [UIButton] = []
    private let replyField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let sentLabel = UILabel()
    private var noteDisposable: Disposable?
    private let reactionHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionHaptic = UISelectionFeedbackGenerator()

    public static func present(store: TelegramNotesStore, theme: PresentationTheme, note: TelegramNote, peerTitle: String, avatarImage: UIImage?, windowScene: UIWindowScene) {
        let card = TelegramNoteCardController(store: store, theme: theme, note: note, peerTitle: peerTitle, avatarImage: avatarImage)
        card.presentationController?.delegate = card
        TelegramNoteHostWindow.present(card, windowScene: windowScene)
    }

    private init(store: TelegramNotesStore, theme: PresentationTheme, note: TelegramNote, peerTitle: String, avatarImage: UIImage?) {
        self.store = store
        self.theme = theme
        self.note = note
        self.peerTitle = peerTitle
        self.avatarImage = avatarImage
        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .pageSheet
        if let sheet = self.sheetPresentationController {
            if #available(iOS 16.0, *) {
                let height: CGFloat = note.poll != nil ? 428.0 : (note.isSpoiler && !note.isRevealed ? 354.0 : 328.0)
                sheet.detents = [.custom(resolver: { _ in return height }), .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28.0
        }
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.noteDisposable?.dispose()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let theme = self.theme
        self.view.backgroundColor = theme.list.blocksBackgroundColor
        self.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light

        let avatarView = UIImageView(image: self.avatarImage)
        avatarView.backgroundColor = theme.list.mediaPlaceholderColor
        avatarView.layer.cornerRadius = 26.0
        avatarView.clipsToBounds = true
        avatarView.isAccessibilityElement = false

        let nameLabel = UILabel()
        nameLabel.text = self.peerTitle
        nameLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        nameLabel.textColor = theme.list.itemPrimaryTextColor

        let subtitleLabel = UILabel()
        subtitleLabel.text = self.subtitle()
        subtitleLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .regular)
        subtitleLabel.textColor = theme.list.itemSecondaryTextColor

        let titles = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 2.0
        let header = UIStackView(arrangedSubviews: [avatarView, titles])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12.0

        self.bubbleView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.bubbleView.layer.cornerRadius = 22.0
        self.bubbleView.layer.cornerCurve = .continuous
        self.bubbleView.didLayout = { [weak self] in
            self?.layoutBubbleContent()
        }

        self.textLabel.text = self.note.text
        self.textLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .semibold)
        self.textLabel.textColor = theme.list.itemPrimaryTextColor
        self.textLabel.textAlignment = .center
        self.textLabel.numberOfLines = 0
        self.textHolderNode.view.addSubview(self.textLabel)
        self.textHolderNode.view.isUserInteractionEnabled = false
        self.bubbleView.addSubview(self.textHolderNode.view)

        self.hintLabel.text = TelegramNotesStrings.string("NotesTapToReveal")
        self.hintLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        self.hintLabel.textColor = theme.list.itemSecondaryTextColor
        self.hintLabel.textAlignment = .center
        self.hintLabel.isHidden = true

        if self.note.isSpoiler && !self.note.isRevealed {
            let dustNode = InvisibleInkDustNode(textNode: self.textHolderNode, enableAnimations: !UIAccessibility.isReduceMotionEnabled)
            dustNode.isUserInteractionEnabled = false
            self.bubbleView.addSubview(dustNode.view)
            self.dustNode = dustNode
            self.textHolderNode.alpha = 0.0
            self.hintLabel.isHidden = false
            self.bubbleView.isAccessibilityElement = true
            self.bubbleView.accessibilityTraits = .button
            self.bubbleView.accessibilityLabel = "\(TelegramNotesStrings.string("NotesSpoilerNote")). \(TelegramNotesStrings.string("NotesTapToReveal"))"
            self.bubbleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.bubbleTapped(_:))))
        } else {
            self.bubbleView.isAccessibilityElement = true
            self.bubbleView.accessibilityLabel = self.note.text
        }

        self.pollStack.axis = .vertical
        self.pollStack.spacing = 8.0
        if let poll = self.note.poll {
            for (index, option) in poll.options.enumerated() {
                let row = PollRowView(title: option, theme: theme)
                row.addTarget(self, action: #selector(self.pollRowPressed(_:)), for: .touchUpInside)
                row.tag = index
                self.pollRows.append(row)
                self.pollStack.addArrangedSubview(row)
            }
        }

        self.reactionStack.axis = .horizontal
        self.reactionStack.distribution = .equalSpacing
        for reaction in TelegramNoteCardController.reactions {
            let button = UIButton(type: .custom)
            button.setTitle(reaction, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 25.0)
            button.layer.cornerRadius = 23.0
            button.accessibilityLabel = "\(TelegramNotesStrings.string("NotesReact")) \(reaction)"
            button.addTarget(self, action: #selector(self.reactionPressed(_:)), for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 46.0).isActive = true
            button.heightAnchor.constraint(equalToConstant: 46.0).isActive = true
            self.reactionButtons.append(button)
            self.reactionStack.addArrangedSubview(button)
        }

        self.replyField.delegate = self
        self.replyField.font = UIFont.systemFont(ofSize: 16.0)
        self.replyField.textColor = theme.list.itemPrimaryTextColor
        self.replyField.tintColor = theme.list.itemAccentColor
        self.replyField.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.replyField.layer.cornerRadius = 22.0
        self.replyField.attributedPlaceholder = NSAttributedString(string: "\(TelegramNotesStrings.string("NotesReplyTo")) \(self.peerTitle)", attributes: [.foregroundColor: theme.list.itemPlaceholderTextColor])
        self.replyField.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 16.0, height: 44.0))
        self.replyField.leftViewMode = .always
        self.replyField.returnKeyType = .send
        self.replyField.addTarget(self, action: #selector(self.replyChanged), for: .editingChanged)

        var sendConfiguration = UIButton.Configuration.filled()
        sendConfiguration.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .bold))
        sendConfiguration.cornerStyle = .capsule
        sendConfiguration.baseBackgroundColor = theme.list.itemAccentColor
        sendConfiguration.baseForegroundColor = theme.list.itemCheckColors.foregroundColor
        self.sendButton.configuration = sendConfiguration
        self.sendButton.accessibilityLabel = TelegramNotesStrings.string("NotesReplySend")
        self.sendButton.isEnabled = false
        self.sendButton.addTarget(self, action: #selector(self.sendPressed), for: .touchUpInside)

        self.sentLabel.text = TelegramNotesStrings.string("NotesReplySent")
        self.sentLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
        self.sentLabel.textColor = theme.list.itemAccentColor
        self.sentLabel.textAlignment = .center
        self.sentLabel.alpha = 0.0

        let replyRow = UIStackView(arrangedSubviews: [self.replyField, self.sendButton])
        replyRow.axis = .horizontal
        replyRow.spacing = 8.0

        let stack = UIStackView(arrangedSubviews: [header, self.bubbleView, self.hintLabel, self.pollStack, self.reactionStack, replyRow, self.sentLabel])
        stack.axis = .vertical
        stack.spacing = 14.0
        stack.setCustomSpacing(4.0, after: self.hintLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)
        self.pollStack.isHidden = self.note.poll == nil
        let guide = self.view.layoutMarginsGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 28.0),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 52.0),
            avatarView.heightAnchor.constraint(equalToConstant: 52.0),
            self.replyField.heightAnchor.constraint(equalToConstant: 44.0),
            self.sendButton.widthAnchor.constraint(equalToConstant: 44.0)
        ])
        let bubbleHeightConstraint = self.bubbleView.heightAnchor.constraint(equalToConstant: 88.0)
        bubbleHeightConstraint.isActive = true
        self.bubbleHeightConstraint = bubbleHeightConstraint

        self.applyNote(animated: false)
        self.reactionHaptic.prepare()
        self.selectionHaptic.prepare()
        self.noteDisposable = (self.store.notesSignal
        |> deliverOnMainQueue).start(next: { [weak self] notes in
            guard let self, let note = notes[self.note.peerId] else {
                return
            }
            self.note = note
            self.applyNote(animated: true)
        })
    }

    private func subtitle() -> String {
        let left: String
        switch TelegramNoteTimer.left(expiration: self.note.expirationTimestamp, now: Int32(Date().timeIntervalSince1970)) {
        case let .hours(hours):
            left = "\(hours)\(TelegramNotesStrings.string("NotesHoursLeft"))"
        case let .minutes(minutes):
            left = "\(minutes)\(TelegramNotesStrings.string("NotesMinutesLeft"))"
        }
        return "\(left) · \(self.note.audience.title)"
    }

    // Runs from the bubble's own layout: the controller's pass comes before the stack has sized the bubble.
    private func layoutBubbleContent() {
        let bounds = self.bubbleView.bounds
        if bounds.width <= 0.0 {
            return
        }
        let textSize = self.textLabel.sizeThatFits(CGSize(width: bounds.width - 40.0, height: .greatestFiniteMagnitude))
        let bubbleHeight = max(88.0, ceil(textSize.height) + 40.0)
        if let bubbleHeightConstraint = self.bubbleHeightConstraint, bubbleHeightConstraint.constant != bubbleHeight {
            bubbleHeightConstraint.constant = bubbleHeight
        }
        let textFrame = CGRect(x: floor((bounds.width - textSize.width) * 0.5), y: floor((bounds.height - textSize.height) * 0.5), width: ceil(textSize.width), height: ceil(textSize.height))
        self.textHolderNode.frame = textFrame
        self.textLabel.frame = CGRect(origin: CGPoint(), size: textFrame.size)
        if let dustNode = self.dustNode, !dustNode.isRevealed {
            dustNode.frame = textFrame
            let rect = CGRect(origin: CGPoint(), size: textFrame.size)
            dustNode.update(size: textFrame.size, color: self.theme.list.itemPrimaryTextColor, textColor: self.theme.list.itemPrimaryTextColor, rects: [rect], wordRects: [rect])
        }
    }

    private func applyNote(animated: Bool) {
        if let poll = self.note.poll {
            let percentages = poll.percentages
            for (index, row) in self.pollRows.enumerated() where poll.options.indices.contains(index) {
                row.update(percentage: poll.chosenIndex != nil ? percentages[index] : nil, isChosen: poll.chosenIndex == index, animated: animated && !UIAccessibility.isReduceMotionEnabled)
            }
        }
        for button in self.reactionButtons {
            let isSelected = button.title(for: .normal) == self.note.reaction
            button.backgroundColor = isSelected ? self.theme.list.itemAccentColor.withAlphaComponent(0.2) : .clear
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    @objc private func bubbleTapped(_ recognizer: UITapGestureRecognizer) {
        guard let dustNode = self.dustNode, !dustNode.isRevealed else {
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let location = recognizer.location(in: dustNode.view)
        let bounds = dustNode.view.bounds
        dustNode.revealAtLocation(CGPoint(x: max(0.0, min(bounds.width, location.x)), y: max(0.0, min(bounds.height, location.y))))
        self.store.reveal(note: self.note)
        self.bubbleView.accessibilityLabel = self.note.text
        self.bubbleView.accessibilityTraits = .staticText
        UIView.animate(withDuration: 0.2, animations: {
            self.hintLabel.alpha = 0.0
        })
    }

    @objc private func pollRowPressed(_ sender: UIControl) {
        guard self.note.poll?.chosenIndex == nil else {
            return
        }
        self.selectionHaptic.selectionChanged()
        self.store.vote(note: self.note, index: sender.tag)
    }

    @objc private func reactionPressed(_ sender: UIButton) {
        guard let reaction = sender.title(for: .normal) else {
            return
        }
        if self.note.reaction == reaction {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.store.setReaction(nil, note: self.note)
            return
        }
        self.reactionHaptic.impactOccurred()
        self.reactionHaptic.prepare()
        self.store.setReaction(reaction, note: self.note)
        if !UIAccessibility.isReduceMotionEnabled {
            self.burst(reaction: reaction, from: sender)
        }
    }

    // A reaction lands with a pop and a few copies of itself flying out.
    private func burst(reaction: String, from button: UIButton) {
        button.layer.removeAnimation(forKey: "pop")
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1.0, 1.45, 0.92, 1.0]
        pop.keyTimes = [0.0, 0.4, 0.75, 1.0]
        pop.duration = 0.42
        button.layer.add(pop, forKey: "pop")

        let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: self.view)
        let count = 7
        for index in 0 ..< count {
            let label = UILabel()
            label.text = reaction
            label.font = UIFont.systemFont(ofSize: 18.0)
            label.sizeToFit()
            label.center = center
            label.isUserInteractionEnabled = false
            self.view.addSubview(label)
            let angle = -CGFloat.pi * (CGFloat(index) + 0.5) / CGFloat(count)
            let distance: CGFloat = 54.0 + CGFloat(index % 3) * 16.0
            UIView.animate(withDuration: 0.62, delay: 0.0, options: .curveEaseOut, animations: {
                label.center = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                label.transform = CGAffineTransform(scaleX: 0.55, y: 0.55).rotated(by: angle)
                label.alpha = 0.0
            }, completion: { _ in
                label.removeFromSuperview()
            })
        }
    }

    @objc private func replyChanged() {
        self.sendButton.isEnabled = !(self.replyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func textFieldDidBeginEditing(_ textField: UITextField) {
        if let sheet = self.sheetPresentationController {
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = .large
            }
        }
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.sendPressed()
        return false
    }

    // The prototype's sample contacts have no chat, so a reply is confirmed and goes no further.
    @objc private func sendPressed() {
        guard self.sendButton.isEnabled else {
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.replyField.text = nil
        self.replyField.resignFirstResponder()
        self.sendButton.isEnabled = false
        UIView.animate(withDuration: 0.2, animations: {
            self.sentLabel.alpha = 1.0
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.presentingViewController == nil {
            TelegramNoteHostWindow.remove()
        }
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        TelegramNoteHostWindow.remove()
    }
}

private final class NoteCardBubbleView: UIView {
    var didLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        self.didLayout?()
    }
}

// One answer of a Note poll. It is a plain button until the vote, then a filled bar with its share of the votes.
private final class PollRowView: UIControl {
    private let fillView = UIView()
    private let titleLabel = UILabel()
    private let percentLabel = UILabel()
    private let checkView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private var fraction: CGFloat = 0.0

    init(title: String, theme: PresentationTheme) {
        super.init(frame: .zero)

        self.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.layer.cornerRadius = 14.0
        self.layer.cornerCurve = .continuous
        self.clipsToBounds = true
        self.heightAnchor.constraint(equalToConstant: 48.0).isActive = true

        self.fillView.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.24)
        self.fillView.isUserInteractionEnabled = false
        self.addSubview(self.fillView)

        self.titleLabel.text = title
        self.titleLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .medium)
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.addSubview(self.titleLabel)

        self.percentLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15.0, weight: .semibold)
        self.percentLabel.textColor = theme.list.itemPrimaryTextColor
        self.percentLabel.textAlignment = .right
        self.percentLabel.alpha = 0.0
        self.addSubview(self.percentLabel)

        self.checkView.tintColor = theme.list.itemAccentColor
        self.checkView.alpha = 0.0
        self.addSubview(self.checkView)

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
        self.accessibilityLabel = title
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        self.fillView.frame = CGRect(x: 0.0, y: 0.0, width: bounds.width * self.fraction, height: bounds.height)
        self.titleLabel.frame = CGRect(x: 16.0, y: 0.0, width: bounds.width - 110.0, height: bounds.height)
        self.percentLabel.frame = CGRect(x: bounds.width - 66.0, y: 0.0, width: 52.0, height: bounds.height)
        self.checkView.frame = CGRect(x: bounds.width - 90.0, y: (bounds.height - 20.0) * 0.5, width: 20.0, height: 20.0)
    }

    func update(percentage: Int?, isChosen: Bool, animated: Bool) {
        self.isEnabled = percentage == nil
        self.fraction = CGFloat(percentage ?? 0) / 100.0
        self.percentLabel.text = percentage.flatMap { "\($0)%" }
        if let percentage {
            self.accessibilityValue = "\(percentage)%"
            self.accessibilityTraits = isChosen ? [.staticText, .selected] : .staticText
        }
        let apply = {
            self.percentLabel.alpha = percentage == nil ? 0.0 : 1.0
            self.checkView.alpha = isChosen ? 1.0 : 0.0
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.0, options: [], animations: apply)
        } else {
            apply()
        }
    }
}
