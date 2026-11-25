import Foundation
import UIKit

private let transparentContents: CGImage? = UIGraphicsImageRenderer(size: CGSize(width: 1.0, height: 1.0)).image { _ in }.cgImage

// iOS 26 and later deliver no touches to a layer that draws nothing, even though hit-testing returns it
// (docs/ios27-windows-and-touches.md). Views that only hold other views get fully transparent contents.
func makeTouchable(_ view: UIView) {
    view.layer.contents = transparentContents
}
