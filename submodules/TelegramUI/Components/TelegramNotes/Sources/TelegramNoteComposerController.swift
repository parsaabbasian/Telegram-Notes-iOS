import Foundation
import UIKit
import SwiftSignalKit
import TelegramPresentationData

// The Note composer: a native sheet where the text is typed straight into the speech bubble contacts will see.
public final class TelegramNoteComposerController: UIViewController, UITextViewDelegate, UITextFieldDelegate, UIAdaptivePresentationControllerDelegate {
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
    private var audienceDisposable: Disposable?

    private let bubbleView = UIView()
    private let audienceButton = UIButton(type: .system)
    private let timerButton = UIButton(type: .system)
    private let spoilerButton = UIButton(type: .system)
    private let pollButton = UIButton(type: .system)
    private let pollStack = UIStackView()
    private let pollFields = [UITextField(), UITextField()]
    private var options = TelegramNoteOptions()
    private var audiences: [TelegramNoteAudience] = [.contacts, .closeFriends]
    private var isSharing = false

    public static func present(store: TelegramNotesStore, theme: PresentationTheme, windowScene: UIWindowScene) {
        let composer = TelegramNoteComposerController(store: store, theme: theme)
        composer.presentationController?.delegate = composer
        TelegramNoteHostWindow.present(composer, windowScene: windowScene)
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
        self.audienceDisposable?.dispose()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let theme = self.theme
        let accent = theme.list.itemAccentColor
        self.view.backgroundColor = theme.list.blocksBackgroundColor
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
        titleLabel.text = TelegramNotesStrings.string(self.store.accountNote == nil ? "NotesNew" : "NotesEditTitle")
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
        let bubble = self.bubbleView
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

        self.durationLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        self.durationLabel.textColor = theme.list.itemSecondaryTextColor
        self.durationLabel.textAlignment = .center

        if let note = self.store.accountNote {
            self.options = TelegramNoteOptions(period: note.expirationTimestamp - note.timestamp, isSpoiler: note.isSpoiler, pollOptions: note.poll?.options, audience: note.audience)
        }

        let chips = UIStackView(arrangedSubviews: [self.audienceButton, self.timerButton, self.spoilerButton, self.pollButton])
        chips.axis = .horizontal
        chips.spacing = 6.0
        chips.isHidden = !self.store.supportsNoteOptions
        self.audienceButton.showsMenuAsPrimaryAction = true
        // A long folder name gives way first, so the row of chips always fits.
        self.audienceButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.audienceButton.accessibilityLabel = TelegramNotesStrings.string("NotesAudienceHint")
        self.timerButton.showsMenuAsPrimaryAction = true
        self.timerButton.accessibilityLabel = TelegramNotesStrings.string("NotesTimerHint")
        self.spoilerButton.addTarget(self, action: #selector(self.spoilerPressed), for: .touchUpInside)
        self.pollButton.addTarget(self, action: #selector(self.pollPressed), for: .touchUpInside)

        self.pollStack.axis = .vertical
        self.pollStack.spacing = 8.0
        for (index, field) in self.pollFields.enumerated() {
            field.delegate = self
            field.font = UIFont.systemFont(ofSize: 16.0)
            field.textColor = theme.list.itemPrimaryTextColor
            field.tintColor = accent
            field.backgroundColor = theme.list.itemBlocksBackgroundColor
            field.layer.cornerRadius = 12.0
            field.layer.cornerCurve = .continuous
            field.attributedPlaceholder = NSAttributedString(string: TelegramNotesStrings.string(index == 0 ? "NotesPollOption1" : "NotesPollOption2"), attributes: [.foregroundColor: theme.list.itemPlaceholderTextColor])
            field.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 40.0))
            field.leftViewMode = .always
            field.returnKeyType = .done
            field.text = self.options.pollOptions.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            field.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
            field.addTarget(self, action: #selector(self.pollFieldChanged), for: .editingChanged)
            self.pollStack.addArrangedSubview(field)
        }

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

        let lowerStack = UIStackView(arrangedSubviews: [self.durationLabel, chips, self.pollStack, self.emojiStack, self.statusLabel, self.deleteButton])
        lowerStack.axis = .vertical
        lowerStack.alignment = .center
        lowerStack.spacing = 12.0

        for view in [header, bubble, dots, lowerStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        let guide = self.view.layoutMarginsGuide
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            header.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 16.0),
            bubble.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24.0),
            bubble.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            bubble.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.92),
            dots.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 6.0),
            dots.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 42.0),
            dots.heightAnchor.constraint(equalToConstant: 22.0),
            dots.widthAnchor.constraint(equalToConstant: 26.0),
            lowerStack.topAnchor.constraint(equalTo: dots.bottomAnchor, constant: 6.0),
            lowerStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            lowerStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            chips.widthAnchor.constraint(lessThanOrEqualTo: lowerStack.widthAnchor),
            self.pollStack.widthAnchor.constraint(equalTo: lowerStack.widthAnchor, multiplier: 0.92),
            self.statusLabel.widthAnchor.constraint(equalTo: lowerStack.widthAnchor)
        ])

        self.audienceDisposable = (self.store.audienceOptions()
        |> deliverOnMainQueue).start(next: { [weak self] audiences in
            guard let self else {
                return
            }
            self.audiences = audiences
            if !audiences.contains(self.options.audience) {
                self.audiences.append(self.options.audience)
            }
            self.updateOptionControls()
        })
        self.updateOptionControls()

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
            TelegramNoteHostWindow.remove()
        }
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        TelegramNoteHostWindow.remove()
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Focused here so the keyboard rises with the sheet, not after it.
        self.textView.becomeFirstResponder()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.textView.becomeFirstResponder()
