import DockCatCore
import SpriteKit

@MainActor
final class CatScene: SKScene {
    private let layoutRoot = SKNode()
    private let facingRoot = SKNode()
    private let poseRoot = SKNode()
    private let artworkRoot = SKNode()
    private let body = SKShapeNode(ellipseOf: CGSize(width: 82, height: 48))
    private let head = SKShapeNode(ellipseOf: CGSize(width: 47, height: 41))
    private let card = SKShapeNode(rectOf: CGSize(width: 30, height: 20), cornerRadius: 3)
    private let carryAnchor = SKNode()
    private var tail: SKShapeNode?
    private var hindPaw: SKShapeNode?
    private var frontPaw: SKShapeNode?
    private let orange = SKColor(red: 0.94, green: 0.49, blue: 0.16, alpha: 1)
    private let darkOrange = SKColor(red: 0.55, green: 0.23, blue: 0.08, alpha: 1)
    private struct PendingAnimation {
        let animation: CatAnimation
        let node: SKNode
        let actionKey: String
        let slot: String
        let continuation: CheckedContinuation<PresentationAnimationResult, Never>
    }
    private var pendingAnimations: [UUID: PendingAnimation] = [:]
    private var activeOperationBySlot: [String: UUID] = [:]
    private var visualPreferences: EffectiveAnimationPreferences = .default
    private var isSleepingPose = true
    private var currentFacing: CatFacing = .resting
    private let clipLibrary: CatAnimationClipLibrary?
    private var currentSpriteClipID: CatAnimationClipID?

    override init(size: CGSize) {
        let artworkLoadResult = CatAnimationAtlasLoader().load()
        if case .loaded(let library) = artworkLoadResult { self.clipLibrary = library } else { self.clipLibrary = nil }
        super.init(size: size)
        configureScene()
    }

    init(size: CGSize, artworkLoadResult: CatArtworkLoadResult) {
        if case .loaded(let library) = artworkLoadResult { self.clipLibrary = library } else { self.clipLibrary = nil }
        super.init(size: size)
        configureScene()
    }

    required init?(coder: NSCoder) { nil }


    private func configureScene() {
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

        layoutRoot.position = CGPoint(x: 75, y: 35)
        layoutRoot.addChild(facingRoot)
        facingRoot.addChild(poseRoot)
        poseRoot.addChild(artworkRoot)
        artworkRoot.addChild(body)
        artworkRoot.addChild(head)
        artworkRoot.addChild(carryAnchor)
        carryAnchor.addChild(card)
        addChild(layoutRoot)
        playLoop()
    }

    private enum ActionKey {
        static let breathing = "cat.breathing"
        static let walking = "cat.walking"
        static let tail = "cat.tail"
        static let turn = "cat.turn"
        static let cardPickup = "cat.cardPickup"
        static let settle = "cat.settle"
    }

