import Foundation

public enum CatAnimation: Sendable, Equatable {
    case sleep, wake, pickUp
    case turnToPresentation(CatAnimationContext)
    case walkToPresentation
    case walkToPresentationLoop(CatAnimationContext)
    case stopAtPresentation(CatAnimationContext)
    case wait
    case turnHome(CatAnimationContext)
    case walkHome
    case walkHomeLoop(CatAnimationContext)
    case settle
}

public enum CatAnimationClipResolver {
    public static func clipID(for animation: CatAnimation, context: CatAnimationContext? = nil) -> CatAnimationClipID? {
        switch animation {
        case .sleep: .sleep
        case .wake: .wake
        case .pickUp: .pickUp
        case .turnToPresentation: .turnToPresentation
        case .walkToPresentation: nil
        case .walkToPresentationLoop: .walkCarry
        case .stopAtPresentation: .present
        case .wait: .wait
        case .turnHome: .turnHome
        case .walkHome: nil
        case .walkHomeLoop: .walkHome
        case .settle: .settle
        }
    }
}
