import AppKit
import ServiceManagement

let ownID = "io.github.iamwrm.MenuBarCompact"
let thawID = "com.stonerl.Thaw"
let iStatID = "com.bjango.istatmenus.status"

struct SettingsRow: Equatable {
    var id: String
    var name: String
    var running: Bool
    var pid: pid_t
    var rule: Int
    var system: SystemItem?
}
struct LaneRenderKey: Equatable {
    var rows: [SettingsRow]
    var filtering: Bool
    var columns: Int
}
// Menu probes run off-main; preserve the atomic cancellation reads of ObjC.
final class InteractionRevision {
    private let lock = NSLock()
    private var value: UInt = 0
    func read() -> UInt { lock.lock(); defer { lock.unlock() }; return value }
    func advance() { lock.lock(); value &+= 1; lock.unlock() }
}

class MenuBarCompact: NSObject, NSApplicationDelegate, VisibilityEditorDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSPopoverDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    var compatibilityLabel: NSTextField?, loginLabel: NSTextField?
    var loginButton: NSButton?, autoHideButton: NSButton?, takeOverButton: NSButton?, toggleButton: NSButton?, allAppsButton: NSButton?
    var search: NSSearchField?
    var visibilityEditorScroll: NSScrollView?
    var visibilityLanes: [VisibilityLane] = []
    var userResizedSettings = false, layingOutSettings = false
    var visibilityLabels: [[NSTextField]] = []
    var visibilityCounts: [NSTextField] = []
    var rules: [String: Int] = [:]
    var names: [String: String] = [:]
    var rows: [SettingsRow] = []
    var running: [String: NSRunningApplication] = [:]
    var assertion: RestrictionAssertion?, settledAssertion: RestrictionAssertion?
    var makeAssertion: ([Int], [String]) throws -> RestrictionAssertion = { try NativeRestriction(systems: $0, bundles: $1) }
    var visibilityReadyHandler: ((Bool) -> Void)?
    var lastAllowlist: [String]?, lastSystemAllowlist: [Int]?
    var rehideTimer: Timer?, maintenance: Timer?, activationTimeout: Timer?
    var verifiedCompatibilityFingerprint: CompatibilityFingerprint?
    var lastCompatibilityAudit: TimeInterval = 0, lastCompatibilityAttempt: TimeInterval = 0
    let iconCache: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.countLimit = 128; return cache }()
    var renderedLaneRows: [Int: LaneRenderKey] = [:]
    var closedStatusImage: NSImage?, openStatusImage: NSImage?
    var compatibilityTask: Process?
    var generation: UInt = 0, refreshGeneration: UInt = 0
    var mode = VisibilityMode.collapsed
    var ready = false, menuOpen = false, paused = false, activationPending = false, discoveryReady = false
    var stateMessage = "Starting…", compatibilityMessage = "Checking iStat compatibility…"
    var logURL: URL?
    var overflow: NSPopover?
    var includeAlwaysHidden = false
    var activeItem: String?
    var interactionTimer: Timer?
    let interactionRevision = InteractionRevision()
    var outsideMonitor: Any?

    func log(_ message: String) {
        NSLog("%@", message)
        guard let logURL, let file = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data("\(Date()) \(message)\n".utf8))
    }
    func protectedID(_ identifier: String) -> Bool {
        SystemCatalog.items[identifier]?.protected ?? VisibilityPolicy.protectedBundle(identifier, ownID: ownID)
    }
    func saveRules() {
        UserDefaults.standard.set(rules, forKey: "VisibilityRules")
        UserDefaults.standard.set(names, forKey: "AppNames")
    }
    func importThawOnce() {
        let groups = UserDefaults.standard.persistentDomain(forName: thawID)?["MenuBarItemManager.savedSectionOrder"] as? [String: [String]] ?? [:]
        for group in ["alwaysHidden", "hidden", "visible"] {
            for item in groups[group] ?? [] {
                let identifier = item.components(separatedBy: ":").first ?? ""
                if !identifier.isEmpty, !protectedID(identifier) { rules[identifier] = group == "hidden" ? 1 : (group == "alwaysHidden" ? 2 : 0) }
            }
        }
        saveRules()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: ownID).count > 1 { NSApp.terminate(nil); return }
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("MenuBarCompact") {
            try? fm.createDirectory(at: support, withIntermediateDirectories: true)
            let url = support.appendingPathComponent("events.log")
            logURL = url
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.intValue > 512 * 1024 {
                try? fm.moveItem(at: url, to: support.appendingPathComponent("events-\(UUID().uuidString).log"))
            }
            if !fm.fileExists(atPath: url.path) { try? Data().write(to: url, options: .atomic) }
        }
        let prefs = UserDefaults.standard
        if prefs.object(forKey: "VisibilityRules") == nil, let legacy = prefs.persistentDomain(forName: "local.codex.MenuShelter") {
            for key in ["VisibilityRules", "AppNames", "AutoRehide"] { if let value = legacy[key] { prefs.set(value, forKey: key) } }
        }
        prefs.register(defaults: ["AutoRehide": true])
        discoverSystemItems(nil)
        let first = prefs.object(forKey: "VisibilityRules") == nil
        rules = prefs.dictionary(forKey: "VisibilityRules") as? [String: Int] ?? [:]
        names = prefs.dictionary(forKey: "AppNames") as? [String: String] ?? [:]
        if first { importThawOnce() }
        for identifier in Array(rules.keys) where protectedID(identifier) { rules.removeValue(forKey: identifier) }
        names[iStatID] = "iStat Menus"
        mode = .collapsed
        if prefs.object(forKey: "NSStatusItem Preferred Position MenuBarCompact.Main") == nil { prefs.set(0, forKey: "NSStatusItem Preferred Position MenuBarCompact.Main") }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = status; status.autosaveName = "MenuBarCompact.Main"
        status.button?.target = self; status.button?.action = #selector(statusClick(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.setAccessibilityLabel("MenuBarCompact")
        let main = NSMenu(), root = NSMenuItem(), app = NSMenu()
        main.addItem(root)
        app.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        app.addItem(withTitle: "Quit MenuBarCompact", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = app; NSApp.mainMenu = main
        let workspace = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(workspaceChanged(_:)), name: event, object: nil)
        }
        workspace.addObserver(self, selector: #selector(suspend(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(suspend(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        refreshApps(); checkCompatibility(nil)
        maintenance = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(maintain(_:)), userInfo: nil, repeats: true)
        maintenance?.tolerance = 10
        if ProcessInfo.processInfo.arguments.contains("--enable-login") { setLoginEnabled(true) }
        if first || ProcessInfo.processInfo.arguments.contains("--settings") { showSettings(nil) }
        log("START MenuBarCompact 0.7.0")
    }
    @objc func workspaceChanged(_ note: Notification) {
        if note.name == NSWorkspace.didWakeNotification || note.name == NSWorkspace.sessionDidBecomeActiveNotification {
            paused = false; maintenance?.fireDate = Date(timeIntervalSinceNow: 60); releaseRestriction()
        }
        refreshGeneration &+= 1
        let revision = refreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, revision == self.refreshGeneration, !self.paused else { return }
            self.refreshApps(); self.checkCompatibility(nil); self.applyVisibility()
        }
    }
    @objc func suspend(_ note: Notification) { paused = true; maintenance?.fireDate = .distantFuture; overflow?.performClose(nil); finishInteraction(); releaseRestriction() }
    @objc func maintain(_ sender: Any?) { if paused { return }; pollApps(); discoverSystemItems(nil); checkCompatibility(nil) }
    func pollApps() {
        var latest: [String: pid_t] = [:]
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            if let id = app.bundleIdentifier, !id.isEmpty { latest[id] = app.processIdentifier }
        }
        if latest != running.mapValues(\.processIdentifier) { refreshApps(); applyVisibility() }
    }
    func refreshApps() {
        var apps: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            guard let identifier = app.bundleIdentifier, !identifier.isEmpty else { continue }
            apps[identifier] = app
            if let name = app.localizedName, !name.isEmpty { names[identifier] = name }
        }
        running = apps; rebuildRows()
    }
    @objc func discoverSystemItems(_ sender: Any?) {
        let wasReady = discoveryReady
        guard let catalog = SystemCatalog.discover(force: sender != nil) else {
            discoveryReady = false; log("DISCOVERY unavailable — hiding paused"); applyVisibility(); return
        }
        discoveryReady = !catalog.isEmpty
        if wasReady == discoveryReady, catalog == SystemCatalog.items, sender == nil { return }
        if catalog != SystemCatalog.items {
            SystemCatalog.items = catalog; iconCache.removeAllObjects()
            log("DISCOVERY \(catalog.count) system items (\(SystemCatalog.categoryIDs.count) runtime categories)")
        }
        rebuildRows()
        if ready { applyVisibility() }
    }
    func rebuildRows() {
        guard window?.isVisible == true else { return }
        var ids = Set(rules.keys)
        ids.insert(iStatID); ids.formUnion(SystemCatalog.items.keys)
        if allAppsButton?.state == .on {
            for (id, app) in running where !protectedID(id) && (app.activationPolicy != .prohibited || rules[id] != nil) { ids.insert(id) }
        }
        let query = search?.stringValue ?? ""
        rows = ids.compactMap { id in
            var name = SystemCatalog.items[id]?.name ?? names[id]
            if name == nil {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension }
                else { name = id }
                names[id] = name
            }
            if id == iStatID { name = "iStat Menus" }
            let display = name ?? id
            if !query.isEmpty, display.range(of: query, options: .caseInsensitive) == nil, id.range(of: query, options: .caseInsensitive) == nil { return nil }
            return SettingsRow(id: id, name: display, running: running[id] != nil, pid: running[id]?.processIdentifier ?? 0, rule: rules[id] ?? 0, system: SystemCatalog.items[id])
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        renderVisibilityLanes()
    }
    @objc func takeOver(_ sender: Any?) { running[thawID]?.terminate(); stateMessage = "Waiting for Thaw to quit…"; updateUI() }
    @objc func openDiagnostics(_ sender: Any?) { if let logURL { NSWorkspace.shared.open(logURL) } }
    @objc func toggleAppScope(_ sender: Any?) { search?.placeholderString = allAppsButton?.state == .on ? "Find an app" : "Find a configured item"; rebuildRows() }
    // Kept overridable so lifecycle tests exercise this controller without UI.
    func updateUI() {
        let shown = overflow?.isShown == true
        if closedStatusImage == nil {
            closedStatusImage = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "MenuBarCompact"); closedStatusImage?.isTemplate = true
            openStatusImage = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "MenuBarCompact"); openStatusImage?.isTemplate = true
        }
        let image = shown ? openStatusImage : closedStatusImage
        if statusItem?.button?.image !== image { statusItem?.button?.image = image }
        let tip = "MenuBarCompact — \(stateMessage)\nClick for hidden icons below the menu bar. Right-click for settings. Option-click includes always-hidden icons."
        if statusItem?.button?.toolTip != tip { statusItem?.button?.toolTip = tip }
        guard window?.isVisible == true else { return }
        if compatibilityLabel?.stringValue != compatibilityMessage { compatibilityLabel?.stringValue = compatibilityMessage }
        takeOverButton?.isHidden = running[thawID] == nil
        let title = shown ? "Close hidden panel" : "Open hidden panel"
        if toggleButton?.title != title { toggleButton?.title = title }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if compatibilityTask?.isRunning == true { stateMessage = "Finishing iStat check before quitting…"; updateUI(); return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        paused = true; maintenance?.invalidate(); rehideTimer?.invalidate(); finishInteraction(); releaseRestriction(); saveRules(); log("STOP — menu-bar restriction released")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
