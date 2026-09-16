import AppKit

protocol RestrictionAssertion: AnyObject {
    func activate(_ completion: @escaping (Error?) -> Void)
    func invalidate()
}
final class NativeRestriction: RestrictionAssertion {
    let handle: MBRestrictionHandle
    init(systems: [Int], bundles: [String]) throws { handle = try MBRestrictionHandle(systems: systems.map(NSNumber.init), bundles: bundles) }
    func activate(_ completion: @escaping (Error?) -> Void) { handle.activate(completion) }
    func invalidate() { handle.invalidate() }
}

extension MenuBarCompact {
    func visibilityDidFinish(_ success: Bool) {
        let handler = visibilityReadyHandler
        visibilityReadyHandler = nil
        if let handler { DispatchQueue.main.async { handler(success) } }
    }
    func releaseRestriction() {
        generation &+= 1
        activationPending = false
        activationTimeout?.invalidate(); activationTimeout = nil
        let current = assertion
        assertion = nil
        if let current { current.invalidate(); log("RELEASE visibility restriction") }
        if settledAssertion !== current { settledAssertion?.invalidate() }
        settledAssertion = nil
        lastAllowlist = nil; lastSystemAllowlist = nil
    }
    func visibilityUnavailable(_ message: String) {
        releaseRestriction(); stateMessage = message; updateUI(); visibilityDidFinish(false)
    }
    func applyVisibility() {
        if paused { visibilityDidFinish(false); return }
        guard discoveryReady else { visibilityUnavailable("System item discovery unavailable; hiding is paused"); return }
        guard running[thawID] == nil else { visibilityUnavailable("Paused while Thaw is running"); return }
        guard ready else { visibilityUnavailable("Waiting for iStat compatibility"); return }
        let plan = VisibilityPolicy.plan(running: Array(running.keys), rules: VisibilityPolicy.interactionRules(rules, selected: activeItem), ownID: ownID, mode: .collapsed)
        if mode == .everything || plan.excluded == 0 {
            releaseRestriction()
            stateMessage = mode == .everything ? "Showing all items" : "All configured items are visible"
            updateUI(); visibilityDidFinish(true); return
        }
        if assertion != nil, plan.bundles == lastAllowlist, plan.systems == lastSystemAllowlist {
            if !activationPending { stateMessage = mode == .collapsed ? "Hidden items are tucked away" : "Showing hidden items" }
            updateUI()
            if !activationPending { visibilityDidFinish(true) }
            return
        }
        // Retain the acknowledged restriction until its replacement succeeds.
        generation &+= 1
        activationTimeout?.invalidate(); activationTimeout = nil
        if assertion !== settledAssertion { assertion?.invalidate() }
        assertion = nil; activationPending = false
        do {
            let next = try makeAssertion(plan.systems, plan.bundles)
            assertion = next
            lastAllowlist = plan.bundles; lastSystemAllowlist = plan.systems; activationPending = true
            let revision = generation
            stateMessage = "Updating menu bar…"
            next.activate { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, revision == self.generation else { return }
                    self.activationPending = false
                    self.activationTimeout?.invalidate(); self.activationTimeout = nil
                    if let error {
                        self.releaseRestriction()
                        self.stateMessage = "Could not hide apps; all items remain visible"
                        self.log("ACTIVATE failed: \(error)")
                    } else {
                        if self.settledAssertion !== self.assertion { self.settledAssertion?.invalidate() }
                        self.settledAssertion = self.assertion
                        self.stateMessage = self.mode == .collapsed ? "Hidden items are tucked away" : "Showing hidden items"
                        self.log("ACTIVATE success mode=\(self.mode.rawValue) excluded=\(plan.excluded) iStat=\(plan.bundles.contains(iStatID) ? "allowed" : "hidden")")
                    }
                    self.updateUI(); self.visibilityDidFinish(error == nil)
                }
            }
            activationTimeout = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                guard let self, revision == self.generation, self.activationPending else { return }
                self.visibilityUnavailable("Menu bar did not respond; hiding is paused")
            }
        } catch {
            visibilityUnavailable("Hiding is unavailable; all items remain visible")
            log(error.localizedDescription)
        }
        updateUI()
    }
}