#if DEBUG
        self.runDemoScriptIfNeeded()
#endif
    }

#if DEBUG
    // Records the concept video at an even pace. Documents/demo-script.txt holds the Note on its first line, then
    // one option per line: spoiler, timer=<seconds> or audience=<name>.
    private func runDemoScriptIfNeeded() {
        guard TelegramNotesStore.isDemoMode, let script = try? String(contentsOfFile: NSHomeDirectory() + "/Documents/demo-script.txt", encoding: .utf8) else {
            return
        }
        var lines = script.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.isEmpty {
            return
        }
        let characters = Array(lines.removeFirst())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.typeDemoCharacter(characters, index: 0, steps: lines)
        }
    }

    private func typeDemoCharacter(_ characters: [Character], index: Int, steps: [String]) {
        if index >= characters.count {
            self.runDemoStep(steps, index: 0)
            return
        }
        self.textView.insertText(String(characters[index]))
        let pace: [Double] = [0.14, 0.18, 0.12, 0.2, 0.15]
        DispatchQueue.main.asyncAfter(deadline: .now() + pace[index % pace.count]) { [weak self] in
            self?.typeDemoCharacter(characters, index: index + 1, steps: steps)
        }
    }

    private func runDemoStep(_ steps: [String], index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else {
                return
            }
            if index >= steps.count {
                self.pressShareForDemo()
                return
            }
            let step = steps[index]
            if step == "spoiler" {
                self.spoilerPressed()
            } else if step.hasPrefix("timer="), let period = Int32(step.dropFirst(6)) {
                self.options.period = period
                self.updateOptionControls()
            } else if step.hasPrefix("audience="), let audience = self.audiences.first(where: { $0.title == step.dropFirst(9) }) {
                self.options.audience = audience
                self.updateOptionControls()
            }
            self.runDemoStep(steps, index: index + 1)
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
#endif

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
        self.shareButton.isEnabled = TelegramNoteCaption.validated(self.textView.text) != nil && self.options.isValid && self.store.publishState != .publishing
    }

    private func textDidChange() {
        let length = TelegramNoteCaption.length(self.textView.text)
        self.placeholderLabel.isHidden = !self.textView.text.isEmpty
        // Centered text puts the cursor in the middle of the placeholder, so it stays hidden until there is text.
        self.textView.tintColor = self.textView.text.isEmpty ? .clear : self.theme.list.itemAccentColor
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

    private func timerTitle(period: Int32, short: Bool) -> String {
        switch period {
        case 1 * 60 * 60:
            return short ? "1h" : TelegramNotesStrings.string("NotesTimer1h")
        case 8 * 60 * 60:
            return short ? "8h" : TelegramNotesStrings.string("NotesTimer8h")
        case 72 * 60 * 60:
            return short ? "3d" : TelegramNotesStrings.string("NotesTimer72h")
        default:
            return short ? "24h" : TelegramNotesStrings.string("NotesTimer24h")
        }
    }

    private func configureChip(_ button: UIButton, symbol: String, title: String, isSelected: Bool) {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold))
        configuration.imagePadding = 5.0
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = isSelected ? self.theme.list.itemAccentColor : self.theme.list.itemBlocksBackgroundColor
        configuration.baseForegroundColor = isSelected ? self.theme.list.itemCheckColors.foregroundColor : self.theme.list.itemPrimaryTextColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7.0, leading: 11.0, bottom: 7.0, trailing: 11.0)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
            return attributes
        }
        button.configuration = configuration
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    private func updateOptionControls() {
        let options = self.options
        let isFolder: Bool
        if case .folder = options.audience {
            isFolder = true
        } else {
            isFolder = false
        }
        self.configureChip(self.audienceButton, symbol: isFolder ? "folder.fill" : (options.audience == .closeFriends ? "star.fill" : "person.2.fill"), title: options.audience.title, isSelected: options.audience != .contacts)
        self.configureChip(self.timerButton, symbol: "timer", title: self.timerTitle(period: options.period, short: true), isSelected: options.period != TelegramNoteCaption.period)
        self.configureChip(self.spoilerButton, symbol: "sparkles", title: TelegramNotesStrings.string("NotesSpoiler"), isSelected: options.isSpoiler)
        self.configureChip(self.pollButton, symbol: "chart.bar.fill", title: TelegramNotesStrings.string("NotesPoll"), isSelected: options.pollOptions != nil)

        self.audienceButton.menu = UIMenu(title: TelegramNotesStrings.string("NotesAudienceHint"), children: self.audiences.map { audience in
            return UIAction(title: audience.title, state: audience == options.audience ? .on : .off, handler: { [weak self] _ in
                self?.options.audience = audience
                self?.optionChanged()
            })
        })
        self.timerButton.menu = UIMenu(title: TelegramNotesStrings.string("NotesTimerHint"), children: TelegramNoteOptions.periods.map { period in
            return UIAction(title: self.timerTitle(period: period, short: false), state: period == options.period ? .on : .off, handler: { [weak self] _ in
                self?.options.period = period
                self?.optionChanged()
            })
        })

        var summary = "\(options.audience.title) · \(self.timerTitle(period: options.period, short: false))"
        if options.isSpoiler {
            summary += " · \(TelegramNotesStrings.string("NotesSpoilerHint"))"
        }
        self.durationLabel.text = summary
        self.pollStack.isHidden = options.pollOptions == nil
        self.updateShareButton()
    }

    private func optionChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
        self.updateOptionControls()
    }

    // A spoiler hides the text and a poll asks about it, so a Note is one or the other.
    @objc private func spoilerPressed() {
        self.options.isSpoiler.toggle()
        if self.options.isSpoiler {
            self.options.pollOptions = nil
        }
        self.optionChanged()
    }

    @objc private func pollPressed() {
        if self.options.pollOptions == nil {
            self.options.isSpoiler = false
            self.options.pollOptions = self.pollFields.map { $0.text ?? "" }
            self.optionChanged()
            self.pollFields[0].becomeFirstResponder()
        } else {
            self.options.pollOptions = nil
            self.optionChanged()
            self.textView.becomeFirstResponder()
        }
    }

    @objc private func pollFieldChanged() {
        self.options.pollOptions = self.pollFields.map { $0.text ?? "" }
        self.updateShareButton()
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let updated = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        return updated.utf16.count <= TelegramNoteOptions.maxPollOptionLength || string.isEmpty
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === self.pollFields[0] {
            self.pollFields[1].becomeFirstResponder()
        } else {
            self.textView.becomeFirstResponder()
        }
        return false
    }

    @objc private func sharePressed() {
        // The keyboard shortcut reaches this without the button, and a second tap can land while the sheet closes.
        guard self.shareButton.isEnabled, !self.isSharing else {
            return
        }
        self.isSharing = true
        let text = self.textView.text ?? ""
        let options = self.options
        self.store.publish(text: text, theme: self.theme, completion: { [weak self] success in
            guard let self else {
                return
            }
            if !success {
                self.isSharing = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else if TelegramNotesStore.isDemoMode, let validated = TelegramNoteCaption.validated(text) {
                self.flyNoteToAvatar(text: validated, options: options)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.dismiss(animated: true)
            }
        })
    }

    // The Note leaves the sheet as a bubble, shrinks on an arc into the row and lands on the avatar.
    private func flyNoteToAvatar(text: String, options: TelegramNoteOptions) {
        let store = self.store
        let land = {
            store.landDemoNote(text: text, options: options)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        guard !UIAccessibility.isReduceMotionEnabled, let window = self.view.window, let target = store.accountBubbleView, target.window != nil else {
            self.dismiss(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: land)
            return
        }

        let startFrame = self.bubbleView.convert(self.bubbleView.bounds, to: nil)
        let targetFrame = target.convert(target.bounds, to: nil)
        let bubbleFont = UIFont.systemFont(ofSize: 24.0, weight: .semibold)
        let rowFontSize: CGFloat = 10.5

        let flying = UIView(frame: startFrame)
        flying.isUserInteractionEnabled = false
        flying.layer.shadowColor = UIColor.black.cgColor
        flying.layer.shadowOpacity = self.theme.overallDarkAppearance ? 0.5 : 0.2
        flying.layer.shadowRadius = 12.0
        flying.layer.shadowOffset = CGSize(width: 0.0, height: 5.0)

        let clip = UIView(frame: flying.bounds)
        clip.backgroundColor = self.bubbleView.backgroundColor
        clip.layer.cornerRadius = 26.0
        clip.layer.cornerCurve = .continuous
        clip.clipsToBounds = true
        flying.addSubview(clip)

        let label = UILabel()
        label.text = text
        label.font = bubbleFont
        label.textColor = self.theme.list.itemPrimaryTextColor
        label.textAlignment = .center
        label.numberOfLines = 3
        let labelSize = label.sizeThatFits(CGSize(width: startFrame.width - 40.0, height: startFrame.height))
        label.bounds = CGRect(origin: CGPoint(), size: labelSize)
        label.center = CGPoint(x: startFrame.width * 0.5, y: startFrame.height * 0.5)
        clip.addSubview(label)
        window.addSubview(flying)

        self.bubbleView.alpha = 0.0
        TelegramNoteHostWindow.isHoldingForFlight = true
        self.dismiss(animated: true)

        let rowTextWidth = ceil((text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: rowFontSize, weight: .medium)]).width)
        let endSize = CGSize(width: min(68.0, max(44.0, rowTextWidth + 10.0)), height: targetFrame.height)
        let endFrame = CGRect(x: targetFrame.midX - endSize.width * 0.5, y: targetFrame.midY - endSize.height * 0.5, width: endSize.width, height: endSize.height)
        let textScale = rowFontSize / bubbleFont.pointSize

        let arc = CAKeyframeAnimation(keyPath: "position.y")
        arc.values = [0.0, -34.0, 0.0]
        arc.keyTimes = [0.0, 0.45, 1.0]
        arc.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        arc.isAdditive = true
        arc.duration = 0.62
        flying.layer.add(arc, forKey: "arc")

        let animator = UIViewPropertyAnimator(duration: 0.62, controlPoint1: CGPoint(x: 0.34, y: 0.0), controlPoint2: CGPoint(x: 0.16, y: 1.0), animations: {
            flying.frame = endFrame
            clip.frame = CGRect(origin: CGPoint(), size: endFrame.size)
            clip.layer.cornerRadius = endFrame.height * 0.5
            label.center = CGPoint(x: endFrame.width * 0.5, y: endFrame.height * 0.5)
            label.transform = CGAffineTransform(scaleX: textScale, y: textScale)
        })
        animator.addCompletion { _ in
            land()
            UIView.animate(withDuration: 0.14, delay: 0.03, options: [], animations: {
                flying.alpha = 0.0
            }, completion: { _ in
                flying.removeFromSuperview()
                TelegramNoteHostWindow.endFlight()
            })
        }
        animator.startAnimation()
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