    private func run(
        _ animation: CatAnimation,
        duration: TimeInterval,
        preferences: EffectiveAnimationPreferences,
        actionKey: String,
        completion: @escaping @MainActor () -> Void
    ) {
        if let clipID = CatAnimationClipResolver.clipID(for: animation), playSpriteClip(clipID, animation: animation, duration: duration, preferences: preferences, actionKey: actionKey, completion: completion) { return }
        if preferences.mode == .animationsPaused {
            applyFinalState(for: animation)
            completion()
            return
        }
        let reducedMotion = preferences.mode == .reducedMotion
        let d = max(0.05, reducedMotion ? min(0.2, duration) : duration)
        switch animation {
        case .sleep:
            hideMiniCard()
            playLoop()
            completion()
        case .wake:
            isSleepingPose = false
            stopBreathing()
            poseRoot.run(.sequence([.rotate(toAngle: 0.08, duration: d / 2), .rotate(toAngle: 0, duration: d / 2), .run { completion() }]), withKey: actionKey)
        case .pickUp:
            stopBreathing()
            showMiniCard()
            card.alpha = 0
            card.run(.sequence([.fadeIn(withDuration: d), .run { completion() }]), withKey: actionKey)
        case .turnToPresentation(let context), .turnHome(let context):
            stopBreathing()
            let transform = facingTransform(for: context.facing)
            facingRoot.xScale = transform.xScale
            if reducedMotion {
                facingRoot.zRotation = transform.rotation
                facingRoot.run(.sequence([.wait(forDuration: d), .run { completion() }]), withKey: actionKey)
            } else {
                facingRoot.run(.sequence([.rotate(toAngle: transform.rotation, duration: d, shortestUnitArc: true), .run { completion() }]), withKey: actionKey)
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
            poseRoot.run(.sequence([.wait(forDuration: d), .run { completion() }]), withKey: actionKey)
        case .wait:
            stopWalkLoop()
            showMiniCard()
            setStoppedPose(carrying: true)
            completion()
        case .settle:
            stopWalkLoop()
            hideMiniCard()
            poseRoot.run(.sequence([.scaleY(to: 0.82, duration: d), .run { [weak self] in self?.playLoop(); completion() }]), withKey: actionKey)
        }
    }

    func runAsync(
        _ animation: CatAnimation,
        duration: TimeInterval,
        preferences: EffectiveAnimationPreferences
    ) async -> PresentationAnimationResult {
        let operationID = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return .cancelled }
            return await withCheckedContinuation { continuation in
                let slot = animationSlot(animation)
                if let previous = activeOperationBySlot[slot] { cancelAnimation(previous) }
                let node = actionNode(animation)
                let actionKey = "cat.awaited.\(operationID.uuidString)"
                pendingAnimations[operationID] = PendingAnimation(
                    animation: animation, node: node, actionKey: actionKey,
                    slot: slot, continuation: continuation
                )
                activeOperationBySlot[slot] = operationID
                run(
                    animation, duration: duration, preferences: preferences,
                    actionKey: actionKey
                ) { [weak self] in
                    self?.finishAnimation(operationID, result: .completed)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelAnimation(operationID) }
        }
    }

    /// Cancels every visual operation and resolves its waiter. Resolving waiters is required
    /// so recovery cannot strand a flow task in a continuation.
    func cancelAnimations() {
        facingRoot.removeAllActions()
        poseRoot.removeAllActions()
        card.removeAllActions()
        tail?.removeAllActions()
        frontPaw?.removeAllActions()
        hindPaw?.removeAllActions()
        let operationIDs = Array(pendingAnimations.keys)
        operationIDs.forEach(cancelAnimation)
    }

    func resetToSleeping() {
        cancelAnimations()
        hideMiniCard()
        stopWalkLoop()
        body.yScale = 1
        head.position = CGPoint(x: 31, y: 14)
        poseRoot.position = .zero
        poseRoot.setScale(1)
        poseRoot.zRotation = 0
        facingRoot.setScale(1)
        facingRoot.zRotation = 0
        currentFacing = .resting
        playLoop()
    }

    func updateLayout(
        size: CGSize,
        visualAnchor: CGPoint,
        preferences: EffectiveAnimationPreferences
    ) {
        self.size = size
        layoutRoot.position = visualAnchor
        applyVisualPreferences(preferences, completeActiveAnimations: false)
    }

    func applyVisualPreferences(
        _ preferences: EffectiveAnimationPreferences,
        completeActiveAnimations: Bool
    ) {
        visualPreferences = preferences
        layoutRoot.setScale(preferences.catScale)
        if completeActiveAnimations {
            completeAnimationsImmediately()
        }
        if isSleepingPose {
            preferences.idleAnimationEnabled ? playLoop() : stopBreathing()
        }
    }

    private func completeAnimationsImmediately() {
        let operations = pendingAnimations.map { ($0.key, $0.value) }
        for (id, pending) in operations {
            pending.node.removeAction(forKey: pending.actionKey)
            applyFinalState(for: pending.animation)
            finishAnimation(id, result: .completed)
        }
    }

