import Foundation
import UIKit
import TelegramCore
import TelegramNotes

// Sample memories for demo mode, with the fictional contacts from Notes. Their pictures are drawn here,
// so the demo needs no real photos of anyone.
enum TelegramMemoryDemo {
    private enum Kind {
        case hills
        case table
        case stage
    }

    private struct Scene {
        let key: String
        let emoji: String
        let top: UInt32
        let bottom: UInt32
        let ground: UInt32
        let kind: Kind
        let hour: Int
    }

    private static let trips: [(name: String, yearsAgo: Int, scenes: [Scene])] = [
        ("Mia", 3, [
            Scene(key: "rome-scooter", emoji: "🛵", top: 0xff9a5a, bottom: 0xffd39b, ground: 0xc9773d, kind: .hills, hour: 10),
            Scene(key: "rome-colosseum", emoji: "🏛️", top: 0x5fa8f5, bottom: 0xcde8ff, ground: 0xd9b27c, kind: .hills, hour: 12),
            Scene(key: "rome-pasta", emoji: "🍝", top: 0xf4e3c8, bottom: 0xfff6e8, ground: 0xd8433b, kind: .table, hour: 14),
            Scene(key: "rome-gelato", emoji: "🍨", top: 0xff9ec4, bottom: 0xb8f0dc, ground: 0x6fc7a4, kind: .hills, hour: 18)
        ]),
        ("Leo", 1, [
            Scene(key: "concert-guitar", emoji: "🎸", top: 0x1c0f3f, bottom: 0x5b2a86, ground: 0x2a1450, kind: .stage, hour: 21),
            Scene(key: "concert-mic", emoji: "🎤", top: 0x0f1d4a, bottom: 0xc2307a, ground: 0x2b0f3a, kind: .stage, hour: 22)
        ])
    ]

    private static var imageCache: [String: UIImage] = [:]

    static func memories(windows: [TelegramMemoryWindow]) -> [TelegramMemory] {
        let peers = TelegramNotesStore.demoContactPeers
        var result: [TelegramMemory] = []
        for trip in self.trips {
            guard let peer = peers.first(where: { $0.compactDisplayTitle == trip.name }), let window = windows.first(where: { $0.yearsAgo == trip.yearsAgo }) else {
                continue
            }
            let items = trip.scenes.map { scene -> TelegramMemoryItem in
                let timestamp = window.start + Int32(scene.hour * 3600)
                return TelegramMemoryItem(id: scene.key, content: .demo(self.image(scene, timestamp: timestamp)), timestamp: timestamp)
            }
            result.append(TelegramMemory(peer: peer, yearsAgo: trip.yearsAgo, items: items))
        }
        return result
    }

    private static func color(_ value: UInt32, _ alpha: CGFloat = 1.0) -> UIColor {
        return UIColor(red: CGFloat((value >> 16) & 0xff) / 255.0, green: CGFloat((value >> 8) & 0xff) / 255.0, blue: CGFloat(value & 0xff) / 255.0, alpha: alpha)
    }

