import DockCatCore
import SpriteKit

@MainActor
final class CatScene: SKScene {
    private let cat = SKNode()
    private let body = SKShapeNode(ellipseOf: CGSize(width: 82, height: 48))
    private let head = SKShapeNode(ellipseOf: CGSize(width: 47, height: 41))
    private let card = SKShapeNode(rectOf: CGSize(width: 30, height: 20), cornerRadius: 3)
    private let carryAnchor = SKNode()
    private var tail: SKShapeNode?
    private var hindPaw: SKShapeNode?
    private var frontPaw: SKShapeNode?
    private let orange = SKColor(red: 0.94, green: 0.49, blue: 0.16, alpha: 1)
    private let darkOrange = SKColor(red: 0.55, green: 0.23, blue: 0.08, alpha: 1)

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill

        body.fillColor = orange
        body.strokeColor = darkOrange
        body.lineWidth = 2.5
        body.position = CGPoint(x: -5, y: 0)
        body.zPosition = 2

        addTail()
        addHindPaw()
        addFrontPaw()

        head.fillColor = orange
        head.strokeColor = darkOrange
        head.lineWidth = 2.5
        head.position = CGPoint(x: 31, y: 14)
        head.zPosition = 5
        addEarsAndFace()
        addStripes()

        card.fillColor = .white
        card.strokeColor = .systemGray
        carryAnchor.position = CGPoint(x: 42, y: 38)
        carryAnchor.zPosition = 10
        card.position = .zero
        card.zPosition = 1
        card.isHidden = true