    private func applyFinalState(for animation: CatAnimation) {
        switch animation {
        case .sleep:
            hideMiniCard()
            playLoop()
        case .wake:
            isSleepingPose = false
            stopBreathing()
            poseRoot.zRotation = 0
        case .pickUp:
            isSleepingPose = false
            stopBreathing()
            showMiniCard()
        case .turnToPresentation(let context), .turnHome(let context):
            isSleepingPose = false
            stopBreathing()
            applyFacing(context.facing, animated: false, duration: 0)
        case .walkToPresentationLoop(let context), .walkHomeLoop(let context):
            isSleepingPose = false
            stopBreathing()
            applyFacing(context.facing, animated: false, duration: 0)
            setStaticCarryPose()
        case .walkToPresentation, .walkHome:
            break
        case .stopAtPresentation(let context):
            stopWalkLoop()
            applyFacing(context.facing, animated: false, duration: 0)
            setStoppedPose(carrying: context.isCarryingMiniCard)
        case .wait:
            stopWalkLoop()
            setStoppedPose(carrying: true)
        case .settle:
            stopWalkLoop()
            hideMiniCard()
            playLoop()
        }
    }


    private func playSpriteClip(
        _ clipID: CatAnimationClipID,
        animation: CatAnimation,
        duration: TimeInterval,
        preferences: EffectiveAnimationPreferences,
        actionKey: String,
        completion: @escaping @MainActor () -> Void
    ) -> Bool {
        guard let clipLibrary else { return false }
        if case .walkToPresentationLoop(let context) = animation {
            if preferences.mode == .walkingDisabled || context.phase == .staticCarry {
                applyFinalState(for: animation); completion(); return true
            }
        }
        let clip = clipLibrary[clipID]
        currentSpriteClipID = clipID
        applyFinalState(for: animation)
        if preferences.mode == .animationsPaused || preferences.mode == .reducedMotion || clip.textures.count <= 1 || clip.playback == .loop {
            completion(); return true
        }
        poseRoot.run(.sequence([.wait(forDuration: max(0.05, min(duration, Double(clip.textures.count) * clip.secondsPerFrame))), .run { completion() }]), withKey: actionKey)
        return true
    }

    private func finishAnimation(
        _ operationID: UUID,
        result: PresentationAnimationResult
    ) {
        guard let pending = pendingAnimations.removeValue(forKey: operationID) else { return }
        if activeOperationBySlot[pending.slot] == operationID {
            activeOperationBySlot.removeValue(forKey: pending.slot)
        }
        pending.continuation.resume(returning: result)
    }

    private func cancelAnimation(_ operationID: UUID) {
        guard let pending = pendingAnimations[operationID] else { return }
        pending.node.removeAction(forKey: pending.actionKey)
        finishAnimation(operationID, result: .cancelled)
    }

    private func animationSlot(_ animation: CatAnimation) -> String {
        switch animation {
        case .pickUp: "pickup"
        case .settle: "settle"
        case .walkToPresentationLoop, .walkHomeLoop: "locomotion-loop"
        default: "body"
        }
    }

    private func actionNode(_ animation: CatAnimation) -> SKNode {
        if case .pickUp = animation { return card }
        switch animation {
        case .turnToPresentation(_), .turnHome(_): return facingRoot
        default: return poseRoot
        }
    }

    func stopLocomotion(cancelled: Bool, context: CatAnimationContext?) {
        stopWalkLoop()
        if cancelled {
            setStoppedPose(carrying: context?.isCarryingMiniCard ?? !card.isHidden)
        }
    }

    func playLoop() {
        isSleepingPose = true
        stopWalkLoop()
        facingRoot.removeAction(forKey: ActionKey.turn)
        poseRoot.removeAction(forKey: ActionKey.settle)
        poseRoot.setScale(1)
        poseRoot.zRotation = 0
        facingRoot.setScale(1)
        facingRoot.zRotation = 0
        currentFacing = .resting
        guard visualPreferences.idleAnimationEnabled else { return }
        guard poseRoot.action(forKey: ActionKey.breathing) == nil else { return }
        poseRoot.run(.repeatForever(.sequence([.scaleY(to: 0.96, duration: 1.2), .scaleY(to: 1, duration: 1.2)])), withKey: ActionKey.breathing)
    }

