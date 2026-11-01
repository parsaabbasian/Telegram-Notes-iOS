import Foundation
import TelegramNotes
import InvisibleInkDustNode
import UIKit
import Display
import ComponentFlow
import AppBundle
import BundleIconComponent
import AccountContext
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AvatarNode
import ContextUI
import AsyncDisplayKit
import StoryContainerScreen
import MultilineTextComponent
import HierarchyTrackingLayer
import EmojiStatusComponent

private func calculateCircleIntersection(center: CGPoint, otherCenter: CGPoint, radius: CGFloat) -> (point1Angle: CGFloat, point2Angle: CGFloat)? {
    let distanceVector = CGPoint(x: otherCenter.x - center.x, y: otherCenter.y - center.y)
    let distance = sqrt(distanceVector.x * distanceVector.x + distanceVector.y * distanceVector.y)
    if distance > radius * 2.0 || distance == 0.0 {
        return nil
    }
    
    let x1 = center.x
    let y1 = center.y
    let x2 = otherCenter.x
    let y2 = otherCenter.y
    let r1 = radius
    let r2 = radius
    let R = distance
    
    let ix1: CGFloat = 0.5 * (x1 + x2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (x2 - x1) + 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (y2 - y1)
    let ix2: CGFloat = 0.5 * (x1 + x2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (x2 - x1) - 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (y2 - y1)
    
    let iy1: CGFloat = 0.5 * (y1 + y2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (y2 - y1) + 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (x1 - x2)
    let iy2: CGFloat = 0.5 * (y1 + y2) + (pow(r1, 2.0) - pow(r2, 2.0)) / (2 * pow(R, 2.0)) * (y2 - y1) - 0.5 * sqrt(2.0 * (pow(r1, 2.0) + pow(r2, 2.0)) / pow(R, 2.0) - pow((pow(r1, 2.0) - pow(r2, 2.0)), 2.0) / pow(R, 4.0) - 1) * (x1 - x2)
    
    var v1 = CGPoint(x: ix1 - center.x, y: iy1 - center.y)
    let length1 = sqrt(v1.x * v1.x + v1.y * v1.y)
    v1.x /= length1
    v1.y /= length1
    
    var v2 = CGPoint(x: ix2 - center.x, y: iy2 - center.y)
    let length2 = sqrt(v2.x * v2.x + v2.y * v2.y)
    v2.x /= length2
    v2.y /= length2
    
    var point1Angle = atan(v1.y / v1.x)
    var point2Angle = atan(v2.y / v2.x)
    
    if distanceVector.x < 0.0 {
        point1Angle += CGFloat.pi
        point2Angle += CGFloat.pi
    }
    
    return (point1Angle, point2Angle)
}

private func calculateMergingCircleShape(center: CGPoint, leftCenter: CGPoint?, rightCenter: CGPoint?, radius: CGFloat, totalCount: Int, unseenCount: Int, isSeen: Bool, segmentFraction: CGFloat, rotationFraction: CGFloat) -> CGPath {
    var totalCount = totalCount
    var unseenCount = unseenCount
    
    let totalCountNorm = CGFloat(totalCount) / 30.0
    if totalCountNorm > 1.0 {
        totalCount = Int(CGFloat(totalCount) / totalCountNorm)
        unseenCount = Int(CGFloat(unseenCount) / totalCountNorm)
    }
    
    let leftAngles = leftCenter.flatMap { calculateCircleIntersection(center: center, otherCenter: $0, radius: radius) }
    let rightAngles = rightCenter.flatMap { calculateCircleIntersection(center: center, otherCenter: $0, radius: radius) }
    
    let path = CGMutablePath()
    
    let segmentCount = max(totalCount, 1)
    
    if isSeen {
        if unseenCount < totalCount {
        } else {
            return path
        }
    } else {
        if unseenCount != 0 {
        } else {
            return path
        }
    }
    
    if let leftAngles, let rightAngles {
        path.addArc(center: center, radius: radius, startAngle: leftAngles.point1Angle, endAngle: rightAngles.point2Angle, clockwise: true)
        
        path.move(to: CGPoint(x: center.x + cos(rightAngles.point1Angle) * radius, y: center.y + sin(rightAngles.point1Angle) * radius))
        path.addArc(center: center, radius: radius, startAngle: rightAngles.point1Angle, endAngle: leftAngles.point2Angle, clockwise: true)
    } else if let angles = leftAngles ?? rightAngles {
        path.addArc(center: center, radius: radius, startAngle: angles.point1Angle, endAngle: angles.point2Angle, clockwise: true)
    } else {
        if segmentCount == 1 {
            if isSeen {
                if unseenCount == 0 {
                    path.addEllipse(in: CGRect(origin: CGPoint(x: center.x - radius, y: center.y - radius), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
                }
            } else {
                if unseenCount != 0 {
                    path.addEllipse(in: CGRect(origin: CGPoint(x: center.x - radius, y: center.y - radius), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
                }
            }
        } else {
            let segmentSpacing: CGFloat = 4.0 * segmentFraction
            let segmentSpacingAngle: CGFloat = segmentSpacing / radius
            let segmentAngle = (2.0 * CGFloat.pi - segmentSpacingAngle * CGFloat(segmentCount)) / CGFloat(segmentCount)
            for i in 0 ..< segmentCount {
                if isSeen {
                    if i <= segmentCount - unseenCount - 1 {
                    } else {
                        continue
                    }
                } else {
                    if i > segmentCount - unseenCount - 1 {
                    } else {
                        continue
                    }
                }
                
                var startAngle = segmentSpacingAngle * 0.5 - CGFloat.pi * 0.5 + CGFloat(i) * (segmentSpacingAngle + segmentAngle)
                startAngle += -1.0 * (1.0 - rotationFraction) * CGFloat.pi * 2.0 * 0.25
                
                let endAngle = startAngle + segmentAngle
                path.move(to: CGPoint(x: center.x + cos(startAngle) * radius, y: center.y + sin(startAngle) * radius))
                path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            }
        }
    }
    
    return path
}

private final class StoryProgressLayer: HierarchyTrackingLayer {
    enum Value: Equatable {
        case indefinite
        case progress(Float)
    }
    
    private struct Params: Equatable {
        var size: CGSize
        var lineWidth: CGFloat
        var radius: CGFloat
        var value: Value
    }
    private var currentParams: Params?
    
    private let uploadProgressLayer = SimpleShapeLayer()
    
    private let indefiniteDashLayer = SimpleShapeLayer()
    private let indefiniteReplicatorLayer = CAReplicatorLayer()
    
    override init() {
        super.init()
        
        self.uploadProgressLayer.fillColor = nil
        self.uploadProgressLayer.strokeColor = UIColor.white.cgColor
        self.uploadProgressLayer.lineCap = .round
        
        self.indefiniteDashLayer.fillColor = nil
        self.indefiniteDashLayer.strokeColor = UIColor.white.cgColor
        self.indefiniteDashLayer.lineCap = .round
        self.indefiniteDashLayer.lineJoin = .round
        self.indefiniteDashLayer.strokeEnd = 0.0333
        
        let count = 1.0 / self.indefiniteDashLayer.strokeEnd
        let angle = (2.0 * Double.pi) / Double(count)
        self.indefiniteReplicatorLayer.addSublayer(self.indefiniteDashLayer)
        self.indefiniteReplicatorLayer.instanceCount = Int(count)
        self.indefiniteReplicatorLayer.instanceTransform = CATransform3DMakeRotation(CGFloat(angle), 0.0, 0.0, 1.0)
        self.indefiniteReplicatorLayer.transform = CATransform3DMakeRotation(-.pi / 2.0, 0.0, 0.0, 1.0)
        self.indefiniteReplicatorLayer.instanceDelay = 0.025
        
        self.didEnterHierarchy = { [weak self] in
            guard let self else {
                return
            }
            self.updateAnimations(transition: .immediate)
        }
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func reset() {
        self.currentParams = nil
        self.indefiniteDashLayer.path = nil
        self.uploadProgressLayer.path = nil
    }
    
    func updateAnimations(transition: ComponentTransition) {
        guard let params = self.currentParams else {
            return
        }
        
        switch params.value {
        case let .progress(progress):
            var animateIn = false
            if self.indefiniteReplicatorLayer.superlayer != nil {
                self.indefiniteReplicatorLayer.opacity = 0.0
                self.indefiniteReplicatorLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { [weak self] finished in
                    guard let self, finished else {
                        return
                    }
                    self.indefiniteReplicatorLayer.removeFromSuperlayer()
                })
                animateIn = true
            }
            if self.uploadProgressLayer.superlayer == nil {
                self.addSublayer(self.uploadProgressLayer)
                if animateIn {
                    self.uploadProgressLayer.opacity = 1.0
                    self.uploadProgressLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
            transition.setShapeLayerStrokeEnd(layer: self.uploadProgressLayer, strokeEnd: CGFloat(progress))
            if self.uploadProgressLayer.animation(forKey: "rotation") == nil {
                let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotationAnimation.duration = 2.0
                rotationAnimation.fromValue = NSNumber(value: Float(0.0))
                rotationAnimation.toValue = NSNumber(value: Float(Double.pi * 2.0))
                rotationAnimation.repeatCount = Float.infinity
                rotationAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
                self.uploadProgressLayer.add(rotationAnimation, forKey: "rotation")
            }
        case .indefinite:
            var animateIn = false
            if self.uploadProgressLayer.superlayer != nil {
                self.uploadProgressLayer.opacity = 0.0
                self.uploadProgressLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { [weak self] finished in
                    guard let self, finished else {
                        return
                    }
                    self.uploadProgressLayer.removeFromSuperlayer()
                })
                animateIn = true
            }
            if self.indefiniteReplicatorLayer.superlayer == nil {
                self.addSublayer(self.indefiniteReplicatorLayer)
                if animateIn {
                    self.indefiniteReplicatorLayer.opacity = 1.0
                    self.indefiniteReplicatorLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
            if self.indefiniteReplicatorLayer.animation(forKey: "rotation") == nil {
                let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotationAnimation.duration = 4.0
                rotationAnimation.fromValue = NSNumber(value: -.pi / 2.0)
                rotationAnimation.toValue = NSNumber(value: -.pi / 2.0 + Double.pi * 2.0)
                rotationAnimation.repeatCount = Float.infinity
                rotationAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
                self.indefiniteReplicatorLayer.add(rotationAnimation, forKey: "rotation")
            }
            if self.indefiniteDashLayer.animation(forKey: "dash") == nil {
                let dashAnimation = CAKeyframeAnimation(keyPath: "strokeStart")
                dashAnimation.keyTimes = [0.0, 0.45, 0.55, 1.0]
                dashAnimation.values = [
                    self.indefiniteDashLayer.strokeStart,
                    self.indefiniteDashLayer.strokeEnd,
                    self.indefiniteDashLayer.strokeEnd,
                    self.indefiniteDashLayer.strokeStart,
                ]
                dashAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
                dashAnimation.duration = 2.5
                dashAnimation.repeatCount = .infinity
                self.indefiniteDashLayer.add(dashAnimation, forKey: "dash")
            }
        }
    }
    
    func update(size: CGSize, lineWidth: CGFloat, radius: CGFloat, value: Value, transition: ComponentTransition) {
        let params = Params(
            size: size,
            lineWidth: lineWidth,
            radius: radius,
            value: value
        )
        if self.currentParams == params {
            return
        }
        if self.currentParams?.radius != params.radius {
            self.uploadProgressLayer.path = nil
            self.indefiniteDashLayer.path = nil
        }
        self.currentParams = params
        
        self.uploadProgressLayer.lineWidth = lineWidth
        self.indefiniteDashLayer.lineWidth = lineWidth
        
        let bounds = CGRect(origin: .zero, size: size)
        if self.uploadProgressLayer.path == nil {
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(origin: CGPoint(x: (size.width - radius * 2.0) * 0.5, y: (size.height - radius * 2.0) * 0.5), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
            self.uploadProgressLayer.path = path
            self.uploadProgressLayer.frame = bounds
        }
        
        if self.indefiniteDashLayer.path == nil {
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(origin: CGPoint(x: (size.width - radius * 2.0) * 0.5, y: (size.height - radius * 2.0) * 0.5), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
            self.indefiniteDashLayer.path = path
            self.indefiniteReplicatorLayer.frame = bounds
            self.indefiniteDashLayer.frame = bounds
        }
        
        self.updateAnimations(transition: transition)
    }
}

private var sharedAvatarBackgroundImage: UIImage?

public final class StoryPeerListItemComponent: Component {
    public final class TransitionView: UIView {
        private weak var itemView: StoryPeerListItemComponent.View?
        private var snapshotView: UIView?
        private var portalView: PortalView?
        
        init(itemView: StoryPeerListItemComponent.View?) {
            self.itemView = itemView
            
            super.init(frame: CGRect())
            
            if let itemView {
                if let portalView = PortalView(matchPosition: false) {
                    portalView.view.layer.rasterizationScale = UIScreenScale
                    itemView.avatarContent.addPortal(view: portalView)
                    self.portalView = portalView
                    self.addSubview(portalView.view)
                }
                /*if let snapshotView = itemView.avatarContent.snapshotView(afterScreenUpdates: false) {
                    self.addSubview(snapshotView)
                    self.snapshotView = snapshotView
                }*/
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(state: StoryContainerScreen.TransitionState, transition: ComponentTransition) {
            let size = state.sourceSize.interpolate(to: state.destinationSize, amount: state.progress)
            
            if let snapshotView = self.snapshotView {
                transition.setPosition(view: snapshotView, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
                transition.setScale(view: snapshotView, scale: size.width / state.destinationSize.width)
            }
            if let portalView = self.portalView {
                transition.setPosition(view: portalView.view, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
                transition.setScale(view: portalView.view, scale: size.width / state.destinationSize.width)
            }
        }
    }
    
    public enum RingAnimation: Equatable {
        case progress(Float)
        case loading
    }
    
    public let context: AccountContext
    public let theme: PresentationTheme
    public let strings: PresentationStrings
    public let peer: EnginePeer
    public let totalCount: Int
    public let unseenCount: Int
    public let hasUnseenCloseFriendsItems: Bool
    public let hasLiveItems: Bool
    public let hasItems: Bool
    public let ringAnimation: RingAnimation?
    public let scale: CGFloat
    public let fullWidth: CGFloat
    public let expandedAlphaFraction: CGFloat
    public let expandEffectFraction: CGFloat
    public let leftNeighborDistance: CGPoint?
    public let rightNeighborDistance: CGPoint?
    public let composeContentOffset: CGFloat?
    public let action: (EnginePeer) -> Void
    public let contextGesture: (ContextExtractedContentContainingNode, ContextGesture, EnginePeer) -> Void
    public let note: Note?
    public let noteAction: ((EnginePeer) -> Void)?
    
    // A Telegram Note shown as a speech bubble over the avatar; the account's own item shows a placeholder to add one.
    public struct Note: Equatable {
        public let text: String
        public let isPlaceholder: Bool
        public let storyId: Int32?
        public let accessibilityLabel: String
        public let isHiddenBySpoiler: Bool
        public let timeLeftFraction: CGFloat?
        public let reaction: String?
        
        public init(text: String, isPlaceholder: Bool, storyId: Int32?, accessibilityLabel: String, isHiddenBySpoiler: Bool = false, timeLeftFraction: CGFloat? = nil, reaction: String? = nil) {
            self.text = text
            self.isPlaceholder = isPlaceholder
            self.storyId = storyId
            self.accessibilityLabel = accessibilityLabel
            self.isHiddenBySpoiler = isHiddenBySpoiler
            self.timeLeftFraction = timeLeftFraction
            self.reaction = reaction
        }
    }
    
    public init(
        context: AccountContext,
        theme: PresentationTheme,
        strings: PresentationStrings,
        peer: EnginePeer,
        totalCount: Int,
        unseenCount: Int,
        hasUnseenCloseFriendsItems: Bool,
        hasLiveItems: Bool,
        hasItems: Bool,
        ringAnimation: RingAnimation?,
        scale: CGFloat,
        fullWidth: CGFloat,
        expandedAlphaFraction: CGFloat,
        expandEffectFraction: CGFloat,
        leftNeighborDistance: CGPoint?,
        rightNeighborDistance: CGPoint?,
        composeContentOffset: CGFloat?,
        action: @escaping (EnginePeer) -> Void,
        contextGesture: @escaping (ContextExtractedContentContainingNode, ContextGesture, EnginePeer) -> Void,
        note: Note? = nil,
        noteAction: ((EnginePeer) -> Void)? = nil
    ) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.peer = peer
        self.totalCount = totalCount
        self.unseenCount = unseenCount
        self.hasUnseenCloseFriendsItems = hasUnseenCloseFriendsItems
        self.hasLiveItems = hasLiveItems
        self.hasItems = hasItems
        self.ringAnimation = ringAnimation
        self.scale = scale
        self.fullWidth = fullWidth
        self.expandedAlphaFraction = expandedAlphaFraction
        self.expandEffectFraction = expandEffectFraction
        self.leftNeighborDistance = leftNeighborDistance
        self.rightNeighborDistance = rightNeighborDistance
        self.composeContentOffset = composeContentOffset
        self.action = action
        self.contextGesture = contextGesture
        self.note = note
        self.noteAction = noteAction
    }
    
    public static func ==(lhs: StoryPeerListItemComponent, rhs: StoryPeerListItemComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.peer != rhs.peer {
            return false
        }
        if lhs.totalCount != rhs.totalCount {
            return false
        }
        if lhs.unseenCount != rhs.unseenCount {
            return false
        }
        if lhs.hasUnseenCloseFriendsItems != rhs.hasUnseenCloseFriendsItems {
            return false
        }
        if lhs.hasLiveItems != rhs.hasLiveItems {
            return false
        }
        if lhs.hasItems != rhs.hasItems {
            return false
        }
        if lhs.ringAnimation != rhs.ringAnimation {
            return false
        }
        if lhs.scale != rhs.scale {
            return false
        }
        if lhs.fullWidth != rhs.fullWidth {
            return false
        }
        if lhs.expandedAlphaFraction != rhs.expandedAlphaFraction {
            return false
        }
        if lhs.expandEffectFraction != rhs.expandEffectFraction {
            return false
        }
        if lhs.leftNeighborDistance != rhs.leftNeighborDistance {
            return false
        }
        if lhs.rightNeighborDistance != rhs.rightNeighborDistance {
            return false
        }
        if lhs.composeContentOffset != rhs.composeContentOffset {
            return false
        }
        if lhs.note != rhs.note {
            return false
        }
        return true
    }
    
    public final class View: UIView {
        let backgroundContainer: UIView
        
        private let extractedContainerNode: ContextExtractedContentContainingNode
        private let containerNode: ContextControllerSourceNode
        private let extractedBackgroundView: UIImageView
        
        private let button: HighlightTrackingButton
        private let titleContainer: UIView
        private var noteBubble: StoryNoteBubbleView?
        private var noteTimerTrackLayer: CAShapeLayer?
        private var noteTimerLayer: CAShapeLayer?
        private var noteReactionLabel: UILabel?
        private var demoAvatarView: UIImageView?
        
        fileprivate var composeLayer: StoryComposeLayer?
        fileprivate let avatarContent: PortalSourceView
        private let avatarContainer: UIView
        private let avatarBackgroundContainer: UIView
        private let avatarBackgroundView: UIImageView
        private var avatarNode: AvatarNode?
        private var avatarAddBadgeView: UIImageView?
        private var avatarLiveBadgeView: UIImageView?
        private var avatarLiveBadgeMaskSeenLayer: SimpleLayer?
        private var avatarLiveBadgeMaskUnseenLayer: SimpleLayer?
        private let avatarShapeLayer: SimpleShapeLayer
        private let indicatorMaskSeenLayer: SimpleLayer
        private let indicatorMaskUnseenLayer: SimpleLayer
        private let indicatorColorSeenLayer: SimpleGradientLayer
        private let indicatorColorUnseenLayer: SimpleGradientLayer
        private var progressLayer: StoryProgressLayer?
        private let indicatorShapeSeenLayer: SimpleShapeLayer
        private let indicatorShapeUnseenLayer: SimpleShapeLayer
        private let title = ComponentView<Empty>()
        private var verifiedIconView: ComponentHostView<Empty>?
        private let composeTitle = ComponentView<Empty>()
        
        private var component: StoryPeerListItemComponent?
        private weak var componentState: EmptyComponentState?
        
        public override init(frame: CGRect) {
            self.backgroundContainer = UIView()
            self.backgroundContainer.isUserInteractionEnabled = false
            
            self.button = HighlightTrackingButton()
            
            self.titleContainer = UIView()
            self.titleContainer.isUserInteractionEnabled = false
            
            self.extractedContainerNode = ContextExtractedContentContainingNode()
            self.containerNode = ContextControllerSourceNode()
            self.extractedBackgroundView = UIImageView()
            self.extractedBackgroundView.alpha = 0.0
            
            self.avatarContent = PortalSourceView()
            self.avatarContent.isUserInteractionEnabled = false
            
            self.avatarContainer = UIView()
            self.avatarContainer.isUserInteractionEnabled = false
            
            self.avatarBackgroundContainer = UIView()
            self.avatarBackgroundView = UIImageView()
            
            self.avatarShapeLayer = SimpleShapeLayer()
            
            self.indicatorColorSeenLayer = SimpleGradientLayer()
            self.indicatorColorSeenLayer.type = .axial
            self.indicatorColorSeenLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
            self.indicatorColorSeenLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
            
            self.indicatorColorUnseenLayer = SimpleGradientLayer()
            self.indicatorColorUnseenLayer.type = .axial
            self.indicatorColorUnseenLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
            self.indicatorColorUnseenLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
            
            self.indicatorMaskSeenLayer = SimpleLayer()
            self.indicatorMaskUnseenLayer = SimpleLayer()
            self.indicatorShapeSeenLayer = SimpleShapeLayer()
            self.indicatorShapeUnseenLayer = SimpleShapeLayer()
            
            super.init(frame: frame)
            
            self.layer.allowsGroupOpacity = true
            
            self.extractedContainerNode.contentNode.view.addSubview(self.extractedBackgroundView)
            
            self.containerNode.addSubnode(self.extractedContainerNode)
            self.containerNode.targetNodeForActivationProgress = self.extractedContainerNode.contentNode
            self.addSubview(self.containerNode.view)
            
            self.backgroundContainer.addSubview(self.avatarBackgroundContainer)
            self.avatarBackgroundContainer.addSubview(self.avatarBackgroundView)
            
            self.extractedContainerNode.contentNode.view.addSubview(self.button)
            self.avatarContent.addSubview(self.avatarContainer)
            self.button.addSubview(self.avatarContent)
            
            self.button.addSubview(self.titleContainer)
            
            self.avatarContent.layer.addSublayer(self.indicatorColorSeenLayer)
            self.avatarContent.layer.addSublayer(self.indicatorColorUnseenLayer)
            
            if let filter = CALayer.luminanceToAlpha() {
                self.indicatorMaskSeenLayer.filters = [filter]
                self.indicatorMaskUnseenLayer.filters = [filter]
            }
            
            self.indicatorMaskSeenLayer.backgroundColor = UIColor.black.cgColor
            self.indicatorMaskUnseenLayer.backgroundColor = UIColor.black.cgColor
            
            self.indicatorMaskSeenLayer.addSublayer(self.indicatorShapeSeenLayer)
            self.indicatorMaskUnseenLayer.addSublayer(self.indicatorShapeUnseenLayer)
            self.indicatorColorSeenLayer.mask = self.indicatorMaskSeenLayer
            self.indicatorColorUnseenLayer.mask = self.indicatorMaskUnseenLayer
            
            self.avatarShapeLayer.fillColor = UIColor.white.cgColor
            self.avatarShapeLayer.fillRule = .evenOdd
            
            self.indicatorShapeSeenLayer.fillColor = nil
            self.indicatorShapeSeenLayer.strokeColor = UIColor.white.cgColor
            self.indicatorShapeSeenLayer.lineCap = .round
            
            self.indicatorShapeUnseenLayer.fillColor = nil
            self.indicatorShapeUnseenLayer.strokeColor = UIColor.white.cgColor
            self.indicatorShapeUnseenLayer.lineCap = .round
            
            self.button.highligthedChanged = { [weak self] highlighted in
                guard let self else {
                    return
                }
                if highlighted {
                    self.alpha = 0.7
                } else {
                    let previousAlpha = self.alpha
                    self.alpha = 1.0
                    self.layer.animateAlpha(from: previousAlpha, to: self.alpha, duration: 0.25)
                }
            }
            self.button.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
            
            self.containerNode.activated = { [weak self] gesture, _ in
                guard let self, let component = self.component else {
                    return
                }
                self.button.isEnabled = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        return
                    }
                    self.button.isEnabled = true
                }
                component.contextGesture(self.extractedContainerNode, gesture, component.peer)
            }
            self.containerNode.additionalActivationProgressLayer = self.avatarBackgroundContainer.layer
            
            self.extractedContainerNode.willUpdateIsExtractedToContextPreview = { [weak self] isExtracted, transition in
                guard let self, let component = self.component else {
                    return
                }
                
                if isExtracted {
                    self.extractedBackgroundView.image = generateStretchableFilledCircleImage(diameter: 24.0, color: component.theme.contextMenu.backgroundColor)
                }
                transition.updateAlpha(layer: self.extractedBackgroundView.layer, alpha: isExtracted ? 1.0 : 0.0, completion: { [weak self] _ in
                    if !isExtracted {
                        self?.extractedBackgroundView.image = nil
                    }
                })
            }
        }
        
        required public init?(coder: NSCoder) {
            preconditionFailure()
        }
        
        @objc private func pressed() {
            guard let component = self.component else {
                return
            }
            if TelegramNotesStore.isDemoMode, component.note != nil {
                self.notePressed()
                return
            }
            component.action(component.peer)
        }
        
        @objc private func notePressed() {
            guard let component = self.component else {
                return
            }
            if let noteAction = component.noteAction {
                noteAction(component.peer)
            } else {
                component.action(component.peer)
            }
        }
        
        private func updateNoteBubble(component: StoryPeerListItemComponent, previousComponent: StoryPeerListItemComponent?, avatarFrame: CGRect, effectiveScale: CGFloat, transition: ComponentTransition) {
            guard let note = component.note else {
                if let noteBubble = self.noteBubble {
                    self.noteBubble = nil
                    noteBubble.removeFromSuperview()
                }
                self.noteTimerTrackLayer?.removeFromSuperlayer()
                self.noteTimerTrackLayer = nil
                self.noteTimerLayer?.removeFromSuperlayer()
                self.noteTimerLayer = nil
                self.noteReactionLabel?.removeFromSuperview()
                self.noteReactionLabel = nil
                return
            }
            
            let noteBubble: StoryNoteBubbleView
            var isNew = false
            if let current = self.noteBubble {
                noteBubble = current
            } else {
                noteBubble = StoryNoteBubbleView()
                noteBubble.addTarget(self, action: #selector(self.notePressed), for: .touchUpInside)
                self.noteBubble = noteBubble
                self.button.addSubview(noteBubble)
                isNew = true
            }
            
            noteBubble.update(note: note, theme: component.theme)
            let bubbleSize = noteBubble.measure(maxWidth: avatarFrame.width + 16.0)
            // The bubble rests on the avatar's top edge, so the face and the circle stay visible under it.
            let bubbleCenter = CGPoint(x: avatarFrame.midX, y: avatarFrame.minY + bubbleSize.height * 0.5 - 15.0)
            noteBubble.bounds = CGRect(origin: CGPoint(), size: bubbleSize)
            transition.setPosition(view: noteBubble, position: bubbleCenter)
            transition.setScale(view: noteBubble, scale: effectiveScale)
            transition.setAlpha(view: noteBubble, alpha: component.expandedAlphaFraction)
            noteBubble.isUserInteractionEnabled = component.expandedAlphaFraction > 0.5
            
            let isAccount = component.peer.id == component.context.account.peerId
            if isAccount {
                TelegramNotesStore.shared(context: component.context).accountBubbleView = noteBubble
            }
            
            self.updateNoteTimer(component: component, note: note, avatarFrame: avatarFrame)
            self.updateNoteReaction(component: component, note: note, previousReaction: previousComponent?.note?.reaction, avatarFrame: avatarFrame)
            
            // A new story id means a new Note, even when its text is the same as the last one's.
            let noteChanged = previousComponent?.note?.storyId != note.storyId
            if (isNew || noteChanged) && !note.isPlaceholder && !UIAccessibility.isReduceMotionEnabled {
                if isAccount && !isNew {
                    noteBubble.layer.animateSpring(from: 0.7 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.8, damping: 22.0)
                    self.playNoteLanding(avatarFrame: avatarFrame, color: component.theme.list.itemAccentColor)
                } else {
                    noteBubble.layer.animateSpring(from: 0.2 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.7, damping: 30.0)
                }
            }
        }
        
        // The time a Note has left, drawn where a Story's ring would be. It runs out like a secret chat's timer.
        private func updateNoteTimer(component: StoryPeerListItemComponent, note: StoryPeerListItemComponent.Note, avatarFrame: CGRect) {
            guard let fraction = note.timeLeftFraction else {
                self.noteTimerTrackLayer?.removeFromSuperlayer()
                self.noteTimerTrackLayer = nil
                self.noteTimerLayer?.removeFromSuperlayer()
                self.noteTimerLayer = nil
                return
            }
            let trackLayer: CAShapeLayer
            let timerLayer: CAShapeLayer
            if let currentTrack = self.noteTimerTrackLayer, let currentTimer = self.noteTimerLayer {
                trackLayer = currentTrack
                timerLayer = currentTimer
            } else {
                trackLayer = CAShapeLayer()
                timerLayer = CAShapeLayer()
                for layer in [trackLayer, timerLayer] {
                    layer.fillColor = nil
                    layer.lineWidth = 2.0
                    layer.lineCap = .round
                    self.avatarContent.layer.addSublayer(layer)
                }
                self.noteTimerTrackLayer = trackLayer
                self.noteTimerLayer = timerLayer
            }
            let center = CGPoint(x: avatarFrame.width * 0.5, y: avatarFrame.height * 0.5)
            let path = UIBezierPath(arcCenter: center, radius: avatarFrame.width * 0.5 + 3.0, startAngle: -.pi * 0.5, endAngle: .pi * 1.5, clockwise: true).cgPath
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trackLayer.path = path
            timerLayer.path = path
            trackLayer.strokeColor = component.theme.list.itemSecondaryTextColor.withAlphaComponent(0.22).cgColor
            timerLayer.strokeColor = component.theme.list.itemAccentColor.cgColor
            timerLayer.strokeEnd = fraction
            trackLayer.opacity = Float(component.expandedAlphaFraction)
            timerLayer.opacity = Float(component.expandedAlphaFraction)
            CATransaction.commit()
        }
        
        private func updateNoteReaction(component: StoryPeerListItemComponent, note: StoryPeerListItemComponent.Note, previousReaction: String?, avatarFrame: CGRect) {
            guard let reaction = note.reaction else {
                self.noteReactionLabel?.removeFromSuperview()
                self.noteReactionLabel = nil
                return
            }
            let label: UILabel
            if let current = self.noteReactionLabel {
                label = current
            } else {
                label = UILabel()
                label.font = UIFont.systemFont(ofSize: 12.0)
                label.textAlignment = .center
                label.layer.cornerRadius = 10.0
                label.clipsToBounds = true
                label.isUserInteractionEnabled = false
                self.button.addSubview(label)
                self.noteReactionLabel = label
            }
            label.text = reaction
            label.backgroundColor = component.theme.rootController.navigationBar.opaqueBackgroundColor
            label.frame = CGRect(x: avatarFrame.maxX - 17.0, y: avatarFrame.maxY - 17.0, width: 20.0, height: 20.0)
            label.alpha = component.expandedAlphaFraction
            if previousReaction != reaction && !UIAccessibility.isReduceMotionEnabled {
                label.layer.animateSpring(from: 0.2 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.6, damping: 24.0)
            }
        }
        
        // The avatar takes the Note's weight, a ring spreads from it, and the timer draws itself in.
        private func playNoteLanding(avatarFrame: CGRect, color: UIColor) {
            let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
            bounce.values = [0.0, -0.1, 0.07, -0.02, 0.0]
            bounce.keyTimes = [0.0, 0.2, 0.5, 0.78, 1.0]
            bounce.isAdditive = true
            bounce.duration = 0.6
            self.avatarContent.layer.add(bounce, forKey: "noteLanding")
            
            if let timerLayer = self.noteTimerLayer {
                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0.0
                draw.toValue = timerLayer.strokeEnd
                draw.duration = 0.75
                draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
                timerLayer.add(draw, forKey: "noteLanding")
            }
            
            let center = CGPoint(x: avatarFrame.midX, y: avatarFrame.midY)
            let ripple = CAShapeLayer()
            ripple.path = UIBezierPath(arcCenter: CGPoint(), radius: avatarFrame.width * 0.5 + 3.0, startAngle: 0.0, endAngle: .pi * 2.0, clockwise: true).cgPath
            ripple.position = center
            ripple.fillColor = nil
            ripple.strokeColor = color.cgColor
            ripple.lineWidth = 2.0
            ripple.opacity = 0.0
            self.button.layer.addSublayer(ripple)
            
            let rippleScale = CABasicAnimation(keyPath: "transform.scale")
            rippleScale.fromValue = 1.0
            rippleScale.toValue = 1.55
            let rippleFade = CABasicAnimation(keyPath: "opacity")
            rippleFade.fromValue = 0.85
            rippleFade.toValue = 0.0
            let rippleGroup = CAAnimationGroup()
            rippleGroup.animations = [rippleScale, rippleFade]
            rippleGroup.duration = 0.65
            rippleGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ripple.add(rippleGroup, forKey: "ripple")
            
            let sparkleColors = [color, UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1.0), UIColor(red: 1.0, green: 0.42, blue: 0.62, alpha: 1.0)]
            let sparkleCount = 12
            var sparkles: [CALayer] = [ripple]
            for index in 0 ..< sparkleCount {
                let angle = CGFloat(index) / CGFloat(sparkleCount) * .pi * 2.0 + CGFloat.random(in: -0.12 ... 0.12)
                let start = CGPoint(x: center.x + cos(angle) * avatarFrame.width * 0.5, y: center.y + sin(angle) * avatarFrame.width * 0.5)
                let distance = avatarFrame.width * 0.5 + CGFloat.random(in: 18.0 ... 34.0)
                let side = CGFloat.random(in: 3.0 ... 5.0)
                let sparkle = CALayer()
                sparkle.bounds = CGRect(x: 0.0, y: 0.0, width: side, height: side)
                sparkle.cornerRadius = side * 0.5
                sparkle.backgroundColor = sparkleColors[index % sparkleColors.count].cgColor
                sparkle.position = start
                sparkle.opacity = 0.0
                self.button.layer.addSublayer(sparkle)
                sparkles.append(sparkle)
                
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(cgPoint: start)
                move.toValue = NSValue(cgPoint: CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance))
                let shrink = CABasicAnimation(keyPath: "transform.scale")
                shrink.fromValue = 1.0
                shrink.toValue = 0.2
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [1.0, 1.0, 0.0]
                fade.keyTimes = [0.0, 0.55, 1.0]
                let group = CAAnimationGroup()
                group.animations = [move, shrink, fade]
                group.duration = 0.7
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                sparkle.add(group, forKey: "sparkle")
            }
            Queue.mainQueue().after(0.8, {
                for layer in sparkles {
                    layer.removeFromSuperlayer()
                }
            })
        }
        
        public func transitionView() -> UIView? {
            return self.avatarNode?.view
        }
        
        func updateIsPreviewing(isPreviewing: Bool) {
            self.avatarContent.alpha = isPreviewing ? 0.0 : 1.0
            self.avatarBackgroundView.alpha = isPreviewing ? 0.0 : 1.0
        }
        
        func update(component: StoryPeerListItemComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let size = availableSize
            
            let themeUpdated = self.component?.theme !== component.theme
            
            let previousComponent = self.component
            
            self.component = component
            self.componentState = state
            
            let effectiveWidth: CGFloat = component.scale * component.fullWidth
            
            let effectiveScale: CGFloat = component.scale
            
            let avatarNode: AvatarNode
            if let current = self.avatarNode {
                avatarNode = current
            } else {
                avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 26.0))
                self.avatarNode = avatarNode
                avatarNode.layer.mask = self.avatarShapeLayer
                avatarNode.isUserInteractionEnabled = false
                self.avatarContainer.addSubview(avatarNode.view)
            }
            
            let avatarSize = CGSize(width: 52.0, height: 52.0)
            
            let avatarBackgroundImage: UIImage?
            if let sharedAvatarBackgroundImage = sharedAvatarBackgroundImage, sharedAvatarBackgroundImage.size.width == avatarSize.width {
                avatarBackgroundImage = sharedAvatarBackgroundImage
            } else {
                avatarBackgroundImage = generateFilledCircleImage(diameter: avatarSize.width, color: .white)?.withRenderingMode(.alwaysTemplate)
            }
            self.avatarBackgroundView.image = avatarBackgroundImage
            
            if themeUpdated {
                self.avatarBackgroundView.tintColor = component.theme.rootController.navigationBar.opaqueBackgroundColor
            }
            
            let avatarFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - avatarSize.width) * 0.5) + (effectiveWidth - availableSize.width) * 0.5, y: 4.0), size: avatarSize)
            
            transition.setFrame(view: avatarNode.view, frame: CGRect(origin: CGPoint(), size: avatarFrame.size))
            // The sample contacts have no profile for Telegram's context menu to open.
            self.containerNode.isGestureEnabled = !(TelegramNotesStore.isDemoMode && component.note != nil)
            if let demoAvatarImage = TelegramNotesStore.demoAvatarImage(peerId: component.peer.id, accountPeerId: component.context.account.peerId) {
                let demoAvatarView: UIImageView
                if let current = self.demoAvatarView {
                    demoAvatarView = current
                } else {
                    demoAvatarView = UIImageView()
                    self.demoAvatarView = demoAvatarView
                    avatarNode.view.addSubview(demoAvatarView)
                }
                demoAvatarView.image = demoAvatarImage
                demoAvatarView.frame = CGRect(origin: CGPoint(), size: avatarFrame.size)
            } else if let demoAvatarView = self.demoAvatarView {
                self.demoAvatarView = nil
                demoAvatarView.removeFromSuperview()
            }
            transition.setFrame(view: self.avatarBackgroundView, frame: CGRect(origin: CGPoint(), size: avatarFrame.size).insetBy(dx: -3.0 - UIScreenPixel * 2.0, dy: -3.0 - UIScreenPixel * 2.0))
            
            let indicatorFrame = avatarFrame.insetBy(dx: -8.0, dy: -8.0)
            
            let baseLineUnseenWidth: CGFloat = 2.33
            let baseLineSeenWidth: CGFloat = 1.33
            
            let minimizedLineWidth: CGFloat = 4.3
            
            let normalizedScale = max(0.0, min(1.0, component.scale))
            let indicatorLineSeenWidth: CGFloat = baseLineSeenWidth * normalizedScale + minimizedLineWidth * (1.0 - normalizedScale)
            let indicatorLineUnseenWidth: CGFloat = baseLineUnseenWidth * normalizedScale + minimizedLineWidth * (1.0 - normalizedScale)
            
            avatarNode.setPeer(
                context: component.context,
                theme: component.theme,
                peer: component.peer
            )
            avatarNode.updateSize(size: avatarSize)
            
            transition.setPosition(view: self.avatarContent, position: CGPoint(x: avatarFrame.midX, y: avatarFrame.midY))
            transition.setBounds(view: self.avatarContent, bounds: CGRect(origin: CGPoint(), size: avatarFrame.size))
            
            transition.setPosition(view: self.avatarContainer, position: CGPoint(x: avatarFrame.width * 0.5, y: avatarFrame.height * 0.5))
            transition.setBounds(view: self.avatarContainer, bounds: CGRect(origin: CGPoint(), size: avatarFrame.size))
            
            transition.setPosition(view: self.avatarBackgroundContainer, position: avatarFrame.center)
            transition.setBounds(view: self.avatarBackgroundContainer, bounds: CGRect(origin: CGPoint(), size: avatarFrame.size))
            
            let scaledAvatarSize = effectiveScale * avatarSize.width
            
            transition.setScale(view: self.avatarContainer, scale: scaledAvatarSize / avatarSize.width)
            transition.setScale(view: self.avatarBackgroundContainer, scale: scaledAvatarSize / avatarSize.width)
            
            // The add badge goes away once the account has a Note: the bubble is then the way to edit it.
            if component.peer.id == component.context.account.peerId && !component.hasItems && component.ringAnimation == nil && component.note?.isPlaceholder != false {
                self.indicatorColorSeenLayer.isHidden = true
                self.indicatorColorUnseenLayer.isHidden = true
                
                let avatarAddBadgeView: UIImageView
                var avatarAddBadgeTransition = transition
                if let current = self.avatarAddBadgeView {
                    avatarAddBadgeView = current
                } else {
                    avatarAddBadgeTransition = .immediate
                    avatarAddBadgeView = UIImageView()
                    self.avatarAddBadgeView = avatarAddBadgeView
                    self.avatarContainer.addSubview(avatarAddBadgeView)
                }
                let badgeSize = CGSize(width: 16.0, height: 16.0)
                if avatarAddBadgeView.image == nil || themeUpdated {
                    avatarAddBadgeView.image = generateImage(badgeSize, rotatedContext: { size, context in
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(component.theme.list.itemCheckColors.fillColor.cgColor)
                        context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
                        
                        context.setStrokeColor(component.theme.list.itemCheckColors.foregroundColor.cgColor)
                        context.setLineWidth(UIScreenPixel * 3.0)
                        context.setLineCap(.round)
                        
                        let lineSize: CGFloat = 9.0 + UIScreenPixel
                        
                        context.move(to: CGPoint(x: size.width * 0.5, y: (size.height - lineSize) * 0.5))
                        context.addLine(to: CGPoint(x: size.width * 0.5, y: (size.height - lineSize) * 0.5 + lineSize))
                        context.strokePath()
                        
                        context.move(to: CGPoint(x: (size.width - lineSize) * 0.5, y: size.height * 0.5))
                        context.addLine(to: CGPoint(x: (size.width - lineSize) * 0.5 + lineSize, y: size.height * 0.5))
                        context.strokePath()
                    })
                }
                avatarAddBadgeTransition.setFrame(view: avatarAddBadgeView, frame: CGRect(origin: CGPoint(x: avatarFrame.width - 1.0 - badgeSize.width, y: avatarFrame.height - 2.0 - badgeSize.height), size: badgeSize))
            } else {
                self.indicatorColorSeenLayer.isHidden = false
                self.indicatorColorUnseenLayer.isHidden = false
                
                if let avatarAddBadgeView = self.avatarAddBadgeView {
                    self.avatarAddBadgeView = nil
                    avatarAddBadgeView.removeFromSuperview()
                }
            }
            
            if component.hasLiveItems {
                let avatarLiveBadgeView: UIImageView
                var avatarLiveBadgeTransition = transition
                if let current = self.avatarLiveBadgeView {
                    avatarLiveBadgeView = current
                } else {
                    avatarLiveBadgeTransition = avatarLiveBadgeTransition.withAnimation(.none)
                    avatarLiveBadgeView = UIImageView()
                    self.avatarLiveBadgeView = avatarLiveBadgeView
                    self.avatarContainer.addSubview(avatarLiveBadgeView)
                }
                let avatarLiveBadgeMaskSeenLayer: SimpleLayer
                if let current = self.avatarLiveBadgeMaskSeenLayer {
                    avatarLiveBadgeMaskSeenLayer = current
                } else {
                    avatarLiveBadgeMaskSeenLayer = SimpleLayer()
                    avatarLiveBadgeMaskSeenLayer.backgroundColor = UIColor.black.cgColor
                    self.avatarLiveBadgeMaskSeenLayer = avatarLiveBadgeMaskSeenLayer
                    self.indicatorMaskSeenLayer.addSublayer(avatarLiveBadgeMaskSeenLayer)
                }
                let avatarLiveBadgeMaskUnseenLayer: SimpleLayer
                if let current = self.avatarLiveBadgeMaskUnseenLayer {
                    avatarLiveBadgeMaskUnseenLayer = current
                } else {
                    avatarLiveBadgeMaskUnseenLayer = SimpleLayer()
                    avatarLiveBadgeMaskUnseenLayer.backgroundColor = UIColor.black.cgColor
                    self.avatarLiveBadgeMaskUnseenLayer = avatarLiveBadgeMaskUnseenLayer
                    self.indicatorMaskUnseenLayer.addSublayer(avatarLiveBadgeMaskUnseenLayer)
                }
                if avatarLiveBadgeView.image == nil || themeUpdated {
                    let liveString = NSAttributedString(string: component.strings.Story_LiveBadge, font: Font.semibold(10.0), textColor: .white)
                    let liveStringBounds = liveString.boundingRect(with: CGSize(width: 100.0, height: 100.0), options: .usesLineFragmentOrigin, context: nil)
                    let liveBadgeSize = CGSize(width: ceil(liveStringBounds.width) + 4.0 * 2.0, height: ceil(liveStringBounds.height) + 2.0 * 2.0)
                    avatarLiveBadgeView.image = generateImage(liveBadgeSize, rotatedContext: { size, context in
                        UIGraphicsPushContext(context)
                        defer {
                            UIGraphicsPopContext()
                        }
                        
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        context.setFillColor(UIColor(rgb: 0xFF2D55).cgColor)
                        context.addPath(UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: size.height * 0.5).cgPath)
                        context.fillPath()
                        
                        liveString.draw(at: CGPoint(x: floorToScreenPixels((size.width - liveStringBounds.width) * 0.5), y: floorToScreenPixels((size.height - liveStringBounds.height) * 0.5)))
                    })
                }
                if let image = avatarLiveBadgeView.image {
                    let badgeSize = image.size
                    let badgeFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((avatarFrame.width - badgeSize.width) * 0.5), y: avatarFrame.height + 5.0 - badgeSize.height), size: badgeSize)
                    avatarLiveBadgeTransition.setPosition(view: avatarLiveBadgeView, position: badgeFrame.center)
                    avatarLiveBadgeTransition.setBounds(view: avatarLiveBadgeView, bounds: CGRect(origin: CGPoint(), size: badgeFrame.size))
                    
                    avatarLiveBadgeTransition.setScale(view: avatarLiveBadgeView, scale: max(0.00001, component.expandedAlphaFraction))
                    avatarLiveBadgeTransition.setAlpha(view: avatarLiveBadgeView, alpha: component.expandedAlphaFraction)
                    
                    avatarLiveBadgeMaskSeenLayer.frame = badgeFrame.offsetBy(dx: 8.0, dy: 8.0).insetBy(dx: -2.0, dy: -2.0)
                    avatarLiveBadgeMaskSeenLayer.cornerRadius = avatarLiveBadgeMaskSeenLayer.bounds.height * 0.5
                    avatarLiveBadgeMaskUnseenLayer.frame = badgeFrame.offsetBy(dx: 8.0, dy: 8.0).insetBy(dx: -2.0, dy: -2.0)
                    avatarLiveBadgeMaskUnseenLayer.cornerRadius = avatarLiveBadgeMaskUnseenLayer.bounds.height * 0.5
                    
                    avatarLiveBadgeTransition.setScale(layer: avatarLiveBadgeMaskSeenLayer, scale: max(0.00001, component.expandedAlphaFraction))
                    avatarLiveBadgeTransition.setAlpha(layer: avatarLiveBadgeMaskSeenLayer, alpha: component.expandedAlphaFraction)
                    
                    avatarLiveBadgeTransition.setScale(layer: avatarLiveBadgeMaskUnseenLayer, scale: max(0.00001, component.expandedAlphaFraction))
                    avatarLiveBadgeTransition.setAlpha(layer: avatarLiveBadgeMaskUnseenLayer, alpha: component.expandedAlphaFraction)
                }
            } else {
                if let avatarLiveBadgeView = self.avatarLiveBadgeView {
                    self.avatarLiveBadgeView = nil
                    avatarLiveBadgeView.removeFromSuperview()
                }
                if let avatarLiveBadgeMaskSeenLayer = self.avatarLiveBadgeMaskSeenLayer {
                    self.avatarLiveBadgeMaskSeenLayer = nil
                    avatarLiveBadgeMaskSeenLayer.removeFromSuperlayer()
                }
                if let avatarLiveBadgeMaskUnseenLayer = self.avatarLiveBadgeMaskUnseenLayer {
                    self.avatarLiveBadgeMaskUnseenLayer = nil
                    avatarLiveBadgeMaskUnseenLayer.removeFromSuperlayer()
                }
            }
            
            if TelegramNotesStore.demoAvatarImage(peerId: component.peer.id, accountPeerId: component.context.account.peerId) != nil {
                // In the concept a Note is not a Story, so the avatar carries no Story ring.
                self.indicatorColorSeenLayer.isHidden = true
                self.indicatorColorUnseenLayer.isHidden = true
            }
            
            self.avatarBackgroundView.isHidden = component.ringAnimation != nil || self.indicatorColorSeenLayer.isHidden
            
            let baseRadius: CGFloat = 30.66
            let collapsedRadius: CGFloat = 35.0
            var indicatorRadius: CGFloat = baseRadius * normalizedScale + collapsedRadius * (1.0 - normalizedScale)
            if component.scale > 1.0 {
                indicatorRadius += max(0.0, component.scale - 1.0) * 0.0
            }
            
            self.indicatorShapeSeenLayer.lineWidth = indicatorLineSeenWidth
            self.indicatorShapeUnseenLayer.lineWidth = indicatorLineUnseenWidth
            
            let locations: [CGFloat] = [0.0, 1.0]
            let seenColors: [CGColor]
            let unseenColors: [CGColor]
            
            if component.hasLiveItems {
                unseenColors = [UIColor(rgb: 0xFF3777).cgColor, UIColor(rgb: 0xFF2D55).cgColor]
            } else if component.hasUnseenCloseFriendsItems {
                unseenColors = [component.theme.chatList.storyUnseenPrivateColors.topColor.cgColor, component.theme.chatList.storyUnseenPrivateColors.bottomColor.cgColor]
            } else {
                unseenColors = [component.theme.chatList.storyUnseenColors.topColor.cgColor, component.theme.chatList.storyUnseenColors.bottomColor.cgColor]
            }
            
            seenColors = [component.theme.chatList.storySeenColors.topColor.cgColor, component.theme.chatList.storySeenColors.bottomColor.cgColor]
            
            self.indicatorColorSeenLayer.locations = locations.map { $0 as NSNumber }
            self.indicatorColorSeenLayer.colors = seenColors
            
            self.indicatorColorUnseenLayer.locations = locations.map { $0 as NSNumber }
            self.indicatorColorUnseenLayer.colors = unseenColors
            
            transition.setPosition(layer: self.indicatorColorSeenLayer, position: indicatorFrame.offsetBy(dx: -avatarFrame.minX, dy: -avatarFrame.minY).center)
            transition.setPosition(layer: self.indicatorColorUnseenLayer, position: indicatorFrame.offsetBy(dx: -avatarFrame.minX, dy: -avatarFrame.minY).center)
            
            transition.setBounds(layer: self.indicatorColorSeenLayer, bounds: CGRect(origin: CGPoint(), size: indicatorFrame.size))
            transition.setBounds(layer: self.indicatorColorUnseenLayer, bounds: CGRect(origin: CGPoint(), size: indicatorFrame.size))
            
            transition.setPosition(layer: self.indicatorShapeSeenLayer, position: CGPoint(x: indicatorFrame.width * 0.5, y: indicatorFrame.height * 0.5))
            transition.setPosition(layer: self.indicatorShapeUnseenLayer, position: CGPoint(x: indicatorFrame.width * 0.5, y: indicatorFrame.height * 0.5))
            
            transition.setBounds(layer: self.indicatorShapeSeenLayer, bounds: CGRect(origin: CGPoint(), size: indicatorFrame.size))
            transition.setBounds(layer: self.indicatorShapeUnseenLayer, bounds: CGRect(origin: CGPoint(), size: indicatorFrame.size))
            
            transition.setScale(layer: self.indicatorColorSeenLayer, scale: effectiveScale)
            transition.setScale(layer: self.indicatorColorUnseenLayer, scale: effectiveScale)
            
            let indicatorCenter = CGRect(origin: CGPoint(), size: indicatorFrame.size).center
            
            var mappedLeftCenter: CGPoint?
            var mappedRightCenter: CGPoint?
            
            if let leftNeighborDistance = component.leftNeighborDistance {
                mappedLeftCenter = CGPoint(x: indicatorCenter.x - leftNeighborDistance.x * (1.0 / effectiveScale), y: indicatorCenter.y + leftNeighborDistance.y * (1.0 / effectiveScale))
            }
            if let rightNeighborDistance = component.rightNeighborDistance {
                mappedRightCenter = CGPoint(x: indicatorCenter.x + rightNeighborDistance.x * (1.0 / effectiveScale), y: indicatorCenter.y + rightNeighborDistance.y * (1.0 / effectiveScale))
            }
            
            let avatarPath = CGMutablePath()
            avatarPath.addEllipse(in: CGRect(origin: CGPoint(), size: avatarSize).insetBy(dx: -1.0, dy: -1.0))
            if let avatarLiveBadgeView = self.avatarLiveBadgeView {
                let avatarLiveBadgeFrame = avatarLiveBadgeView.frame
                if avatarLiveBadgeFrame.height > 4.0 {
                    avatarPath.addPath(UIBezierPath(roundedRect: avatarLiveBadgeFrame.insetBy(dx: -2.0, dy: -2.0), cornerRadius: avatarLiveBadgeFrame.height * 0.5).cgPath)
                }
            } else if component.peer.id == component.context.account.peerId && !component.hasItems && component.ringAnimation == nil && component.note?.isPlaceholder != false {
                let cutoutSize: CGFloat = 18.0 + UIScreenPixel * 2.0
                avatarPath.addEllipse(in: CGRect(origin: CGPoint(x: avatarSize.width - cutoutSize + UIScreenPixel, y: avatarSize.height - 1.0 - cutoutSize + UIScreenPixel), size: CGSize(width: cutoutSize, height: cutoutSize)))
            } else if let mappedLeftCenter {
                avatarPath.addEllipse(in: CGRect(origin: CGPoint(), size: avatarSize).insetBy(dx: -indicatorLineSeenWidth * 1.4, dy: -indicatorLineSeenWidth * 1.4).offsetBy(dx: -abs(indicatorCenter.x - mappedLeftCenter.x), dy: -abs(indicatorCenter.y - mappedLeftCenter.y)))
            }
            ComponentTransition.immediate.setShapeLayerPath(layer: self.avatarShapeLayer, path: avatarPath)
            
            ComponentTransition.immediate.setShapeLayerPath(layer: self.indicatorShapeSeenLayer, path: calculateMergingCircleShape(center: indicatorCenter, leftCenter: mappedLeftCenter, rightCenter: mappedRightCenter, radius: indicatorRadius - indicatorLineUnseenWidth * 0.5, totalCount: component.hasLiveItems ? 1 : component.totalCount, unseenCount: component.hasLiveItems ? 1 : component.unseenCount, isSeen: true, segmentFraction: component.expandedAlphaFraction, rotationFraction: component.expandEffectFraction))
            ComponentTransition.immediate.setShapeLayerPath(layer: self.indicatorShapeUnseenLayer, path: calculateMergingCircleShape(center: indicatorCenter, leftCenter: mappedLeftCenter, rightCenter: mappedRightCenter, radius: indicatorRadius - indicatorLineUnseenWidth * 0.5, totalCount: component.hasLiveItems ? 1 : component.totalCount, unseenCount: component.hasLiveItems ? 1 : component.unseenCount, isSeen: false, segmentFraction: component.expandedAlphaFraction, rotationFraction: component.expandEffectFraction))
            
            let titleString: String
            if component.peer.id == component.context.account.peerId {
                if let ringAnimation = component.ringAnimation, case .progress = ringAnimation {
                    titleString = component.strings.StoryFeed_MyUploading
                } else {
                    titleString = TelegramNotesStrings.string("NotesYours")
                }
            } else {
                titleString = component.peer.compactDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            var titleTransition = transition
            if let previousAnimation = previousComponent?.ringAnimation, case .progress = previousAnimation, component.ringAnimation == nil {
                if let titleView = self.title.view, let snapshotView = titleView.snapshotView(afterScreenUpdates: false) {
                    self.titleContainer.addSubview(snapshotView)
                    snapshotView.frame = titleView.frame
                    snapshotView.layer.animateAlpha(from: component.expandedAlphaFraction, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                        snapshotView?.removeFromSuperview()
                    })
                    titleView.layer.animateAlpha(from: 0.0, to: component.expandedAlphaFraction, duration: 0.25)
                }
                titleTransition = .immediate
                
                self.avatarContent.layer.transform = CATransform3DMakeScale(1.08, 1.08, 1.0)
                self.avatarContent.layer.animateScale(from: 1.0, to: 1.08, duration: 0.2, completion: { [weak self] _ in
                    self?.avatarContent.layer.transform = CATransform3DMakeScale(1.0, 1.0, 1.0)
                    self?.avatarContent.layer.animateScale(from: 1.08, to: 1.0, duration: 0.15)
                })
                
                let initialLineWidth: CGFloat = baseLineUnseenWidth
                let targetLineWidth: CGFloat = baseLineUnseenWidth * 1.5
                self.indicatorShapeSeenLayer.lineWidth = targetLineWidth
                self.indicatorShapeSeenLayer.animateShapeLineWidth(from: initialLineWidth, to: targetLineWidth, duration: 0.2, completion: { [weak self] _ in
                    self?.indicatorShapeSeenLayer.lineWidth = initialLineWidth
                    self?.indicatorShapeSeenLayer.animateShapeLineWidth(from: targetLineWidth, to: initialLineWidth, duration: 0.15)
                })
                
                if self.window != nil {
                    HapticFeedback().success()
                }
            }
            
            let iconContainerSize = CGSize(width: 12.0, height: 12.0)
            let iconSpacing: CGFloat = 1.0
            
            var currentVerifiedIconContent: EmojiStatusComponent.Content?
            if component.peer.isVerified {
                currentVerifiedIconContent = .verified(fillColor: component.theme.list.itemCheckColors.fillColor, foregroundColor: component.theme.list.itemCheckColors.foregroundColor, sizeType: .smaller)
            }
            var titleConstrainedSize = CGSize(width: availableSize.width + 12.0, height: 100.0)
            if let _ = currentVerifiedIconContent {
                titleConstrainedSize.width -= iconContainerSize.width + iconSpacing
            }
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: titleString, font: Font.regular(11.0), textColor: (component.unseenCount != 0 || component.hasLiveItems || component.peer.id == component.context.account.peerId) ? component.theme.list.itemPrimaryTextColor : component.theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.5))),
                    maximumNumberOfLines: 1
                )),
                environment: {},
                containerSize: titleConstrainedSize
            )
            
            var totalTitleWidth = titleSize.width
            if let currentVerifiedIconContent {
                let verifiedIconView: ComponentHostView<Empty>
                if let current = self.verifiedIconView {
                    verifiedIconView = current
                } else {
                    verifiedIconView = ComponentHostView<Empty>()
                    verifiedIconView.isUserInteractionEnabled = false
                    self.verifiedIconView = verifiedIconView
                    self.titleContainer.addSubview(verifiedIconView)
                }
                let verifiedIconComponent = EmojiStatusComponent(
                    context: component.context,
                    animationCache: component.context.animationCache,
                    animationRenderer: component.context.animationRenderer,
                    content: currentVerifiedIconContent,
                    size: iconContainerSize,
                    isVisibleForAnimations: component.context.sharedContext.energyUsageSettings.loopEmoji,
                    action: nil
                )

                let iconSize = verifiedIconView.update(
                    transition: .immediate,
                    component: AnyComponent(verifiedIconComponent),
                    environment: {},
                    containerSize: iconContainerSize
                )
                totalTitleWidth += iconSize.width + iconSpacing
                
                let verifiedIconFrame = CGRect(origin: CGPoint(x: totalTitleWidth - iconSize.width, y: UIScreenPixel), size: iconSize)
                titleTransition.setFrame(view: verifiedIconView, frame: verifiedIconFrame)
            } else if let verifiedIconView = self.verifiedIconView {
                self.verifiedIconView = nil
                verifiedIconView.removeFromSuperview()
            }
            
            let titleFrame = CGRect(origin: .zero, size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    titleView.isUserInteractionEnabled = false
                    self.titleContainer.addSubview(titleView)
                }
                titleTransition.setPosition(view: titleView, position: titleFrame.center)
                titleView.bounds = CGRect(origin: CGPoint(), size: titleFrame.size)
            }
            
            let titleContainerSize = CGSize(width: totalTitleWidth, height: titleSize.height)
            let titleContainerFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - titleContainerSize.width) * 0.5) + (effectiveWidth - availableSize.width) * 0.5, y: indicatorFrame.midY + (indicatorFrame.height * 0.5 + 2.0) * effectiveScale), size: titleContainerSize)
            
            titleTransition.setPosition(view: self.titleContainer, position: titleContainerFrame.center)
            self.titleContainer.bounds = CGRect(origin: CGPoint(), size: titleContainerFrame.size)
            titleTransition.setScale(view: self.titleContainer, scale: effectiveScale)
            
            self.updateNoteBubble(component: component, previousComponent: previousComponent, avatarFrame: avatarFrame, effectiveScale: effectiveScale, transition: transition)
            titleTransition.setAlpha(view: self.titleContainer, alpha: component.expandedAlphaFraction)
            
            if let ringAnimation = component.ringAnimation {
                var progressTransition = transition
                let progressLayer: StoryProgressLayer
                if let current = self.progressLayer {
                    progressLayer = current
                } else {
                    progressTransition = .immediate
                    progressLayer = StoryProgressLayer()
                    self.progressLayer = progressLayer
                    self.indicatorMaskUnseenLayer.addSublayer(progressLayer)
                }
                let progressFrame = CGRect(origin: CGPoint(), size: indicatorFrame.size).insetBy(dx: 4.0, dy: 4.0)
                progressTransition.setFrame(layer: progressLayer, frame: progressFrame)
                
                switch ringAnimation {
                case let .progress(progress):
                    let progressTransition: ComponentTransition
                    if abs(progress - 0.028) < 0.001 {
                        progressTransition = .immediate
                    } else {
                        progressTransition = .easeInOut(duration: 0.3)
                    }
                    progressLayer.update(size: progressFrame.size, lineWidth: indicatorLineUnseenWidth, radius: indicatorRadius - indicatorLineUnseenWidth * 0.5, value: .progress(progress), transition: progressTransition)
                case .loading:
                    progressLayer.update(size: progressFrame.size, lineWidth: indicatorLineUnseenWidth, radius: indicatorRadius - indicatorLineUnseenWidth * 0.5, value: .indefinite, transition: transition)
                }
                
                self.indicatorShapeSeenLayer.opacity = 0.0
                self.indicatorShapeUnseenLayer.opacity = 0.0
                
                if let previousComponent = previousComponent, previousComponent.ringAnimation == nil {
                    progressLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                    self.indicatorShapeSeenLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                    self.indicatorShapeUnseenLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                }
            } else {
                self.indicatorShapeSeenLayer.opacity = 1.0
                self.indicatorShapeUnseenLayer.opacity = 1.0
                
                if let progressLayer = self.progressLayer {
                    self.indicatorShapeSeenLayer.opacity = 1.0
                    self.indicatorShapeUnseenLayer.opacity = 1.0
                    
                    self.indicatorShapeSeenLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                    self.indicatorShapeUnseenLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                    
                    self.progressLayer = nil
                    if transition.animation.isImmediate {
                        progressLayer.reset()
                        progressLayer.removeFromSuperlayer()
                    } else {
                        progressLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak progressLayer] _ in
                            progressLayer?.reset()
                            progressLayer?.removeFromSuperlayer()
                        })
                    }
                }
            }
            
            let extractedBackgroundWidth = max(size.width + 8.0, titleSize.width + 10.0)
            transition.setFrame(view: self.button, frame: CGRect(origin: CGPoint(), size: size))
            transition.setFrame(view: self.extractedBackgroundView, frame: CGRect(origin: CGPoint(x: floor((size.width - extractedBackgroundWidth) * 0.5), y: -4.0), size: CGSize(width: extractedBackgroundWidth, height: size.height + 8.0)))
            
            self.extractedContainerNode.frame = CGRect(origin: CGPoint(), size: size)
            self.extractedContainerNode.contentNode.frame = CGRect(origin: CGPoint(), size: size)
            self.extractedContainerNode.contentRect = CGRect(origin: CGPoint(x: self.extractedBackgroundView.frame.minX - 2.0, y: self.extractedBackgroundView.frame.minY), size: CGSize(width: self.extractedBackgroundView.frame.width + 4.0, height: self.extractedBackgroundView.frame.height))
            self.containerNode.frame = CGRect(origin: CGPoint(), size: size)
            
            var baseSize: CGFloat = 60.0
            var effectiveColors = component.unseenCount > 0 ? unseenColors : seenColors
            if self.avatarAddBadgeView != nil {
                baseSize = 52.0
                effectiveColors = [component.theme.list.itemCheckColors.fillColor.cgColor, component.theme.list.itemCheckColors.fillColor.cgColor]
            }
            if let composeContentOffset = component.composeContentOffset {
                let composeLayer: StoryComposeLayer
                if let current = self.composeLayer {
                    composeLayer = current
                } else {
                    composeLayer = StoryComposeLayer(theme: component.theme, strings: component.strings)
                    self.composeLayer = composeLayer
                    self.layer.addSublayer(composeLayer)
                }
                                
                composeLayer.frame = CGRect(origin: CGPoint(x: size.width - 195.0, y: 0.0), size: CGSize(width: 160.0, height: 60.0))
                composeLayer.updateOffset(composeContentOffset, baseSize: baseSize, colors: effectiveColors, transition: transition)
            } else if let composeLayer = self.composeLayer {
                self.composeLayer = nil
                composeLayer.updateOffset(0.0, baseSize: baseSize, colors: effectiveColors, transition: .easeInOut(duration: 0.2))
                Queue.mainQueue().after(0.21, {
                    composeLayer.removeFromSuperlayer()
                })
            }
            
            return availableSize
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

