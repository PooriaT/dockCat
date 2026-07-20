import AppKit
import DockCatCore

@MainActor
protocol ApplicationFocusControlling: AnyObject {
    var dockCatProcessIdentifier: Int32 { get }
    var frontmostApplication: CardApplicationIdentity? { get }
    var isDockCatFrontmost: Bool { get }
    @discardableResult func activateDockCat() -> Bool
    func isApplicationRunning(_ identity: CardApplicationIdentity) -> Bool
    @discardableResult func activateApplication(_ identity: CardApplicationIdentity) -> Bool
}

@MainActor
final class ApplicationFocusController: ApplicationFocusControlling {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var dockCatProcessIdentifier: Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    var frontmostApplication: CardApplicationIdentity? {
        workspace.frontmostApplication.map {
            CardApplicationIdentity(processIdentifier: $0.processIdentifier)
        }
    }

    var isDockCatFrontmost: Bool {
        frontmostApplication?.processIdentifier == dockCatProcessIdentifier
    }

    @discardableResult
    func activateDockCat() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return NSApp.isActive
    }

    func isApplicationRunning(_ identity: CardApplicationIdentity) -> Bool {
        guard let application = NSRunningApplication(
            processIdentifier: identity.processIdentifier
        ) else { return false }
        return !application.isTerminated
    }

    @discardableResult
    func activateApplication(_ identity: CardApplicationIdentity) -> Bool {
        guard let application = NSRunningApplication(
            processIdentifier: identity.processIdentifier
        ), !application.isTerminated else { return false }
        return application.activate(options: [.activateAllWindows])
    }
}

@MainActor
protocol CardURLOpening: AnyObject {
    @discardableResult func open(_ url: URL) -> Bool
}

@MainActor
final class WorkspaceCardURLOpener: CardURLOpening {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    @discardableResult
    func open(_ url: URL) -> Bool {
        workspace.open(url)
    }
}