    private func stopBreathing() {
        poseRoot.removeAction(forKey: ActionKey.breathing)
        poseRoot.xScale = 1
        poseRoot.yScale = 1
    }
    func showCarriedMiniCard() { showMiniCard() }
    func hideCarriedMiniCard() { hideMiniCard() }
    func prepareHandoffPose() { stopWalkLoop(); setStoppedPose(carrying: true) }
    func completeHandoffPose() { setStoppedPose(carrying: false) }

    private func showMiniCard() { card.isHidden = false; card.alpha = 1 }
    private func hideMiniCard() { card.removeAction(forKey: ActionKey.cardPickup); card.isHidden = true; card.alpha = 0 }

    private func applyFacing(_ facing: CatFacing, animated: Bool, duration: TimeInterval) {
        currentFacing = facing
        let transform = facingTransform(for: facing)
        facingRoot.xScale = transform.xScale
        if animated { facingRoot.run(.rotate(toAngle: transform.rotation, duration: duration, shortestUnitArc: true), withKey: ActionKey.turn) }
        else { facingRoot.zRotation = transform.rotation }
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
        guard poseRoot.action(forKey: ActionKey.walking) == nil else { return }
        let bob = SKAction.sequence([.moveBy(x: 0, y: 4, duration: 0.12), .moveBy(x: 0, y: -4, duration: 0.12)])
        let paws = SKAction.run { [weak self] in
            self?.frontPaw?.run(.sequence([.moveBy(x: 5, y: 0, duration: 0.12), .moveBy(x: -5, y: 0, duration: 0.12)]))
            self?.hindPaw?.run(.sequence([.moveBy(x: -5, y: 0, duration: 0.12), .moveBy(x: 5, y: 0, duration: 0.12)]))
        }
        let tailWag = SKAction.run { [weak self] in self?.tail?.run(.sequence([.rotate(toAngle: 0.12, duration: 0.12), .rotate(toAngle: -0.08, duration: 0.12)]), withKey: ActionKey.tail) }
        poseRoot.run(.repeatForever(.sequence([paws, tailWag, bob])), withKey: ActionKey.walking)
    }

    private func stopWalkLoop() {
        poseRoot.removeAction(forKey: ActionKey.walking)
        tail?.removeAction(forKey: ActionKey.tail)
        frontPaw?.removeAllActions(); hindPaw?.removeAllActions()
        poseRoot.position = .zero
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
        artworkRoot.addChild(tail)
    }

    private func addHindPaw() {
        let paw = SKShapeNode(ellipseOf: CGSize(width: 27, height: 17))
        paw.fillColor = SKColor(red: 1, green: 0.72, blue: 0.46, alpha: 1)
        paw.strokeColor = darkOrange
        paw.lineWidth = 2
        paw.position = CGPoint(x: 13, y: -16)
        paw.zPosition = 4
        self.hindPaw = paw
        artworkRoot.addChild(paw)
    }

    private func addFrontPaw() {
        let paw = SKShapeNode(ellipseOf: CGSize(width: 24, height: 15))
        paw.fillColor = SKColor(red: 1, green: 0.72, blue: 0.46, alpha: 1)
        paw.strokeColor = darkOrange
        paw.lineWidth = 2
        paw.position = CGPoint(x: 28, y: -15)
        paw.zPosition = 4
        self.frontPaw = paw
        artworkRoot.addChild(paw)
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
            artworkRoot.addChild(ear)
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
            artworkRoot.addChild(eye)
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
        artworkRoot.addChild(nose)

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
                artworkRoot.addChild(whisker)
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
            artworkRoot.addChild(stripe)
        }
    }

    var userScaleForTesting: CGFloat { layoutRoot.xScale }
    var facingScaleForTesting: CGFloat { facingRoot.xScale }
    var facingRotationForTesting: CGFloat { facingRoot.zRotation }
    var facingForGeometry: CatFacing { currentFacing }
    var isBreathingForTesting: Bool {
        poseRoot.action(forKey: ActionKey.breathing) != nil
    }
    var isWalkingForTesting: Bool {
        poseRoot.action(forKey: ActionKey.walking) != nil
    }
    var currentSpriteClipIDForTesting: CatAnimationClipID? { currentSpriteClipID }
    var usesSpriteAtlasForTesting: Bool { clipLibrary != nil }
}
