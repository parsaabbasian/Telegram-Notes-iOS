import Foundation
import UIKit
import SwiftSignalKit
import TelegramPresentationData

// The Note composer: a native sheet where the text is typed straight into the speech bubble contacts will see.
public final class TelegramNoteComposerController: UIViewController, UITextViewDelegate, UIAdaptivePresentationControllerDelegate {
    private static let emojiShortcuts = ["😊", "🔥", "❤️", "🎉"]

    private let store: TelegramNotesStore
    private let theme: PresentationTheme

    private let washLayer = CAGradientLayer()
    private let ringTrackLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let countLabel = UILabel()
    private let durationLabel = UILabel()
    private let statusLabel = UILabel()
    private let emojiStack = UIStackView()
    private let shareButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var stateDisposable: Disposable?

    // Telegram's own window routes touches only to its node hierarchy, so a UIKit sheet presented inside it never
    // receives them. The composer gets a window of its own, which goes away when the sheet is dismissed.
    private static var hostWindow: UIWindow?
    
    public static func present(store: TelegramNotesStore, theme: PresentationTheme, windowScene: UIWindowScene) {
        if self.hostWindow != nil {
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .clear
        window.windowLevel = .normal + 1.0
        let rootController = UIViewController()
        rootController.view.backgroundColor = .clear
        window.rootViewController = rootController
        window.makeKeyAndVisible()
        self.hostWindow = window
        
        let composer = TelegramNoteComposerController(store: store, theme: theme)
        composer.presentationController?.delegate = composer
        rootController.present(composer, animated: true)
    }
    
    private static func removeHostWindow() {
        self.hostWindow?.isHidden = true
        self.hostWindow = nil
    }
    
    public init(store: TelegramNotesStore, theme: PresentationTheme) {
        self.store = store
        self.theme = theme
        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .pageSheet
        if let sheet = self.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28.0
            sheet.selectedDetentIdentifier = .large
        }
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.stateDisposable?.dispose()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let theme = self.theme
        let accent = theme.list.itemAccentColor
        self.view.backgroundColor = theme.list.plainBackgroundColor
        self.view.accessibilityLabel = TelegramNotesStrings.string("NotesTitle")
        self.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light

        // A soft wash of the accent colour behind the bubble.
        self.washLayer.colors = [accent.withAlphaComponent(0.22).cgColor, accent.withAlphaComponent(0.0).cgColor]
        self.view.layer.insertSublayer(self.washLayer, at: 0)

        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = TelegramNotesStrings.string("NotesCancel")
        cancelConfiguration.baseForegroundColor = theme.list.itemPrimaryTextColor
        self.cancelButton.configuration = cancelConfiguration
        self.cancelButton.addTarget(self, action: #selector(self.cancelPressed), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = TelegramNotesStrings.string(self.store.accountNote == nil ? "NotesNew" : "NotesEdit")
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = theme.list.itemPrimaryTextColor
        titleLabel.accessibilityTraits = .header

        var shareConfiguration = UIButton.Configuration.filled()
        shareConfiguration.title = TelegramNotesStrings.string("NotesShare")
        shareConfiguration.cornerStyle = .capsule
        shareConfiguration.baseBackgroundColor = accent
        shareConfiguration.baseForegroundColor = theme.list.itemCheckColors.foregroundColor
        shareConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7.0, leading: 16.0, bottom: 7.0, trailing: 16.0)
        self.shareButton.configuration = shareConfiguration
        self.shareButton.addTarget(self, action: #selector(self.sharePressed), for: .touchUpInside)

        let header = UIView()
        for view in [self.cancelButton, titleLabel, self.shareButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        NSLayoutConstraint.activate([
            self.cancelButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: -12.0),
            self.cancelButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            self.shareButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            self.shareButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(equalToConstant: 44.0)
        ])

        // The Note itself: what you type is exactly what your contacts read.
        let bubble = UIView()
        bubble.backgroundColor = theme.list.itemBlocksBackgroundColor
        bubble.layer.cornerRadius = 26.0
        bubble.layer.cornerCurve = .continuous
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = theme.overallDarkAppearance ? 0.4 : 0.1
        bubble.layer.shadowRadius = 18.0
        bubble.layer.shadowOffset = CGSize(width: 0.0, height: 8.0)

        self.textView.delegate = self
        self.textView.backgroundColor = .clear
        self.textView.font = UIFont.systemFont(ofSize: 24.0, weight: .semibold)
        self.textView.textAlignment = .center
        self.textView.isScrollEnabled = false
        self.textView.textColor = theme.list.itemPrimaryTextColor
        self.textView.tintColor = accent
        self.textView.textContainerInset = .zero
        self.textView.accessibilityLabel = TelegramNotesStrings.string("NotesCompose")
        self.textView.text = self.store.accountNote?.text ?? ""
        if TelegramNotesStore.isDemoMode {
            // The scripted Note types itself, so keyboard suggestions would not follow it.
            self.textView.autocorrectionType = .no
            self.textView.spellCheckingType = .no
        }

        self.placeholderLabel.text = TelegramNotesStrings.string("NotesCompose")
        self.placeholderLabel.font = UIFont.systemFont(ofSize: 24.0, weight: .semibold)
        self.placeholderLabel.textAlignment = .center
        self.placeholderLabel.adjustsFontSizeToFitWidth = true
        self.placeholderLabel.textColor = theme.list.itemPlaceholderTextColor
        self.placeholderLabel.isAccessibilityElement = false

        for view in [self.textView, self.placeholderLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bubble.addSubview(view)
        }
        NSLayoutConstraint.activate([
            self.textView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 20.0),
            self.textView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -20.0),
            self.textView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 26.0),
            self.textView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -26.0),
            self.textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 34.0),
            self.placeholderLabel.leadingAnchor.constraint(equalTo: self.textView.leadingAnchor),
            self.placeholderLabel.trailingAnchor.constraint(equalTo: self.textView.trailingAnchor),
            self.placeholderLabel.topAnchor.constraint(equalTo: self.textView.topAnchor)
        ])

        // Two shrinking dots tie the bubble to its author, like a thought.
        let dots = UIView()
        for (x, side) in [(0.0, 13.0), (17.0, 7.0)] as [(CGFloat, CGFloat)] {
            let dot = UIView(frame: CGRect(x: x, y: x * 0.45, width: side, height: side))
            dot.backgroundColor = theme.list.itemBlocksBackgroundColor
            dot.layer.cornerRadius = side * 0.5
            dots.addSubview(dot)
        }
        dots.isAccessibilityElement = false

        self.durationLabel.text = TelegramNotesStrings.string("NotesAudience")
        self.durationLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        self.durationLabel.textColor = theme.list.itemSecondaryTextColor
        self.durationLabel.textAlignment = .center

        self.emojiStack.axis = .horizontal
        self.emojiStack.spacing = 10.0
        self.emojiStack.alignment = .center
        self.emojiStack.accessibilityLabel = TelegramNotesStrings.string("NotesAddEmoji")
        self.emojiStack.shouldGroupAccessibilityChildren = true
        for emoji in TelegramNoteComposerController.emojiShortcuts {
            let button = UIButton(type: .system)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 24.0)
            button.backgroundColor = theme.list.itemBlocksBackgroundColor
            button.layer.cornerRadius = 24.0
            button.accessibilityLabel = "\(TelegramNotesStrings.string("NotesAddEmoji")) \(emoji)"
            button.addTarget(self, action: #selector(self.emojiPressed(_:)), for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 48.0).isActive = true
            button.heightAnchor.constraint(equalToConstant: 48.0).isActive = true
            self.emojiStack.addArrangedSubview(button)
        }

        // Character ring: quiet until the last ten characters.
        let ringView = UIView()
        ringView.translatesAutoresizingMaskIntoConstraints = false
        ringView.widthAnchor.constraint(equalToConstant: 34.0).isActive = true
        ringView.heightAnchor.constraint(equalToConstant: 34.0).isActive = true
        let ringPath = UIBezierPath(arcCenter: CGPoint(x: 17.0, y: 17.0), radius: 14.0, startAngle: -.pi * 0.5, endAngle: .pi * 1.5, clockwise: true).cgPath
        for layer in [self.ringTrackLayer, self.ringLayer] {
            layer.path = ringPath
            layer.fillColor = nil
            layer.lineWidth = 3.0
            layer.lineCap = .round
            ringView.layer.addSublayer(layer)
        }
        self.ringTrackLayer.strokeColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.25).cgColor
        self.countLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)
        self.countLabel.textAlignment = .center
        self.countLabel.frame = CGRect(x: 0.0, y: 0.0, width: 34.0, height: 34.0)
        ringView.addSubview(self.countLabel)
        self.emojiStack.addArrangedSubview(ringView)

        self.statusLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.statusLabel.isHidden = true

        var deleteConfiguration = UIButton.Configuration.plain()
        deleteConfiguration.title = TelegramNotesStrings.string("NotesDelete")
        deleteConfiguration.baseForegroundColor = theme.list.itemDestructiveColor
        self.deleteButton.configuration = deleteConfiguration
        self.deleteButton.isHidden = self.store.accountNote == nil
        self.deleteButton.addTarget(self, action: #selector(self.deletePressed), for: .touchUpInside)

        for view in [header, bubble, dots, self.durationLabel, self.emojiStack, self.statusLabel, self.deleteButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        let guide = self.view.layoutMarginsGuide
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            header.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 16.0),
            bubble.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 32.0),
            bubble.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            bubble.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.92),
            dots.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 6.0),
            dots.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 42.0),
            dots.heightAnchor.constraint(equalToConstant: 22.0),
            dots.widthAnchor.constraint(equalToConstant: 26.0),
            self.durationLabel.topAnchor.constraint(equalTo: dots.bottomAnchor, constant: 8.0),
            self.durationLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.emojiStack.topAnchor.constraint(equalTo: self.durationLabel.bottomAnchor, constant: 18.0),
            self.emojiStack.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.statusLabel.topAnchor.constraint(equalTo: self.emojiStack.bottomAnchor, constant: 10.0),
            self.statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            self.statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            self.deleteButton.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 2.0),
            self.deleteButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        ])

        self.stateDisposable = (self.store.publishStateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.updateState(state)
        })

        self.textDidChange()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.washLayer.frame = CGRect(x: 0.0, y: 0.0, width: self.view.bounds.width, height: 300.0)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.presentingViewController == nil {
            TelegramNoteComposerController.removeHostWindow()
        }
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        TelegramNoteComposerController.removeHostWindow()
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.textView.becomeFirstResponder()
        self.runDemoScriptIfNeeded()
    }

    // Records the concept video at an even pace: Documents/demo-script.txt holds the Note to type and share.
    private func runDemoScriptIfNeeded() {
        guard TelegramNotesStore.isDemoMode, let script = try? String(contentsOfFile: NSHomeDirectory() + "/Documents/demo-script.txt", encoding: .utf8) else {
            return
        }
        let characters = Array(script.trimmingCharacters(in: .whitespacesAndNewlines))
        if characters.isEmpty {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.typeDemoCharacter(characters, index: 0)
        }
    }

    private func typeDemoCharacter(_ characters: [Character], index: Int) {
        if index >= characters.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.pressShareForDemo()
            }
            return
        }
        self.textView.insertText(String(characters[index]))
        let pace: [Double] = [0.14, 0.18, 0.12, 0.2, 0.15]
        DispatchQueue.main.asyncAfter(deadline: .now() + pace[index % pace.count]) { [weak self] in
            self?.typeDemoCharacter(characters, index: index + 1)
        }
    }

    private func pressShareForDemo() {
        UIView.animate(withDuration: 0.12, animations: {
            self.shareButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }, completion: { _ in
            UIView.animate(withDuration: 0.16, animations: {
                self.shareButton.transform = .identity
            })
            self.sharePressed()
        })
    }

    private func updateState(_ state: TelegramNotesStore.PublishState) {
        switch state {
        case .idle:
            self.statusLabel.isHidden = true
        case .publishing:
            self.statusLabel.isHidden = false
            self.statusLabel.textColor = self.theme.list.itemSecondaryTextColor
            self.statusLabel.text = TelegramNotesStrings.string("NotesPublishing")
        case .unavailable:
            self.statusLabel.isHidden = false
            self.statusLabel.textColor = self.theme.list.itemDestructiveColor
            self.statusLabel.text = TelegramNotesStrings.string("NotesUnavailable")
            UIAccessibility.post(notification: .announcement, argument: self.statusLabel.text)
        case .failed:
            self.statusLabel.isHidden = false
            self.statusLabel.textColor = self.theme.list.itemDestructiveColor
            self.statusLabel.text = TelegramNotesStrings.string("NotesPublishFailed")
            UIAccessibility.post(notification: .announcement, argument: self.statusLabel.text)
        }
        let isPublishing = state == .publishing
        self.textView.isEditable = !isPublishing
        self.cancelButton.isEnabled = !isPublishing
        self.deleteButton.isEnabled = !isPublishing
        self.isModalInPresentation = isPublishing
        self.updateShareButton()
    }

    private func updateShareButton() {
        self.shareButton.isEnabled = TelegramNoteCaption.validated(self.textView.text) != nil && self.store.publishState != .publishing
    }

    private func textDidChange() {
        let length = TelegramNoteCaption.length(self.textView.text)
        self.placeholderLabel.isHidden = !self.textView.text.isEmpty
        self.updateShareButton()
        if self.store.publishState == .failed || self.store.publishState == .unavailable {
            self.updateState(.idle)
        }

        let fraction = min(1.0, CGFloat(length) / CGFloat(TelegramNoteCaption.maxLength))
        let remaining = TelegramNoteCaption.maxLength - length
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.ringLayer.strokeEnd = fraction
        self.ringLayer.strokeColor = (remaining <= 10 ? self.theme.list.itemDestructiveColor : self.theme.list.itemAccentColor).cgColor
        CATransaction.commit()
        self.countLabel.text = remaining <= 10 ? "\(remaining)" : nil
        self.countLabel.textColor = self.theme.list.itemDestructiveColor
    }

    public func textViewDidChange(_ textView: UITextView) {
        self.textDidChange()
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text as NSString
        let updated = current.replacingCharacters(in: range, with: text)
        return TelegramNoteCaption.length(updated) <= TelegramNoteCaption.maxLength || text.isEmpty
    }

    @objc private func emojiPressed(_ sender: UIButton) {
        guard let emoji = sender.title(for: .normal), self.textView.isEditable else {
            return
        }
        // Inserted only when the whole UTF-16 sequence fits in what is left of the limit.
        let selected = self.textView.selectedRange
        let remaining = TelegramNoteCaption.maxLength - TelegramNoteCaption.length(self.textView.text) + selected.length
        guard emoji.utf16.count <= remaining else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        self.textView.replace(self.textView.selectedTextRange ?? self.textView.textRange(from: self.textView.endOfDocument, to: self.textView.endOfDocument)!, withText: emoji)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func sharePressed() {
        self.store.publish(text: self.textView.text, theme: self.theme, completion: { [weak self] success in
            guard let self else {
                return
            }
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.dismiss(animated: true)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        })
    }

    @objc private func deletePressed() {
        self.store.deleteAccountNote()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.dismiss(animated: true)
    }

    @objc private func cancelPressed() {
        self.dismiss(animated: true)
    }

    // Hardware keyboard: Escape closes, Cmd+Return shares.
    override public var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(self.cancelPressed)),
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(self.sharePressed)),
            UIKeyCommand(input: "\r", modifierFlags: .control, action: #selector(self.sharePressed))
        ]
    }
}
