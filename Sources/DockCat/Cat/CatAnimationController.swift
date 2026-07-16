import DockCatCore
import Foundation

enum CatAnimation: Sendable {
    case sleep
    case wake
    case pickUp
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
