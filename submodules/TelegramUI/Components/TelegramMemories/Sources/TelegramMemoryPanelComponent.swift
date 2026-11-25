import Foundation
import UIKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext

// The card above the chat list that offers today's memory. It sits where Telegram shows birthday reminders.
public final class TelegramMemoryPanelComponent: Component {
    public let context: AccountContext
    public let theme: PresentationTheme
    public let memory: TelegramMemory
    public let openAction: (UIView) -> Void
    public let dismissAction: () -> Void

    public init(context: AccountContext, theme: PresentationTheme, memory: TelegramMemory, openAction: @escaping (UIView) -> Void, dismissAction: @escaping () -> Void) {
        self.context = context
        self.theme = theme
        self.memory = memory
        self.openAction = openAction
        self.dismissAction = dismissAction
    }

    public static func ==(lhs: TelegramMemoryPanelComponent, rhs: TelegramMemoryPanelComponent) -> Bool {
        return lhs.context === rhs.context && lhs.theme === rhs.theme && lhs.memory == rhs.memory
    }

    public final class View: UIView {
        private let thumbnail = TelegramMemoryImageView()
        private let thumbnailBorder = UIView()
        private let badge = UILabel()
        private let titleLabel = UILabel()
        private let subtitleLabel = UILabel()
        private let closeButton = UIButton(type: .system)
        private let separator = UIView()
        private var component: TelegramMemoryPanelComponent?

        public override init(frame: CGRect) {
            super.init(frame: frame)
            self.thumbnail.layer.cornerRadius = 11.0
            self.thumbnail.layer.cornerCurve = .continuous
            self.addSubview(self.thumbnail)
            self.thumbnailBorder.isUserInteractionEnabled = false
            self.thumbnailBorder.layer.cornerRadius = 13.0
            self.thumbnailBorder.layer.cornerCurve = .continuous
            self.thumbnailBorder.layer.borderWidth = 2.0
            self.addSubview(self.thumbnailBorder)
            self.badge.font = UIFont.systemFont(ofSize: 10.0, weight: .bold)
            self.badge.textColor = .white
            self.badge.textAlignment = .center
            self.badge.layer.cornerRadius = 8.0
            self.badge.clipsToBounds = true
            self.addSubview(self.badge)
            self.titleLabel.font = Font.semibold(15.0)
            self.subtitleLabel.font = Font.regular(14.0)
            self.addSubview(self.titleLabel)
            self.addSubview(self.subtitleLabel)
            self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)), for: .normal)
            self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
            self.addSubview(self.closeButton)
            self.addSubview(self.separator)
            self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped)))
            makeTouchable(self)
            makeTouchable(self.closeButton)
            self.isAccessibilityElement = false
            self.titleLabel.isAccessibilityElement = false
            self.subtitleLabel.isAccessibilityElement = false
        }

        required public init?(coder: NSCoder) {
            preconditionFailure()
        }

        @objc private func tapped() {
            self.component?.openAction(self.thumbnail)
        }

        @objc private func closePressed() {
            self.component?.dismissAction()
        }

        func update(component: TelegramMemoryPanelComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            self.component = component
            let theme = component.theme
            let memory = component.memory
            if let first = memory.items.first {
                self.thumbnail.update(context: component.context, item: first, fullSize: false)
            }
            self.thumbnailBorder.layer.borderColor = theme.list.itemAccentColor.cgColor
            self.badge.text = memory.yearsAgo == 1 ? "1Y" : "\(memory.yearsAgo)Y"
            self.badge.backgroundColor = theme.list.itemAccentColor
            self.titleLabel.text = memory.title
            self.titleLabel.textColor = theme.rootController.navigationBar.primaryTextColor
            self.subtitleLabel.text = memory.subtitle
            self.subtitleLabel.textColor = theme.rootController.navigationBar.secondaryTextColor
            self.closeButton.tintColor = theme.rootController.navigationBar.secondaryTextColor
            self.closeButton.accessibilityLabel = TelegramMemoriesStrings.string("MemoriesHideToday")
            self.separator.backgroundColor = theme.rootController.navigationBar.separatorColor
            self.accessibilityLabel = memory.title + ", " + memory.subtitle

            let height: CGFloat = 64.0
            let side: CGFloat = 46.0
            let thumbnailFrame = CGRect(x: 16.0, y: (height - side) * 0.5, width: side, height: side)
            self.thumbnail.frame = thumbnailFrame
            self.thumbnailBorder.frame = thumbnailFrame.insetBy(dx: -3.0, dy: -3.0)
            let badgeSize = CGSize(width: max(22.0, self.badge.intrinsicContentSize.width + 8.0), height: 16.0)
            self.badge.frame = CGRect(x: thumbnailFrame.maxX - badgeSize.width + 6.0, y: thumbnailFrame.maxY - badgeSize.height + 5.0, width: badgeSize.width, height: badgeSize.height)
            let textX = thumbnailFrame.maxX + 14.0
            let closeSide: CGFloat = 44.0
            let textWidth = max(0.0, availableSize.width - textX - closeSide - 6.0)
            self.titleLabel.frame = CGRect(x: textX, y: 12.0, width: textWidth, height: 20.0)
            self.subtitleLabel.frame = CGRect(x: textX, y: 33.0, width: textWidth, height: 19.0)
            self.closeButton.frame = CGRect(x: availableSize.width - closeSide - 4.0, y: (height - closeSide) * 0.5, width: closeSide, height: closeSide)
            self.separator.frame = CGRect(x: 0.0, y: height - UIScreenPixel, width: availableSize.width, height: UIScreenPixel)
            return CGSize(width: availableSize.width, height: height)
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
