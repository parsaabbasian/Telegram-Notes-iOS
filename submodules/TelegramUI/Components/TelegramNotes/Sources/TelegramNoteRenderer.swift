import Foundation
import UIKit
import TelegramPresentationData

// Draws the 1080x1920 Story image a Note is published as: the text in a speech bubble over the theme's accent gradient.
public enum TelegramNoteRenderer {
    public static func render(text: String, theme: PresentationTheme, size: CGSize = TelegramNoteCaption.imageSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let scale = size.width / 1080.0
        let accent = theme.list.itemAccentColor

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext

            let colors = [accent.withMultipliedBrightnessBy(1.15).cgColor, accent.withMultipliedBrightnessBy(0.55).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.drawLinearGradient(gradient, start: CGPoint(), end: CGPoint(x: size.width, y: size.height), options: [])
            }

            let fontSize: CGFloat = (TelegramNoteCaption.length(text) <= 30 ? 84.0 : 64.0) * scale
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
            let string = NSAttributedString(string: text, attributes: attributes)

            let horizontalPadding = 72.0 * scale
            let verticalPadding = 56.0 * scale
            let maxTextWidth = size.width - 160.0 * scale - horizontalPadding * 2.0
            let textBounds = string.boundingRect(with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral

            let bubbleSize = CGSize(width: textBounds.width + horizontalPadding * 2.0, height: textBounds.height + verticalPadding * 2.0)
            let bubbleFrame = CGRect(x: (size.width - bubbleSize.width) * 0.5, y: (size.height - bubbleSize.height) * 0.5, width: bubbleSize.width, height: bubbleSize.height)

            context.setShadow(offset: CGSize(width: 0.0, height: 12.0 * scale), blur: 48.0 * scale, color: UIColor(white: 0.0, alpha: 0.25).cgColor)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: bubbleFrame, cornerRadius: min(64.0 * scale, bubbleSize.height * 0.5)).fill()
            let tail = UIBezierPath()
            tail.move(to: CGPoint(x: bubbleFrame.minX + 96.0 * scale, y: bubbleFrame.maxY - 2.0))
            tail.addLine(to: CGPoint(x: bubbleFrame.minX + 84.0 * scale, y: bubbleFrame.maxY + 44.0 * scale))
            tail.addLine(to: CGPoint(x: bubbleFrame.minX + 150.0 * scale, y: bubbleFrame.maxY - 2.0))
            tail.close()
            tail.fill()
            context.setShadow(offset: .zero, blur: 0.0, color: nil)

            string.draw(with: CGRect(x: bubbleFrame.minX + horizontalPadding, y: bubbleFrame.minY + verticalPadding, width: textBounds.width, height: textBounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

            let label = NSAttributedString(string: "📝 " + TelegramNotesStrings.string("NotesTitle"), attributes: [
                .font: UIFont.systemFont(ofSize: 44.0 * scale, weight: .semibold),
                .foregroundColor: UIColor(white: 1.0, alpha: 0.85)
            ])
            let labelSize = label.size()
            label.draw(at: CGPoint(x: (size.width - labelSize.width) * 0.5, y: bubbleFrame.minY - labelSize.height - 48.0 * scale))
        }
    }
}

private extension UIColor {
    func withMultipliedBrightnessBy(_ factor: CGFloat) -> UIColor {
        var hue: CGFloat = 0.0, saturation: CGFloat = 0.0, brightness: CGFloat = 0.0, alpha: CGFloat = 0.0
        guard self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(hue: hue, saturation: saturation, brightness: max(0.0, min(1.0, brightness * factor)), alpha: alpha)
    }
}
