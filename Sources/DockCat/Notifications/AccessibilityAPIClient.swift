import ApplicationServices
import Foundation

enum AccessibilityClientError: Error, Equatable {
    case invalidElement, invalidObserver, unsupported, cannotComplete, notTrusted, unknown(Int32)
}

enum AccessibilityAttribute: String, CaseIterable {
    case role = "AXRole", subrole = "AXSubrole", identifier = "AXIdentifier", title = "AXTitle"
    case value = "AXValue", elementDescription = "AXDescription", help = "AXHelp"
    case enabled = "AXEnabled", selected = "AXSelected", children = "AXChildren", parent = "AXParent"
}

@MainActor protocol AccessibilityElementReference: AnyObject { var traversalIdentifier: Int { get } }
@MainActor protocol AccessibilityObserverReference: AnyObject {}

@MainActor protocol AccessibilityAPIClientProtocol: AnyObject {
    func application(processIdentifier: pid_t) -> any AccessibilityElementReference
    func makeObserver(processIdentifier: pid_t, callback: @escaping (any AccessibilityElementReference, String) -> Void) throws -> any AccessibilityObserverReference
    func attach(_ observer: any AccessibilityObserverReference)
    func detach(_ observer: any AccessibilityObserverReference)
    func add(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) throws
    func remove(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference)
    func string(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> String?
    func boolean(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> Bool?
    func elements(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> [any AccessibilityElementReference]
    func element(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> (any AccessibilityElementReference)?
    func actions(of element: any AccessibilityElementReference) throws -> [String]
    func press(_ element: any AccessibilityElementReference) throws
}
extension AccessibilityAPIClientProtocol {
    func press(_ element: any AccessibilityElementReference) throws { throw AccessibilityClientError.unsupported }
}

@MainActor final class AccessibilityAPIClient: AccessibilityAPIClientProtocol {
    private final class Element: AccessibilityElementReference {
        let raw: AXUIElement; init(_ raw: AXUIElement) { self.raw = raw }
        var traversalIdentifier: Int { CFHash(raw) }
    }
    private final class Observer: AccessibilityObserverReference {
        let raw: AXObserver; let box: CallbackBox
        init(raw: AXObserver, box: CallbackBox) { self.raw = raw; self.box = box }
    }
    private final class CallbackBox {
        let callback: (any AccessibilityElementReference, String) -> Void
        init(_ callback: @escaping (any AccessibilityElementReference, String) -> Void) { self.callback = callback }
    }

    func application(processIdentifier: pid_t) -> any AccessibilityElementReference { Element(AXUIElementCreateApplication(processIdentifier)) }
    func makeObserver(processIdentifier: pid_t, callback: @escaping (any AccessibilityElementReference, String) -> Void) throws -> any AccessibilityObserverReference {
        let box = CallbackBox(callback)
        var raw: AXObserver?
        let error = AXObserverCreate(processIdentifier, { _, element, notification, context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { box.callback(Element(element), notification as String) }
        }, &raw)
        guard error == .success, let raw else { throw Self.error(error) }
        return Observer(raw: raw, box: box)
    }
    func attach(_ observer: any AccessibilityObserverReference) { CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(raw(observer)), .commonModes) }
    func detach(_ observer: any AccessibilityObserverReference) { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(raw(observer)), .commonModes) }
    func add(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) throws {
        let o = observer as! Observer
        let result = AXObserverAddNotification(o.raw, raw(element), notification as CFString, Unmanaged.passUnretained(o.box).toOpaque())
        guard result == .success else { throw Self.error(result) }
    }
    func remove(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) {
        AXObserverRemoveNotification(raw(observer), raw(element), notification as CFString)
    }
    func string(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> String? { try value(attribute, element) as? String }
    func boolean(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> Bool? { try value(attribute, element) as? Bool }
    func elements(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> [any AccessibilityElementReference] {
        ((try value(attribute, element) as? [AXUIElement]) ?? []).map(Element.init)
    }
    func element(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> (any AccessibilityElementReference)? {
        guard let raw = try value(attribute, element) as? AXUIElement else { return nil }; return Element(raw)
    }
    func actions(of element: any AccessibilityElementReference) throws -> [String] {
        var names: CFArray?; let result = AXUIElementCopyActionNames(raw(element), &names)
        guard result == .success else { throw Self.error(result) }; return (names as? [String]) ?? []
    }
    func press(_ element: any AccessibilityElementReference) throws {
        let result = AXUIElementPerformAction(raw(element), kAXPressAction as CFString)
        guard result == .success else { throw Self.error(result) }
    }
    private func value(_ attribute: AccessibilityAttribute, _ element: any AccessibilityElementReference) throws -> AnyObject? {
        var result: CFTypeRef?; let error = AXUIElementCopyAttributeValue(raw(element), attribute.rawValue as CFString, &result)
        if error == .noValue || error == .attributeUnsupported { return nil }
        guard error == .success else { throw Self.error(error) }; return result
    }
    private func raw(_ element: any AccessibilityElementReference) -> AXUIElement { (element as! Element).raw }
    private func raw(_ observer: any AccessibilityObserverReference) -> AXObserver { (observer as! Observer).raw }
    private static func error(_ error: AXError) -> AccessibilityClientError {
        switch error { case .invalidUIElement: .invalidElement; case .invalidUIElementObserver: .invalidObserver
        case .notificationUnsupported, .attributeUnsupported, .actionUnsupported: .unsupported
        case .cannotComplete: .cannotComplete; case .apiDisabled: .notTrusted; default: .unknown(error.rawValue) }
    }
}