    private static func image(_ scene: Scene, timestamp: Int32) -> UIImage {
        if let cached = self.imageCache[scene.key] {
            return cached
        }
        let size = CGSize(width: 900.0, height: 1200.0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let c = rendererContext.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            if let sky = CGGradient(colorsSpace: space, colors: [self.color(scene.top).cgColor, self.color(scene.bottom).cgColor] as CFArray, locations: [0.0, 1.0]) {
                c.drawLinearGradient(sky, start: CGPoint(), end: CGPoint(x: 0.0, y: size.height), options: [])
            }
            var subjectCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.6)
            switch scene.kind {
            case .hills:
                if let sun = CGGradient(colorsSpace: space, colors: [UIColor(white: 1.0, alpha: 0.95).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray, locations: [0.0, 1.0]) {
                    c.drawRadialGradient(sun, startCenter: CGPoint(x: size.width * 0.74, y: size.height * 0.24), startRadius: 60.0, endCenter: CGPoint(x: size.width * 0.74, y: size.height * 0.24), endRadius: 300.0, options: [.drawsBeforeStartLocation])
                }
                for (index, offset) in [CGFloat(0.66), 0.74].enumerated() {
                    let path = UIBezierPath()
                    let y = size.height * offset
                    path.move(to: CGPoint(x: 0.0, y: y + 40.0))
                    path.addCurve(to: CGPoint(x: size.width, y: y - 30.0 + CGFloat(index) * 50.0), controlPoint1: CGPoint(x: size.width * 0.3, y: y - 110.0 + CGFloat(index) * 90.0), controlPoint2: CGPoint(x: size.width * 0.65, y: y + 90.0))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0.0, y: size.height))
                    path.close()
                    self.color(scene.ground, index == 0 ? 0.55 : 1.0).setFill()
                    path.fill()
                }
                subjectCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.64)
            case .table:
                let tableTop = size.height * 0.55
                self.color(0xfdf8f0).setFill()
                c.fill(CGRect(x: 0.0, y: tableTop, width: size.width, height: size.height - tableTop))
                let square: CGFloat = 75.0
                self.color(scene.ground, 0.85).setFill()
                var row = 0
                var y = tableTop
                while y < size.height {
                    var x: CGFloat = row % 2 == 0 ? 0.0 : square
                    while x < size.width {
                        c.fill(CGRect(x: x, y: y, width: square, height: square))
                        x += square * 2.0
                    }
                    y += square
                    row += 1
                }
                UIColor(white: 1.0, alpha: 1.0).setFill()
                c.setShadow(offset: CGSize(width: 0.0, height: 14.0), blur: 30.0, color: UIColor(white: 0.0, alpha: 0.25).cgColor)
                c.fillEllipse(in: CGRect(x: size.width * 0.17, y: size.height * 0.56, width: size.width * 0.66, height: size.height * 0.3))
                c.setShadow(offset: .zero, blur: 0.0, color: nil)
                subjectCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.69)
            case .stage:
                for (index, x) in [CGFloat(0.18), 0.5, 0.82].enumerated() {
                    let cone = UIBezierPath()
                    cone.move(to: CGPoint(x: size.width * x - 18.0, y: 0.0))
                    cone.addLine(to: CGPoint(x: size.width * x + 18.0, y: 0.0))
                    cone.addLine(to: CGPoint(x: size.width * (0.5 + (x - 0.5) * 0.4) + 220.0, y: size.height * 0.8))
                    cone.addLine(to: CGPoint(x: size.width * (0.5 + (x - 0.5) * 0.4) - 220.0, y: size.height * 0.8))
                    cone.close()
                    UIColor(white: 1.0, alpha: index == 1 ? 0.16 : 0.1).setFill()
                    cone.fill()
                }
                self.color(scene.ground).setFill()
                c.fill(CGRect(x: 0.0, y: size.height * 0.8, width: size.width, height: size.height * 0.2))
                for index in 0 ..< 46 {
                    let x = CGFloat((index * 197) % 900)
                    let y = CGFloat((index * 131) % 760) + 30.0
                    let dot = CGFloat(4 + index % 5)
                    let tints: [UInt32] = [0xffd166, 0x9b8cff, 0xff6fb5, 0x6fe3ff]
                    self.color(tints[index % tints.count], 0.75).setFill()
                    c.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                }
                subjectCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.6)
            }
            let emoji = NSAttributedString(string: scene.emoji, attributes: [.font: UIFont.systemFont(ofSize: 330.0)])
            let emojiSize = emoji.size()
            c.setShadow(offset: CGSize(width: 0.0, height: 22.0), blur: 40.0, color: UIColor(white: 0.0, alpha: 0.3).cgColor)
            emoji.draw(at: CGPoint(x: subjectCenter.x - emojiSize.width * 0.5, y: subjectCenter.y - emojiSize.height * 0.5))
            c.setShadow(offset: .zero, blur: 0.0, color: nil)

            if let vignette = CGGradient(colorsSpace: space, colors: [UIColor(white: 0.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.28).cgColor] as CFArray, locations: [0.0, 1.0]) {
                c.drawRadialGradient(vignette, startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5), startRadius: size.width * 0.45, endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5), endRadius: size.height * 0.78, options: [.drawsAfterEndLocation])
            }

            // The orange date stamp of an old film camera.
            let formatter = DateFormatter()
            formatter.dateFormat = "M d ''yy"
            let stamp = NSAttributedString(string: formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp))), attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 44.0, weight: .semibold), .foregroundColor: self.color(0xff9a3c)])
            let stampSize = stamp.size()
            c.setShadow(offset: .zero, blur: 12.0, color: self.color(0xff5a1f, 0.9).cgColor)
            stamp.draw(at: CGPoint(x: size.width - stampSize.width - 50.0, y: size.height - stampSize.height - 46.0))
        }
        self.imageCache[scene.key] = image
        return image
    }
}
