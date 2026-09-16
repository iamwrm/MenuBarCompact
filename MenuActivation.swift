import AppKit
import ApplicationServices

// Per-scan memoization avoids duplicate host controls and redundant AX requests.
// The generic traversal also permits deterministic tests without touching macOS.
struct StatusTraversal<Node: Hashable> {
    var budget = 100
    var visited: [Node: Bool] = [:]
    var result: [Node] = []
    let prepare: (Node) -> Void
    let role: (Node) -> String?
    let children: (Node) -> [Node]
    let pressable: (Node) -> Bool
    @discardableResult mutating func visit(_ node: Node, depth: Int = 0) -> Bool {
        if let known = visited[node] { return known }
        guard budget > 0, depth <= 5 else { return false }
        budget -= 1
        visited[node] = false
        prepare(node)
        if role(node) == kAXMenuRole { return false }
        var childControl = false
        for child in children(node) { if visit(child, depth: depth + 1) { childControl = true } }
        if childControl { visited[node] = true; return true }
        let control = pressable(node)
        if control { result.append(node); visited[node] = true }
        return control
    }
}
// CF equality, not pointer identity, is essential for overlapping AX roots.
struct AXNode: Hashable {
    let element: AXUIElement
    static func == (lhs: AXNode, rhs: AXNode) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}
struct MenuMetadata {
    var preferHost = false
    var identifiers: [String] = []
    var name = ""
    init(item: SystemItem? = nil, preferHost: Bool = false) {
        self.preferHost = preferHost
        identifiers = item?.axIdentifiers ?? []
        name = item?.axName ?? ""
    }
}
enum MenuActivation {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    static func elements(_ value: CFTypeRef?) -> [AXUIElement] {
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }
    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func actions(_ element: AXUIElement) -> [String] {
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        return actions as? [String] ?? []
    }
    static func statusButtons(pid: pid_t, host: Bool) -> [AXUIElement] {
        guard pid > 0 else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var traversal = StatusTraversal<AXNode>(prepare: { AXUIElementSetMessagingTimeout($0.element, 0.2) }, role: { value($0.element, kAXRoleAttribute) as? String }, children: { elements(value($0.element, kAXChildrenAttribute)).map { AXNode(element: $0) } }, pressable: {
            let names = actions($0.element)
            return names.contains(kAXPressAction) || names.contains(kAXShowMenuAction)
        })
        if let extras = element(value(app, kAXExtrasMenuBarAttribute)) { traversal.visit(AXNode(element: extras)) }
        if host {
            traversal.visit(AXNode(element: app))
            for window in elements(value(app, kAXWindowsAttribute)) { traversal.visit(AXNode(element: window)) }
        }
        return traversal.result.map(\.element)
    }
    static func hostButtons() -> [AXUIElement] {
        statusButtons(pid: NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?.processIdentifier ?? 0, host: true)
    }
    static func identity(_ element: AXUIElement) -> String {
        ["AXIdentifier", "AXTitle", "AXDescription"].compactMap { value(element, $0) as? String }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func targets(pid: pid_t, before: [AXUIElement], metadata: MenuMetadata) -> [AXUIElement] {
        let owned = statusButtons(pid: pid, host: false)
        if !owned.isEmpty, !metadata.preferHost { return owned }
        let host = hostButtons()
        if metadata.preferHost {
            let identities = Set(owned.map(identity).filter { !$0.isEmpty })
            let hosted = host.filter { identities.contains(identity($0)) }
            if !hosted.isEmpty { return hosted }
        }
        let matches = host.filter { element in
            if !metadata.identifiers.isEmpty, let ax = value(element, "AXIdentifier") as? String,
               metadata.identifiers.contains(where: { ax.caseInsensitiveCompare($0) == .orderedSame }) { return true }
            return !metadata.name.isEmpty && identity(element).range(of: metadata.name, options: .caseInsensitive) != nil
        }
        if !matches.isEmpty { return matches }
        let added = host.filter { element in !before.contains { CFEqual(element, $0) } }
        return added.count == 1 ? added : []
    }
    static func clickPoint(origin: CGPoint, size: CGSize, displays: [CGRect]) -> CGPoint? {
        guard origin.x.isFinite, origin.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.width <= 400, size.height > 0, size.height <= 64 else { return nil }
        let item = CGRect(origin: origin, size: size)
        for display in displays {
            let bar = CGRect(x: display.minX, y: display.minY, width: display.width, height: 64)
            if bar.contains(item) { return CGPoint(x: item.midX, y: item.midY) }
        }
        return nil
    }
    static func screenRect(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: 32), count: UInt32 = 0
        guard CGGetActiveDisplayList(32, &displays, &count) == .success else { return nil }
        let frames = displays.prefix(Int(count)).map(CGDisplayBounds)
        guard clickPoint(origin: origin, size: dimensions, displays: frames) != nil else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
    static func click(_ element: AXUIElement) -> AXError {
        guard let rect = screenRect(element) else { return .actionUnsupported }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        let previous = CGEvent(source: nil)?.location ?? point
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return .failure }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        CGWarpMouseCursorPosition(previous)
        return .success
    }
    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementSetMessagingTimeout(element, 1)
        let names = actions(element)
        let result: AXError
        if names.contains(kAXPressAction) { result = AXUIElementPerformAction(element, kAXPressAction as CFString) }
        else if names.contains(kAXShowMenuAction) { result = AXUIElementPerformAction(element, kAXShowMenuAction as CFString) }
        else { result = .actionUnsupported }
        // A timeout may mean the menu already opened. Never repeat that press.
        if result == .actionUnsupported || result == .notImplemented { return click(element) }
        return result
    }
}
