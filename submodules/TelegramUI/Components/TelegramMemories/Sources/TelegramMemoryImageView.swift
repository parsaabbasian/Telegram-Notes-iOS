import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import AccountContext
import PhotoResources

// Shows one memory item: a chat photo, a video's first frame or a demo picture, filling its bounds.
final class TelegramMemoryImageView: UIView {
    private let imageNode = TransformImageNode()
    private let demoView = UIImageView()
    private let playIcon = UIImageView()
    private var itemId: String?
    private var dimensions = CGSize(width: 1.0, height: 1.0)

    var image: UIImage? {
        return self.demoView.isHidden ? nil : self.demoView.image
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true
        self.isUserInteractionEnabled = false
        self.addSubview(self.imageNode.view)
        self.demoView.contentMode = .scaleAspectFill
        self.demoView.clipsToBounds = true
        self.addSubview(self.demoView)
        self.playIcon.image = UIImage(systemName: "play.fill")
        self.playIcon.tintColor = .white
        self.playIcon.contentMode = .scaleAspectFit
        self.playIcon.layer.shadowOpacity = 0.35
        self.playIcon.layer.shadowRadius = 4.0
        self.playIcon.layer.shadowOffset = .zero
        self.addSubview(self.playIcon)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func update(context: AccountContext, item: TelegramMemoryItem, fullSize: Bool) {
        if self.itemId == item.id {
            return
        }
        self.itemId = item.id
        self.playIcon.isHidden = !item.isVideo
        let representationSize = fullSize ? CGSize(width: 1280.0, height: 1280.0) : CGSize(width: 180.0, height: 180.0)
        switch item.content {
        case let .demo(image):
            self.demoView.image = image
            self.demoView.isHidden = false
            self.imageNode.isHidden = true
            self.dimensions = image.size
        case let .photo(message, image):
            self.demoView.isHidden = true
            self.imageNode.isHidden = false
            self.dimensions = largestImageRepresentation(image.representations)?.dimensions.cgSize ?? CGSize(width: 1.0, height: 1.0)
            self.imageNode.setSignal(mediaGridMessagePhoto(account: context.account, userLocation: .peer(message.id.peerId), photoReference: .message(message: MessageReference(message._asMessage()), media: image), fullRepresentationSize: representationSize))
        case let .video(message, file):
            self.demoView.isHidden = true
            self.imageNode.isHidden = false
            self.dimensions = file.dimensions?.cgSize ?? CGSize(width: 1.0, height: 1.0)
            self.imageNode.setSignal(chatMessageVideoThumbnail(account: context.account, userLocation: .peer(message.id.peerId), fileReference: .message(message: MessageReference(message._asMessage()), media: file)))
        }
        self.setNeedsLayout()
    }

    // The aspect ratio of the item, so a viewer can size it without cropping.
    var aspectRatio: CGFloat {
        return self.dimensions.width / max(1.0, self.dimensions.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        self.demoView.frame = bounds
        self.imageNode.frame = bounds
        if !self.imageNode.isHidden, bounds.width > 0.0, bounds.height > 0.0 {
            let filled = self.dimensions.aspectFilled(bounds.size)
            self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: filled, boundingSize: bounds.size, intrinsicInsets: UIEdgeInsets()))()
        }
        let iconSide = min(28.0, bounds.width * 0.4)
        self.playIcon.frame = CGRect(x: (bounds.width - iconSide) * 0.5, y: (bounds.height - iconSide) * 0.5, width: iconSide, height: iconSide)
    }
}