        cat.position = CGPoint(x: size.width / 2 - 3, y: 34)
        cat.addChild(body)
        cat.addChild(head)
        cat.addChild(carryAnchor)
        carryAnchor.addChild(card)
        addChild(cat)
        playLoop()
    }

    required init?(coder: NSCoder) { nil }

    private enum ActionKey {
        static let breathing = "cat.breathing"
        static let walking = "cat.walking"
        static let tail = "cat.tail"
        static let turn = "cat.turn"
        static let cardPickup = "cat.cardPickup"
        static let settle = "cat.settle"
    }

    func run(_ animation: CatAnimation, duration: TimeInterval, reducedMotion: Bool, completion: @escaping @MainActor () -> Void) {
        let d = max(0.05, reducedMotion ? min(0.2, duration) : duration)
        switch animation {
        case .sleep:
            hideMiniCard()
            playLoop()
            completion()
        case .wake:
            stopBreathing()
            cat.run(.sequence([.rotate(toAngle: 0.08, duration: d / 2), .rotate(toAngle: 0, duration: d / 2), .run { completion() }]), withKey: ActionKey.turn)
        case .pickUp:
            stopBreathing()
            showMiniCard()
            card.alpha = 0
            card.run(.sequence([.fadeIn(withDuration: d), .run { completion() }]), withKey: ActionKey.cardPickup)
        case .turnToPresentation(let context), .turnHome(let context):
            stopBreathing()
            let transform = facingTransform(for: context.facing)
            cat.xScale = transform.xScale
            if reducedMotion {
                cat.zRotation = transform.rotation
                cat.run(.sequence([.wait(forDuration: d), .run { completion() }]), withKey: ActionKey.turn)
            } else {
                cat.run(.sequence([.rotate(toAngle: transform.rotation, duration: d, shortestUnitArc: true), .run { completion() }]), withKey: ActionKey.turn)
            }
        case .walkToPresentationLoop(let context), .walkHomeLoop(let context):
            stopBreathing()
            applyFacing(context.facing, animated: false, duration: 0)
            if context.isCarryingMiniCard { showMiniCard() }
            if context.phase == .staticCarry || reducedMotion {
                setStaticCarryPose()
                completion()
            } else {
                startWalkLoop(context: context)
                completion()
            }
        case .walkToPresentation, .walkHome:
            completion()
        case .stopAtPresentation(let context):
            stopWalkLoop()
            applyFacing(context.facing, animated: false, duration: 0)
            setStoppedPose(carrying: context.isCarryingMiniCard)
            cat.run(.sequence([.wait(forDuration: d), .run { completion() }]))
        case .wait:
            stopWalkLoop()
            showMiniCard()
            setStoppedPose(carrying: true)
            completion()
        case .settle:
            stopWalkLoop()
            hideMiniCard()
            cat.run(.sequence([.scaleY(to: 0.82, duration: d), .run { [weak self] in self?.playLoop(); completion() }]), withKey: ActionKey.settle)
        }
    }

    func runAsync(_ animation: CatAnimation, duration: TimeInterval, reducedMotion: Bool) async {
        await withCheckedContinuation { continuation in
            run(animation, duration: duration, reducedMotion: reducedMotion) {
                continuation.resume()
            }
        }
    }

    func stopLocomotion(cancelled: Bool, context: CatAnimationContext?) {
        stopWalkLoop()
        if cancelled {
            setStoppedPose(carrying: context?.isCarryingMiniCard ?? !card.isHidden)
        }
    }

    func playLoop() {
        stopWalkLoop()
        cat.removeAction(forKey: ActionKey.turn)
        cat.removeAction(forKey: ActionKey.settle)
        cat.setScale(1)
        cat.zRotation = 0
        cat.run(.repeatForever(.sequence([.scaleY(to: 0.96, duration: 1.2), .scaleY(to: 1, duration: 1.2)])), withKey: ActionKey.breathing)
    }

    private func stopBreathing() { cat.removeAction(forKey: ActionKey.breathing); cat.setScale(1) }
    private func showMiniCard() { card.isHidden = false; card.alpha = 1 }
    private func hideMiniCard() { card.removeAction(forKey: ActionKey.cardPickup); card.isHidden = true; card.alpha = 0 }

    private func applyFacing(_ facing: CatFacing, animated: Bool, duration: TimeInterval) {
        let transform = facingTransform(for: facing)
        cat.xScale = transform.xScale
        if animated { cat.run(.rotate(toAngle: transform.rotation, duration: duration, shortestUnitArc: true), withKey: ActionKey.turn) }
        else { cat.zRotation = transform.rotation }
    }

    private func facingTransform(for facing: CatFacing) -> (xScale: CGFloat, rotation: CGFloat) {
        switch facing {
        case .left: (-1, 0)
        case .right, .resting: (1, 0)
        case .up: (1, .pi / 2)
        case .down: (1, -.pi / 2)
        }
    }

    private func startWalkLoop(context: CatAnimationContext) {
        guard cat.action(forKey: ActionKey.walking) == nil else { return }
        let bob = SKAction.sequence([.moveBy(x: 0, y: 4, duration: 0.12), .moveBy(x: 0, y: -4, duration: 0.12)])
        let paws = SKAction.run { [weak self] in
            self?.frontPaw?.run(.sequence([.moveBy(x: 5, y: 0, duration: 0.12), .moveBy(x: -5, y: 0, duration: 0.12)]))
            self?.hindPaw?.run(.sequence([.moveBy(x: -5, y: 0, duration: 0.12), .moveBy(x: 5, y: 0, duration: 0.12)]))
        }
        let tailWag = SKAction.run { [weak self] in self?.tail?.run(.sequence([.rotate(toAngle: 0.12, duration: 0.12), .rotate(toAngle: -0.08, duration: 0.12)]), withKey: ActionKey.tail) }
        cat.run(.repeatForever(.sequence([paws, tailWag, bob])), withKey: ActionKey.walking)
    }

    private func stopWalkLoop() {
        cat.removeAction(forKey: ActionKey.walking)
        tail?.removeAction(forKey: ActionKey.tail)
        frontPaw?.removeAllActions(); hindPaw?.removeAllActions()
        cat.position = CGPoint(x: size.width / 2 - 3, y: 34)
        frontPaw?.position = CGPoint(x: 28, y: -15)
        hindPaw?.position = CGPoint(x: 13, y: -16)
        tail?.zRotation = 0
    }

    private func setStaticCarryPose() { showMiniCard(); body.yScale = 1; head.position = CGPoint(x: 31, y: 16) }
    private func setStoppedPose(carrying: Bool) { if carrying { showMiniCard() } else { hideMiniCard() }; body.yScale = 1; head.position = CGPoint(x: 31, y: 14) }

    private func addTail() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -39, y: 1))
        path.addCurve(to: CGPoint(x: 8, y: -15), control1: CGPoint(x: -62, y: -19), control2: CGPoint(x: -19, y: -29))
        path.addCurve(to: CGPoint(x: 25, y: -6), control1: CGPoint(x: 19, y: -11), control2: CGPoint(x: 25, y: -4))
        let tail = SKShapeNode(path: path)
        tail.strokeColor = darkOrange
        tail.lineWidth = 11
        tail.lineCap = .round
        tail.zPosition = 3
        self.tail = tail
        cat.addChild(tail)
    }

    private func addHindPaw() {
        let paw = SKShapeNode(ellipseOf: CGSize(width: 27, height: 17))
        paw.fillColor = SKColor(red: 1, green: 0.72, blue: 0.46, alpha: 1)
        paw.strokeColor = darkOrange
        paw.lineWidth = 2
        paw.position = CGPoint(x: 13, y: -16)
        paw.zPosition = 4
        self.hindPaw = paw
        cat.addChild(paw)
    }

    private func addFrontPaw() {
        let paw = SKShapeNode(ellipseOf: CGSize(width: 24, height: 15))
        paw.fillColor = SKColor(red: 1, green: 0.72, blue: 0.46, alpha: 1)
        paw.strokeColor = darkOrange
        paw.lineWidth = 2
        paw.position = CGPoint(x: 28, y: -15)
        paw.zPosition = 4
        self.frontPaw = paw
        cat.addChild(paw)
    }

    private func addEarsAndFace() {
        for x in [-14.0, 14.0] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 9, y: 13))
            path.addLine(to: CGPoint(x: x, y: 34))
            path.addLine(to: CGPoint(x: x + 10, y: 12))
            path.closeSubpath()
            let ear = SKShapeNode(path: path)
            ear.fillColor = orange
            ear.strokeColor = darkOrange
            ear.lineWidth = 2.5
            ear.position = head.position
            ear.zPosition = 4
            cat.addChild(ear)
        }

        for x in [-9.0, 9.0] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 5, y: 2))
            path.addQuadCurve(to: CGPoint(x: x + 5, y: 2), control: CGPoint(x: x, y: -2))
            let eye = SKShapeNode(path: path)
            eye.strokeColor = .black
            eye.lineWidth = 2
            eye.lineCap = .round
            eye.position = head.position
            eye.zPosition = 7
            cat.addChild(eye)
        }

        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: -3, y: -5))
        nosePath.addLine(to: CGPoint(x: 3, y: -5))
        nosePath.addLine(to: CGPoint(x: 0, y: -9))
        nosePath.closeSubpath()
        let nose = SKShapeNode(path: nosePath)
        nose.fillColor = .systemPink
        nose.strokeColor = darkOrange
        nose.position = head.position
        nose.zPosition = 7
        cat.addChild(nose)

        for direction in [-1.0, 1.0] {
            for y in [-5.0, 0.0] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: direction * 8, y: y - 7))
                path.addLine(to: CGPoint(x: direction * 27, y: y - 5))
                let whisker = SKShapeNode(path: path)
                whisker.strokeColor = darkOrange
                whisker.lineWidth = 1.2
                whisker.position = head.position
                whisker.zPosition = 7
                cat.addChild(whisker)
            }
        }
    }

    private func addStripes() {
        for x in [-24.0, -10.0, 4.0] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 18))
            path.addLine(to: CGPoint(x: x + 5, y: 10))
            let stripe = SKShapeNode(path: path)
            stripe.strokeColor = darkOrange
            stripe.lineWidth = 3
            stripe.lineCap = .round
            stripe.zPosition = 4
            cat.addChild(stripe)
        }
    }
}
