import Foundation
import UIKit

// A reading feed with stable full-width cards. Appending never rearranges earlier posts.
final class ExploreGridLayout: UICollectionViewLayout {
    static let gap: CGFloat = 18.0
    static let blockSize = 1
    var posts: [ExplorePost] = []
    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0.0

    static func isLarge(index: Int, count: Int) -> Bool { return true }

    override func prepare() {
        super.prepare()
        guard let collectionView = self.collectionView else {
            return
        }
        let width = collectionView.bounds.width
        let count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        var attributes: [UICollectionViewLayoutAttributes] = []
        var maxY: CGFloat = 12.0
        for index in 0 ..< count {
            let item = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
            let cardWidth = max(0.0, min(640.0, width - 32.0))
            let bodyLine = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: 19.0)).lineHeight + 4.0
            var height = bodyLine * 6.0 + 188.0
            if self.posts.indices.contains(index) {
                let post = self.posts[index]
                let isText: Bool
                if case .text = post.kind { isText = true } else { isText = false }
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: isText ? 19.0 : 16.0, weight: isText ? .medium : .regular))
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 4.0
                let measured = (post.message.text as NSString).boundingRect(with: CGSize(width: max(1.0, cardWidth - 40.0), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph], context: nil).height
                let excerpt = min(ceil(measured), (font.lineHeight + 4.0) * (isText ? 6.0 : 3.0))
                height = (isText ? 112.0 : 86.0 + min(300.0, (cardWidth - 24.0) * 0.68)) + max(isText ? 72.0 : 24.0, excerpt) + 72.0
            }
            item.frame = CGRect(x: (width - cardWidth) * 0.5, y: maxY, width: cardWidth, height: height)
            maxY = item.frame.maxY + Self.gap
            attributes.append(item)
        }
        self.attributes = attributes
        self.contentHeight = maxY
    }

    override var collectionViewContentSize: CGSize {
        return CGSize(width: self.collectionView?.bounds.width ?? 0.0, height: self.contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return self.attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return indexPath.item < self.attributes.count ? self.attributes[indexPath.item] : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return newBounds.width != self.collectionView?.bounds.width
    }
}
