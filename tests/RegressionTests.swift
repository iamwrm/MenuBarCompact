import AppKit
import CryptoKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func fixtureCatalog() -> [String: SystemItem] {
    let tokens = ["battery", "bluetooth", "clock", "displays", "keyboard", "volume", "wifi", "screenMirroring", "primaryBentoBox", "futureWidget"]
    return SystemCatalog.build(runtime: tokens.enumerated().map { ["token": $0.element, "raw": $0.offset == 9 ? 42 : $0.offset] }, plugins: [["bundle": "com.apple.menuextra.TimeMachine", "name": "Time Machine", "path": "/fixture/TimeMachine.menu", "host": "com.apple.systemuiserver"], ["bundle": "com.apple.menuextra.NewExtra", "name": "New Extra"]], specials: ["system.spotlight": SystemItem(name: "Spotlight", bundles: ["com.apple.Spotlight", "com.apple.campo"])])
}
func jsonPlan(_ plan: VisibilityPlan) -> [String: Any] { ["bundles": plan.bundles, "systems": plan.systems, "excluded": plan.excluded] }
func testParity() throws {
    SystemCatalog.items = fixtureCatalog()
    let running = [ownID, "example.hidden", "example.other", iStatID, "com.apple.MenuBarAgent", "com.apple.campo", "com.apple.TextInputMenuAgent"]
    let ids = ["example.hidden", "example.other", "example.closed", iStatID, "com.apple.MenuBarAgent", ownID, "system.battery", "system.input-method", "system.spotlight", "system.clock", "system.primaryBentoBox", "system.futureWidget", "system.retiredWidget", "system.extra.com.apple.menuextra.TimeMachine"]
    var state: UInt64 = 0x4D4243, digest = SHA256()
    for index in 0..<512 {
        var rules: [String: Int] = [:]
        for identifier in ids {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = Int((state >> 32) % 6)
            if value != 0 { rules[identifier] = value - 2 }
        }
        for mode in [VisibilityMode.collapsed, .revealed, .everything] {
            let output: [Any] = [jsonPlan(VisibilityPolicy.plan(running: running, rules: rules, ownID: ownID, mode: mode)), VisibilityPolicy.panelItems(running: running, rules: rules, ownID: ownID, includeAlwaysHidden: false).sorted(), VisibilityPolicy.panelItems(running: running, rules: rules, ownID: ownID, includeAlwaysHidden: true).sorted(), jsonPlan(VisibilityPolicy.plan(running: running, rules: VisibilityPolicy.interactionRules(rules, selected: ids[index % ids.count]), ownID: ownID, mode: mode))]
            digest.update(data: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys))
            digest.update(data: Data([10]))
        }
    }
    let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/visibility-parity.json"))) as! [String: Any]
    let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
    require(actual == oracle["sha256"] as? String, "Swift must exactly match 1,536 Objective-C policy/panel/interaction cases (\(actual))")
    let shared = SystemCatalog.build(runtime: [["token": "keyboard", "raw": 4]], plugins: [["bundle": "com.apple.menuextra.TimeMachine", "name": "Time Machine"]], specials: [:])
    SystemCatalog.items = shared
    require(VisibilityPolicy.plan(running: [], rules: ["system.extra.com.apple.menuextra.TimeMachine": 1], ownID: ownID, mode: .collapsed).bundles.contains("com.apple.systemuiserver"), "Never exclude a shared/unknown legacy host")
    require(SystemCatalog.items["system.input-method"]?.systems == [4], "Input Method preference alias stays stable")
    require(SystemCatalog.readableName("futureWidget") == "Future Widget" && SystemCatalog.readableName("PPP") == "PPP", "Readable discovered labels")
    SystemCatalog.items = fixtureCatalog()
    print("Parity passed: 1,536 cases against Objective-C v0.6.8.")
}
final class FakeAssertion: RestrictionAssertion {
    var invalidations = 0
    var completion: ((Error?) -> Void)?
    func activate(_ completion: @escaping (Error?) -> Void) { self.completion = completion }
    func invalidate() { invalidations += 1 }
    func complete(_ error: Error? = nil) { let callback = completion; completion = nil; callback?(error); drain() }
}
class TestController: MenuBarCompact {
    override func updateUI() {}
    override func log(_ message: String) {}
    override func saveRules() {} // Tests never write user preferences.
}
func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
func testTransitions() {
    let c = TestController(); c.ready = true; c.discoveryReady = true
    c.makeAssertion = { _, _ in FakeAssertion() }
    c.rules = ["test.one": 1, "test.two": 1]
    c.applyVisibility()
    let first = c.assertion as! FakeAssertion
    require(c.activationPending, "Initial assertion activates asynchronously")
    first.complete(); require(c.settledAssertion === first, "Retain acknowledged baseline")
    var ready = 0
    c.activeItem = "test.one"; c.visibilityReadyHandler = { ready = $0 ? 1 : -1 }; c.applyVisibility()
    let second = c.assertion as! FakeAssertion
    require(second !== first && first.invalidations == 0 && ready == 0, "Keep baseline and wait before menu activation")
    second.complete()
    require(first.invalidations == 1 && c.settledAssertion === second && ready == 1, "Retire only old assertion after acknowledgement")
    c.activeItem = nil; c.applyVisibility(); let superseded = c.assertion as! FakeAssertion
    c.activeItem = "test.two"; c.applyVisibility(); let latest = c.assertion as! FakeAssertion
    require(second.invalidations == 0 && superseded.invalidations == 1, "Supersession preserves working restriction")
    superseded.complete()
    require(c.assertion === latest && c.settledAssertion === second, "Ignore stale completion")
    latest.complete(); require(second.invalidations == 1 && c.settledAssertion === latest, "Only latest acknowledgement wins")
    c.activeItem = nil; ready = 0; c.visibilityReadyHandler = { ready = $0 ? 1 : -1 }; c.applyVisibility()
    let failed = c.assertion as! FakeAssertion
    failed.complete(NSError(domain: "test", code: 1))
    require(c.assertion == nil && c.settledAssertion == nil && latest.invalidations == 1 && failed.invalidations == 1 && ready == -1, "Errors release both assertions and fail menu request")
    c.applyVisibility(); let timedOut = c.assertion as! FakeAssertion
    ready = 0; c.visibilityReadyHandler = { ready = $0 ? 1 : -1 }; c.activationTimeout?.fire(); drain()
    require(c.assertion == nil && timedOut.invalidations == 1 && ready == -1, "Timeout fails open")
    timedOut.complete(); require(c.assertion == nil, "Late acknowledgement cannot restore expired restriction")
    c.applyVisibility(); let final = c.assertion as! FakeAssertion; final.complete()
    c.releaseRestriction(); require(final.invalidations == 1, "Settled release occurs once")
    c.paused = true; ready = 0; c.visibilityReadyHandler = { ready = $0 ? 1 : -1 }; c.applyVisibility(); drain()
    require(ready == -1, "Paused controller cannot open pending menu")
    c.paused = false; c.makeAssertion = { _, _ in throw NSError(domain: "bridge", code: 1) }
    ready = 0; c.visibilityReadyHandler = { ready = $0 ? 1 : -1 }; c.applyVisibility(); drain()
    require(ready == -1 && c.assertion == nil, "Missing API or bridge exception fails open")
    c.rules = [iStatID: 1]
    require(c.canMoveVisibilityItem(iStatID, to: 2), "iStat supports every visibility choice")
    require(!c.canMoveVisibilityItem("system.clock", to: 1), "Clock is protected from drops")
    require(!c.canMoveVisibilityItem("system.retiredWidget", to: 1), "Stale discovered item cannot receive a drop")
    print("Transitions passed: handoff, supersession, errors, timeout, cancellation, release, protected drops.")
}
func testMaintenance() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("helper")
    func snapshot(_ pid: pid_t = 1) -> CompatibilityFingerprint { CompatibilityFingerprint(files: FileFingerprint.read([path.path]), pid: pid) }
    let missing = snapshot()
    try Data("version1".utf8).write(to: path, options: .atomic)
    let initial = snapshot()
    require(initial != missing, "Installing helper changes fingerprint")
    for elapsed in stride(from: 60, to: 3600, by: 60) {
        require(!needsCompatibilityAudit(current: initial, verified: initial, ready: true, elapsed: Double(elapsed), sinceAttempt: Double(elapsed), force: false), "No idle subprocess audits")
    }
    require(needsCompatibilityAudit(current: initial, verified: initial, ready: true, elapsed: 3600, sinceAttempt: 3600, force: false), "Hourly full audit")
    require(needsCompatibilityAudit(current: initial, verified: initial, ready: true, elapsed: 1, sinceAttempt: 1, force: true), "Manual bypass")
    require(!needsCompatibilityAudit(current: initial, verified: missing, ready: false, elapsed: 120, sinceAttempt: 5, force: false), "Failure retry backoff")
    require(needsCompatibilityAudit(current: initial, verified: missing, ready: false, elapsed: 120, sinceAttempt: 60, force: false), "Retry after backoff")
    require(needsCompatibilityAudit(current: initial, verified: nil, ready: false, elapsed: 0, sinceAttempt: 60, force: false), "Initial audit")
    try Data("version2".utf8).write(to: path, options: .atomic)
    let replacement = snapshot()
    require(replacement != initial, "Same-size atomic replacement detected")
    require(needsCompatibilityAudit(current: replacement, verified: initial, ready: true, elapsed: 10, sinceAttempt: 10, force: false), "Changed file audits immediately")
    require(needsCompatibilityAudit(current: snapshot(2), verified: replacement, ready: true, elapsed: 10, sinceAttempt: 10, force: false), "Restarted helper audited")
    try FileManager.default.removeItem(at: path)
    require(snapshot() != replacement, "Removed helper detected")
    print("Maintenance passed: fingerprints, idle gating, retry backoff, hourly audit.")
}
func testGeometry() {
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -200, width: 1920, height: 1080)]
    func point(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPoint? { MenuActivation.clickPoint(origin: CGPoint(x: x, y: y), size: CGSize(width: w, height: h), displays: screens) }
    require(point(1200, 0, 24, 24) == CGPoint(x: 1212, y: 12), "Status control center")
    require(point(-500, -200, 30, 30) != nil, "Secondary display above/left")
    for (x, y, w, h): (CGFloat, CGFloat, CGFloat, CGFloat) in [(1200,70,24,24),(1430,0,24,24),(1200,50,24,24),(0,0,0,24),(0,0,500,24),(.nan,0,24,24),(0,0,24,.infinity)] {
        require(point(x,y,w,h) == nil, "Reject off-bar, malformed or off-screen click")
    }
    require(MenuActivation.clickPoint(origin: .zero, size: CGSize(width: 24, height: 24), displays: []) == nil, "No displays means no click")
    require(visibilityColumns(748) == 13, "Thirteen default columns")
    require(visibilityHeight(13, 748) == 92 && visibilityHeight(14, 748) == 160 && visibilityHeight(27, 748) == 228, "Wrap boundaries")
    require(visibilityHeight(0, 748) == 92, "Empty drop target height")
    for width: CGFloat in [588, 748, 1000] {
        for count in 1...100 {
            let bounds = NSRect(x: 0, y: 0, width: width, height: visibilityHeight(count, width))
            for i in 0..<count {
                let frame = visibilityIconFrame(i, count, width)
                require(bounds.contains(frame), "Every icon in bounds")
                for j in 0..<i { require(!frame.intersects(visibilityIconFrame(j, count, width)), "No overlapping drop targets") }
            }
        }
    }
    let a = visibilityIconFrame(0,17,748), b = visibilityIconFrame(13,17,748)
    require(a.minX == b.minX && b.minY < a.minY, "Wrap downwards")
    print("Geometry passed: multi-display click bounds, wrapping, resizing, 100-item sections.")
}
func testTraversal() {
    // leaf=0, parent=1, menu child=2, menu=3, legacy=4, root=5
    let roles = ["AXButton", "AXGroup", "AXMenuItem", "AXMenu", "AXMenuItem", "AXApplication"]
    let children = [[], [0], [], [2], [], [1,3,4]]
    var attributeReads = [Int](repeating: 0, count: 6), actionReads = attributeReads
    var t = StatusTraversal<Int>(prepare: { _ in }, role: { attributeReads[$0] += 1; return roles[$0] }, children: { attributeReads[$0] += 1; return children[$0] }, pressable: { actionReads[$0] += 1; return [0,1,2,4].contains($0) })
    t.visit(0); let reads = attributeReads[0]; t.visit(5); t.visit(1)
    require(t.result == [0,4], "Overlapping roots produce unique leaves")
    require(attributeReads[0] == reads && actionReads[0] == 1, "Shared leaf queried once")
    require(actionReads[1] == 0 && actionReads[5] == 0, "Containers need no action query")
    require(attributeReads[2] == 0 && t.budget == 95, "Do not enter open menus; unique-node budget")
    t.visited.removeAll(); t.result.removeAll(); t.budget = 0; t.visit(0)
    require(t.result.isEmpty && attributeReads[0] == reads, "Exhaustion makes no requests")
    print("AX traversal passed: unique leaves, open-menu isolation, request budget.")
}
@main struct RegressionTests {
    static func main() throws {
        try testParity(); testTransitions(); try testMaintenance(); testGeometry(); testTraversal()
        let entries = RuntimeSystemItems.items()
        let tokens = entries.compactMap { $0["token"] as? String }, raw = entries.compactMap { $0["raw"] as? Int }
        require(!entries.isEmpty && Set(tokens).count == entries.count && Set(raw).count == entries.count, "Runtime enumeration has unique tokens and raw IDs")
        require(tokens.contains("battery") && tokens.contains("keyboard"), "Runtime categories available")
        print("Runtime discovery passed: \(entries.count) categories.")
    }
}