// The speech bubble a Note is drawn in. The account's placeholder uses the accent color, contacts' Notes use the item background.
private final class StoryNoteBubbleView: UIControl {
    private let backgroundView = UIView()
    private let label = UILabel()
    private var isPlaceholder = false
    private var dustNode: InvisibleInkDustNode?
    private var dustColor: UIColor = .white
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundView.isUserInteractionEnabled = false
        self.backgroundView.layer.shadowColor = UIColor.black.cgColor
        self.backgroundView.layer.shadowOpacity = 0.18
        self.backgroundView.layer.shadowRadius = 3.0
        self.backgroundView.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
        self.addSubview(self.backgroundView)
        
        self.label.font = Font.medium(10.5)
        self.label.textAlignment = .center
        self.label.lineBreakMode = .byTruncatingTail
        self.label.numberOfLines = 1
        self.addSubview(self.label)
        
        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure()
    }
    
    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }
    
    func update(note: StoryPeerListItemComponent.Note, theme: PresentationTheme) {
        self.isPlaceholder = note.isPlaceholder
        self.label.text = note.text
        self.backgroundView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.label.textColor = note.isPlaceholder ? theme.list.itemSecondaryTextColor : theme.list.itemPrimaryTextColor
        self.dustColor = theme.list.itemPrimaryTextColor
        self.label.alpha = note.isHiddenBySpoiler ? 0.0 : 1.0
        if note.isHiddenBySpoiler {
            if self.dustNode == nil {
                let dustNode = InvisibleInkDustNode(textNode: nil, enableAnimations: !UIAccessibility.isReduceMotionEnabled)
                dustNode.isUserInteractionEnabled = false
                self.addSubview(dustNode.view)
                self.dustNode = dustNode
            }
        } else if let dustNode = self.dustNode {
            self.dustNode = nil
            UIView.animate(withDuration: 0.25, animations: {
                dustNode.view.alpha = 0.0
            }, completion: { _ in
                dustNode.view.removeFromSuperview()
            })
        }
        self.accessibilityLabel = note.accessibilityLabel
    }
    
    func measure(maxWidth: CGFloat) -> CGSize {
        let textSize = self.label.sizeThatFits(CGSize(width: maxWidth - 10.0, height: 20.0))
        let size = CGSize(width: min(maxWidth, ceil(textSize.width) + 10.0), height: 21.0)
        self.backgroundView.frame = CGRect(origin: CGPoint(), size: size)
        self.backgroundView.layer.cornerRadius = size.height * 0.5
        self.label.frame = CGRect(origin: CGPoint(), size: size).insetBy(dx: 5.0, dy: 0.0)
        if let dustNode = self.dustNode {
            let dustFrame = self.label.frame.insetBy(dx: 0.0, dy: 3.0)
            let rect = CGRect(origin: CGPoint(), size: dustFrame.size)
            dustNode.frame = dustFrame
            dustNode.update(size: dustFrame.size, color: self.dustColor, textColor: self.dustColor, rects: [rect], wordRects: [rect])
        }
        return size
    }
    
    // A slightly larger touch target than the drawn bubble, without stealing taps meant for the avatar below it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.bounds.insetBy(dx: -4.0, dy: -6.0).contains(point)
    }
}
