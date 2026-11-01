import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PhotoResources
import AvatarNode

final class ExploreTileCell: UICollectionViewCell {
    static let reuseIdentifier = "ExploreTileCell"

    private let avatarNode = AvatarNode(font: UIFont.systemFont(ofSize: 17.0, weight: .semibold))
    private let formatLabel = UILabel()
    private let footerLine = UIView()
    private let arrowView = UIImageView(image: UIImage(systemName: "arrow.up.right"))
    private let engagementLabel = UILabel()
    private let imageNode = TransformImageNode()
    private let textLabel = UILabel()
    private let channelLabel = UILabel()
    private let bottomGradient = CAGradientLayer()
    private let durationLabel = UILabel()
    private let viewsLabel = UILabel()
    private let albumBadge = UIImageView()
    private let albumLabel = UILabel()

    private var isTextPost = false
    private let dateLabel = UILabel()
    private let readingHint = UILabel()
    private var postId: EngineMessage.Id?
    private var imageSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.contentView.clipsToBounds = true
        self.contentView.layer.cornerRadius = 24.0
        self.contentView.layer.cornerCurve = .continuous
        self.contentView.layer.borderWidth = 0.5
        self.contentView.addSubview(self.avatarNode.view)
        self.formatLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .bold)
        self.formatLabel.layer.cornerRadius = 8.0
        self.formatLabel.clipsToBounds = true
        self.formatLabel.textAlignment = .center
        self.contentView.addSubview(self.formatLabel)
        self.contentView.addSubview(self.footerLine)
        self.contentView.addSubview(self.arrowView)
        self.arrowView.contentMode = .scaleAspectFit
        self.engagementLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        self.contentView.addSubview(self.engagementLabel)
        self.imageNode.view.layer.cornerRadius = 16.0
        self.imageNode.view.clipsToBounds = true
        self.dateLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        self.readingHint.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.contentView.addSubview(self.dateLabel)
        self.contentView.addSubview(self.readingHint)
        self.contentView.addSubview(self.imageNode.view)
        self.textLabel.numberOfLines = 0
        self.textLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.textLabel)
        self.channelLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        self.channelLabel.numberOfLines = 1
        self.contentView.addSubview(self.channelLabel)

        self.bottomGradient.colors = [UIColor(white: 0.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.45).cgColor]
        self.contentView.layer.addSublayer(self.bottomGradient)

        for label in [self.durationLabel, self.viewsLabel, self.albumLabel] {
            label.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .semibold)
            label.textColor = .white
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.4
            label.layer.shadowRadius = 2.0
            label.layer.shadowOffset = .zero
            self.contentView.addSubview(label)
        }
        self.albumBadge.image = UIImage(systemName: "square.on.square.fill")
        self.albumBadge.tintColor = .white
        self.albumBadge.contentMode = .scaleAspectFit
        self.contentView.addSubview(self.albumBadge)

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    override var isHighlighted: Bool {
        didSet {
            self.contentView.alpha = self.isHighlighted ? 0.7 : 1.0
        }
    }

    func update(context: AccountContext, theme: PresentationTheme, post: ExplorePost, isLarge: Bool) {
        self.contentView.backgroundColor = theme.list.mediaPlaceholderColor

        let isText: Bool
        if case .text = post.kind { isText = true } else { isText = false }
        self.imageNode.view.isHidden = isText
        self.textLabel.isHidden = false
        self.isTextPost = isText
        self.channelLabel.isHidden = false
        self.textLabel.textColor = theme.list.itemPrimaryTextColor
        self.channelLabel.textColor = theme.list.itemPrimaryTextColor
        self.textLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: isText ? 19.0 : 16.0, weight: isText ? .medium : .regular))
        self.textLabel.adjustsFontForContentSizeCategory = true
        self.textLabel.numberOfLines = isText ? 6 : 3
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.08).cgColor
        self.avatarNode.setPeer(context: context, theme: theme, peer: post.peer, displayDimensions: CGSize(width: 42.0, height: 42.0))
        self.dateLabel.textColor = theme.list.itemSecondaryTextColor
        self.readingHint.textColor = theme.list.itemAccentColor
        self.readingHint.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
        self.arrowView.tintColor = theme.list.itemAccentColor
        self.footerLine.backgroundColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.07)
        self.engagementLabel.textColor = theme.list.itemSecondaryTextColor
        self.formatLabel.textColor = theme.list.itemAccentColor
        self.formatLabel.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.09)
        let readMinutes = max(1, post.message.text.split(whereSeparator: { $0.isWhitespace }).count / 200)
        self.formatLabel.text = isText ? "READ · \(readMinutes) MIN" : ""
        self.formatLabel.isHidden = !isText
        self.dateLabel.text = DateFormatter.localizedString(from: Date(timeIntervalSince1970: Double(post.message.timestamp)), dateStyle: .medium, timeStyle: .short)
        let comments = post.message.attributes.compactMap { $0 as? ReplyThreadMessageAttribute }.first
        let hasDiscussion = comments?.commentsPeerId != nil
        self.readingHint.text = hasDiscussion ? "Open discussion" : (isText ? "Read post" : "Explore this post")
        var details: [String] = []
        if let comments, hasDiscussion { details.append("\(compactNumericCountString(Int(comments.count))) replies") }
        if let views = post.viewCount { details.append("\(compactNumericCountString(views)) views") }
        self.engagementLabel.text = details.joined(separator: " · ")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.0
        paragraph.lineBreakMode = .byTruncatingTail
        self.textLabel.attributedText = NSAttributedString(string: post.message.text.trimmingCharacters(in: .whitespacesAndNewlines), attributes: [.font: self.textLabel.font!, .foregroundColor: theme.list.itemPrimaryTextColor, .paragraphStyle: paragraph])
        self.channelLabel.text = post.peer.compactDisplayTitle

        if self.postId != post.id {
            self.postId = post.id
            let message = post.message._asMessage()
            let pixelSize = CGSize(width: 480.0, height: 480.0)
            let signal: Signal<(TransformImageArguments) -> DrawingContext?, NoError>
            switch post.kind {
            case let .photo(image):
                self.imageSize = image.representations.last?.dimensions.cgSize ?? pixelSize
                signal = mediaGridMessagePhoto(account: context.account, userLocation: .peer(post.id.peerId), photoReference: .message(message: MessageReference(message), media: image), fullRepresentationSize: pixelSize)
            case let .video(file, _):
                self.imageSize = file.dimensions?.cgSize ?? pixelSize
                signal = chatMessageVideoThumbnail(account: context.account, userLocation: .peer(post.id.peerId), fileReference: .message(message: MessageReference(message), media: file))
            case .text:
                signal = .complete()
            }
            self.imageNode.setSignal(signal)
            if !UIAccessibility.isReduceMotionEnabled {
                self.imageNode.view.alpha = 0.0
                UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseOut, animations: {
                    self.imageNode.view.alpha = 1.0
                })
            }
        }

        var kindLabel = isText ? ExploreStrings.string("ExploreText") : ExploreStrings.string("ExplorePhoto")
        if case let .video(_, duration) = post.kind {
            kindLabel = ExploreStrings.string("ExploreVideo")
            if let duration {
                let seconds = Int(duration.rounded())
                self.durationLabel.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
            } else {
                self.durationLabel.text = nil
            }
        } else {
            self.durationLabel.text = nil
        }

        let viewCount = post.viewCount
        self.viewsLabel.text = nil

        self.albumBadge.isHidden = post.albumCount <= 1
        self.albumLabel.text = post.albumCount > 1 ? "\(post.albumCount)" : nil

        var label = "\(post.peer.compactDisplayTitle), \(kindLabel)"
        if let viewCount {
            label += ", \(compactNumericCountString(viewCount)) \(ExploreStrings.string("ExploreViews"))"
        }
        if post.albumCount > 1 {
            label += ", \(post.albumCount) \(ExploreStrings.string("ExploreAlbumItems"))"
        }
        if isText { label += ", " + post.message.text }
        self.accessibilityLabel = label

        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds

        let mediaHeight = self.isTextPost ? CGFloat(0.0) : min(300.0, (bounds.width - 24.0) * 0.68)
        let mediaBounds = CGRect(x: 12.0, y: 72.0, width: bounds.width - 24.0, height: mediaHeight)
        let fittedSize = self.imageSize.width > 0.0 ? self.imageSize.aspectFilled(mediaBounds.size) : mediaBounds.size
        if !self.isTextPost {
            self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: fittedSize, boundingSize: mediaBounds.size, intrinsicInsets: UIEdgeInsets()))()
        }
        self.imageNode.frame = mediaBounds
        self.avatarNode.frame = CGRect(x: 16.0, y: 16.0, width: 42.0, height: 42.0)
        self.channelLabel.frame = CGRect(x: 70.0, y: 16.0, width: bounds.width - 86.0, height: 23.0)
        self.dateLabel.frame = CGRect(x: 70.0, y: 40.0, width: bounds.width - 86.0, height: 17.0)
        self.formatLabel.frame = CGRect(x: 20.0, y: 76.0, width: 108.0, height: 24.0)
        let textTop = self.isTextPost ? CGFloat(112.0) : mediaBounds.maxY + 14.0
        self.textLabel.frame = CGRect(x: 20.0, y: textTop, width: bounds.width - 40.0, height: max(0.0, bounds.height - textTop - 72.0))
        self.footerLine.frame = CGRect(x: 20.0, y: bounds.height - 60.0, width: bounds.width - 40.0, height: 0.5)
        self.readingHint.frame = CGRect(x: 20.0, y: bounds.height - 49.0, width: bounds.width - 64.0, height: 21.0)
        self.engagementLabel.frame = CGRect(x: 20.0, y: bounds.height - 26.0, width: bounds.width - 64.0, height: 16.0)
        self.arrowView.frame = CGRect(x: bounds.width - 42.0, y: bounds.height - 43.0, width: 20.0, height: 20.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.bottomGradient.frame = CGRect(x: 12.0, y: mediaBounds.maxY - 36.0, width: mediaBounds.width, height: 36.0)
        self.bottomGradient.isHidden = self.isTextPost
        self.bottomGradient.cornerRadius = 16.0
        CATransaction.commit()

        let durationSize = self.durationLabel.sizeThatFits(bounds.size)
        self.durationLabel.frame = CGRect(x: bounds.width - durationSize.width - 22.0, y: mediaBounds.maxY - durationSize.height - 4.0, width: durationSize.width, height: durationSize.height)
        let viewsSize = self.viewsLabel.sizeThatFits(bounds.size)
        self.viewsLabel.frame = CGRect(x: 6.0, y: mediaBounds.maxY - viewsSize.height - 4.0, width: viewsSize.width, height: viewsSize.height)

        self.albumBadge.frame = CGRect(x: bounds.width - 36.0, y: 82.0, width: 14.0, height: 14.0)
        let albumSize = self.albumLabel.sizeThatFits(bounds.size)
        self.albumLabel.frame = CGRect(x: self.albumBadge.frame.minX - albumSize.width - 3.0, y: 81.0, width: albumSize.width, height: albumSize.height)
    }
}

// Shown while the first page loads.
final class ExploreSkeletonCell: UICollectionViewCell {
    static let reuseIdentifier = "ExploreSkeletonCell"
}
