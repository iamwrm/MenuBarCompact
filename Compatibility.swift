import AppKit
import ServiceManagement

extension MenuBarCompact {
    func compatibilityFingerprint() -> CompatibilityFingerprint {
        let support = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        var paths: [String] = []
        for bundle in [support.appendingPathComponent("iStat Menus 7/iStat Menus Menubar.app"), URL(fileURLWithPath: "/Applications/iStat Menus Menubar Compatibility.app")] {
            for file in ["Contents/MacOS/iStat Menus Menubar", "Contents/Info.plist", "Contents/_CodeSignature/CodeResources"] { paths.append(bundle.appendingPathComponent(file).path) }
        }
        paths.append(NSHomeDirectory() + "/Library/LaunchAgents/com.bjango.istatmenus.status.plist")
        paths.append(support.appendingPathComponent("MenuBarCompact/workaround.json").path)
        return CompatibilityFingerprint(files: FileFingerprint.read(paths), pid: running[iStatID]?.processIdentifier ?? 0)
    }
    @objc func checkCompatibility(_ sender: Any?) {
        guard compatibilityTask == nil, !paused else { return }
        let fingerprint = compatibilityFingerprint(), now = ProcessInfo.processInfo.systemUptime
        guard needsCompatibilityAudit(current: fingerprint, verified: verifiedCompatibilityFingerprint, ready: ready, elapsed: now - lastCompatibilityAudit, sinceAttempt: lastCompatibilityAttempt > 0 ? now - lastCompatibilityAttempt : 60, force: sender != nil) else { return }
        lastCompatibilityAttempt = now
        guard let script = Bundle.main.path(forResource: "istat_workaround", ofType: "py") else {
            ready = false; compatibilityMessage = "Compatibility helper is missing; reinstall MenuBarCompact"; applyVisibility(); return
        }
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); task.arguments = [script, "ensure"]; task.qualityOfService = .utility
        task.standardOutput = pipe; task.standardError = pipe; compatibilityTask = task
        do { try task.run() }
        catch {
            compatibilityTask = nil; ready = false; compatibilityMessage = "Could not check iStat; open diagnostics for details"; log(error.localizedDescription); applyVisibility(); return
        }
        let manual = sender != nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.compatibilityTask = nil; self.ready = task.terminationStatus == 0
                self.compatibilityMessage = self.ready ? "iStat compatibility is ready · checked automatically" : "iStat compatibility needs attention · hiding is paused"
                if !self.ready || manual { self.log(String(data: data, encoding: .utf8) ?? "Compatibility check returned no output") }
                self.refreshApps()
                if self.ready { self.verifiedCompatibilityFingerprint = self.compatibilityFingerprint(); self.lastCompatibilityAudit = ProcessInfo.processInfo.systemUptime }
                self.applyVisibility()
            }
        }
    }
    func setLoginEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled { try service.register() }
            else if !enabled, service.status != .notRegistered { try service.unregister() }
        } catch { log("LOGIN: \(error)") }
        updateLoginUI()
    }
    @objc func toggleLogin(_ sender: NSButton) { setLoginEnabled(sender.state == .on) }
    @objc func toggleAutoHide(_ sender: NSButton) { UserDefaults.standard.set(sender.state == .on, forKey: "AutoRehide"); schedulePanelClose() }
    func updateLoginUI() {
        let status = SMAppService.mainApp.status
        loginButton?.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginLabel?.stringValue = status == .enabled ? "Starts automatically when you sign in" : (status == .requiresApproval ? "Allow MenuBarCompact in System Settings → Login Items" : "Open MenuBarCompact when you want to use it")
    }
}
