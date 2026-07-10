import SpriteKit

@MainActor
final class CatScene: SKScene {
    private let cat = SKNode()
    private let body = SKShapeNode(ellipseOf: CGSize(width: 82, height: 48))
    private let head = SKShapeNode(ellipseOf: CGSize(width: 47, height: 41))
    private let card = SKShapeNode(rectOf: CGSize(width: 30, height: 20), cornerRadius: 3)
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

        head.fillColor = orange
        head.strokeColor = darkOrange
        head.lineWidth = 2.5
        head.position = CGPoint(x: 31, y: 14)
        head.zPosition = 5
        addEarsAndFace()
        addStripes()

        card.fillColor = .white
        card.strokeColor = .systemGray
        card.position = CGPoint(x: 42, y: 38)
        card.zPosition = 10
        card.isHidden = true

        cat.position = CGPoint(x: size.width / 2 - 3, y: 34)
        cat.addChild(body)
        cat.addChild(head)
        cat.addChild(card)
        addChild(cat)
        playLoop()
    }

    required init?(coder: NSCoder) { nil }

    func run(_ animation: CatAnimation, duration: TimeInterval, reducedMotion: Bool, completion: @escaping @MainActor () -> Void) {
        cat.removeAllActions()
        let d = reducedMotion ? min(0.2, duration) : duration
        switch animation {
        case .sleep:
            playLoop(); completion()
        case .wake:
            cat.run(.sequence([.rotate(toAngle: 0.08, duration: d / 2), .rotate(toAngle: 0, duration: d / 2), .run { completion() }]))
        case .pickUp:
            card.isHidden = false
            card.alpha = 0
            card.run(.sequence([.fadeIn(withDuration: d), .run { completion() }]))
        case .walkToPresentation, .walkHome:
            let bob = SKAction.sequence([.moveBy(x: 0, y: 5, duration: d / 4), .moveBy(x: 0, y: -5, duration: d / 4)])
            cat.run(.sequence([.repeat(bob, count: 2), .run { completion() }]))
        case .wait:
            playLoop(); completion()
        case .settle:
            card.isHidden = true
            cat.run(.sequence([.scaleY(to: 0.82, duration: d), .run { [weak self] in self?.playLoop(); completion() }]))
        }
    }

    func playLoop() {
        cat.removeAllActions()
        cat.setScale(1)
        cat.run(.repeatForever(.sequence([.scaleY(to: 0.96, duration: 1.2), .scaleY(to: 1, duration: 1.2)])), withKey: "breathing")
    }

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
        cat.addChild(tail)
    }

    private func addHindPaw() {
        let paw = SKShapeNode(ellipseOf: CGSize(width: 27, height: 17))
        paw.fillColor = SKColor(red: 1, green: 0.72, blue: 0.46, alpha: 1)
        paw.strokeColor = darkOrange
        paw.lineWidth = 2
        paw.position = CGPoint(x: 13, y: -16)
        paw.zPosition = 4
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
