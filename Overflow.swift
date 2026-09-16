import AppKit
import ApplicationServices

extension MenuBarCompact {
    func finishInteraction() {
        interactionRevision.advance(); visibilityReadyHandler = nil
        interactionTimer?.invalidate(); interactionTimer = nil
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if activeItem != nil { activeItem = nil; applyVisibility() }
    }
    func schedulePanelClose() {
        rehideTimer?.invalidate(); rehideTimer = nil
        if overflow?.isShown == true, UserDefaults.standard.bool(forKey: "AutoRehide") {
            let timer = Timer(timeInterval: 15, target: self, selector: #selector(hide(_:)), userInfo: nil, repeats: false)
            rehideTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    @objc func toggle(_ sender: Any?) { if overflow?.isShown == true { hide(nil) } else { openOverflow(includeAlwaysHidden: false) } }
    @objc func showAll(_ sender: Any?) { openOverflow(includeAlwaysHidden: true) }
    @objc func hide(_ sender: Any?) { overflow?.performClose(nil); rehideTimer?.invalidate(); rehideTimer = nil; finishInteraction(); updateUI() }
    func popoverDidClose(_ notification: Notification) { rehideTimer?.invalidate(); rehideTimer = nil; updateUI() }
    func requestMenuAccess() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func rowIcon(for identifier: String, name: String) -> NSImage? {
        let key = "\(identifier):\(running[identifier]?.processIdentifier ?? 0)" as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let image = loadRowIcon(for: identifier, name: name)
        if let image { iconCache.setObject(image, forKey: key) }
        return image
    }
    func loadRowIcon(for identifier: String, name: String) -> NSImage? {
        if let system = SystemCatalog.items[identifier] {
            let plugin = system.bundlePath.isEmpty ? nil : Bundle(path: system.bundlePath)
            for resource in ["MenuBarIcon", "menu", "StatusBarIcon"] {
                if let image = plugin?.image(forResource: resource)?.copy() as? NSImage { image.isTemplate = true; return image }
            }
            return NSImage(systemSymbolName: system.symbol, accessibilityDescription: name) ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: name)
        }
        let bundle = running[identifier]?.bundleURL.flatMap { Bundle(url: $0) }
        var candidates = ["MenuBarIcon", "StatusBarIcon", "StatusItemIcon", "TrayIcon"]
        if let known = ["org.pqrs.ShowyEdge": "menu", "com.openai.codex": "Icon/Logo", "com.box.desktop.ui": "BoxLogo"][identifier] { candidates.insert(known, at: 0) }
        for resource in candidates {
            if let image = bundle?.image(forResource: resource)?.copy() as? NSImage { image.isTemplate = true; return image }
        }
        return running[identifier]?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: name)
    }
    func openOverflow(includeAlwaysHidden all: Bool) {
        refreshApps(); finishInteraction(); mode = .collapsed; applyVisibility(); includeAlwaysHidden = all
        let items = VisibilityPolicy.panelItems(running: Array(running.keys), rules: rules, ownID: ownID, includeAlwaysHidden: all).map { id in
            (id: id, name: SystemCatalog.items[id]?.name ?? names[id] ?? id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard let button = statusItem?.button else { return }
        let available = (button.window?.screen ?? NSScreen.main)?.visibleFrame.width ?? 960
        let contentWidth = CGFloat(max(1, items.count) * 32), width = min(available - 40, contentWidth + 16), height: CGFloat = 32
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let strip = NSScrollView(frame: NSRect(x: 8, y: 0, width: width - 16, height: height))
        strip.drawsBackground = false; strip.hasHorizontalScroller = true; strip.autohidesScrollers = true; strip.scrollerStyle = .overlay
        let row = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: height))
        strip.documentView = row; controller.view.addSubview(strip)
        for (index, item) in items.enumerated() {
            var icon = rowIcon(for: item.id, name: item.name)?.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            if SystemCatalog.items[item.id] != nil { icon = icon?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)) ?? icon }
            let control = NSButton(image: icon ?? NSImage(), target: self, action: #selector(openHiddenMenu(_:)))
            control.identifier = NSUserInterfaceItemIdentifier(item.id); control.imagePosition = .imageOnly; control.imageScaling = .scaleProportionallyDown; control.bezelStyle = .regularSquare; control.isBordered = false
            control.toolTip = item.name; control.setAccessibilityLabel("Open menu for " + item.name)
            control.frame = NSRect(x: index * 32, y: 2, width: 32, height: 28); row.addSubview(control)
        }
        if items.isEmpty {
            let empty = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "No running hidden items") ?? NSImage(), target: self, action: #selector(showSettings(_:)))
            empty.isBordered = false; empty.frame = NSRect(x: 0, y: 2, width: 32, height: 28); empty.toolTip = "No running hidden items — open Settings"; row.addSubview(empty)
        }
        let popover = overflow ?? NSPopover()
        if overflow == nil { overflow = popover; popover.animates = false; popover.behavior = .transient; popover.delegate = self }
        popover.contentViewController = controller; popover.contentSize = NSSize(width: width, height: height)
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        NSApp.activate(ignoringOtherApps: true); controller.view.window?.makeKey()
        schedulePanelClose(); updateUI()
        log("PANEL open items=\(items.count); main bar remains collapsed; Accessibility=\(AXIsProcessTrusted() ? "allowed" : "needed")")
    }
    func showMenuError(_ title: String, detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    func activateMenu(identifier: String, pid: pid_t, before: [AXUIElement], metadata: MenuMetadata, revision: UInt, started: TimeInterval) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var targets: [AXUIElement] = [], previousRect: CGRect?, previousTarget: AXUIElement?
            let deadline = ProcessInfo.processInfo.systemUptime + 2.2
            var stable = false, probes = 0
            while ProcessInfo.processInfo.systemUptime < deadline {
                if revision != self.interactionRevision.read() { return }
                targets = MenuActivation.targets(pid: pid, before: before, metadata: metadata); probes += 1
                if targets.count > 1 { break }
                let target = targets.count == 1 ? targets.first : nil
                let rect = target.flatMap(MenuActivation.screenRect)
                stable = rect != nil && previousRect == rect && target != nil && previousTarget != nil && CFEqual(target!, previousTarget!)
                if stable { break }
                previousRect = rect; previousTarget = target
                Thread.sleep(forTimeInterval: probes < 4 ? 0.04 : 0.1)
            }
            // Capture immutable results before returning to the main queue.
            let found = targets, isStable = stable, attempts = probes
            DispatchQueue.main.async { [weak self] in
                guard let self, revision == self.interactionRevision.read() else { return }
                guard isStable, let target = found.first else {
                    self.finishInteraction()
                    self.showMenuError("Could not open this menu", detail: found.count > 1 ? "This app exposes multiple menu controls. Direct selection is not available yet." : "The menu-bar host did not expose a stable matching control. The item has been hidden again.")
                    return
                }
                self.log(String(format: "MENU ready %@ after %.0f ms (%d probes)", identifier, (ProcessInfo.processInfo.systemUptime - started) * 1000, attempts))
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self, revision == self.interactionRevision.read() else { return }
                    let result = identifier == iStatID ? MenuActivation.click(target) : MenuActivation.press(target)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, revision == self.interactionRevision.read() else { return }
                        self.log(String(format: "MENU activation result=%d for %@ after %.0f ms", result.rawValue, identifier, (ProcessInfo.processInfo.systemUptime - started) * 1000))
                        if result != .success, result != .cannotComplete {
                            self.finishInteraction(); self.showMenuError("Could not open this menu", detail: "The app declined the Accessibility menu request."); return
                        }
                        self.interactionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.finishInteraction() }
                        self.outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .keyDown]) { [weak self] event in
                            if event.type == .keyDown, event.keyCode != 53 { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                                guard let self, revision == self.interactionRevision.read() else { return }
                                self.finishInteraction()
                            }
                        }
                    }
                }
            }
        }
    }
    @objc func openHiddenMenu(_ sender: NSButton) {
        guard AXIsProcessTrusted() else {
            overflow?.performClose(nil); requestMenuAccess()
            showMenuError("macOS has not granted this build access", detail: "If MenuBarCompact is already enabled in Device Control and Data Access, remove its old entry and add /Applications/MenuBarCompact.app again. This update uses a consistent developer signature so later builds can retain the grant.")
            return
        }
        guard let identifier = sender.identifier?.rawValue else { return }
        let started = ProcessInfo.processInfo.systemUptime, item = SystemCatalog.items[identifier]
        let metadata = MenuMetadata(item: item, preferHost: identifier == iStatID)
        finishInteraction(); rehideTimer?.invalidate()
        let revision = interactionRevision.read()
        var pid = running[identifier]?.processIdentifier ?? 0
        if let host = item?.hostBundle, !host.isEmpty { pid = running[host]?.processIdentifier ?? 0 }
        if identifier == "system.input-method" { pid = running["com.apple.TextInputMenuAgent"]?.processIdentifier ?? 0 }
        let targetPID = pid
        overflow?.performClose(nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let before = MenuActivation.hostButtons()
            DispatchQueue.main.async { [weak self] in
                guard let self, revision == self.interactionRevision.read() else { return }
                self.activeItem = identifier
                self.visibilityReadyHandler = { [weak self] success in
                    guard let self, revision == self.interactionRevision.read() else { return }
                    guard success else {
                        self.finishInteraction(); self.showMenuError("Could not reveal this item", detail: "The menu-bar host did not accept the visibility change. Try opening the panel again."); return
                    }
                    self.activateMenu(identifier: identifier, pid: targetPID, before: before, metadata: metadata, revision: revision, started: started)
                }
                self.applyVisibility()
            }
        }
    }
    @objc func statusClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            let menu = NSMenu(); menu.delegate = self
            let entries: [(String, Selector)] = [("Hidden icons…", #selector(toggle(_:))), ("All hidden icons…", #selector(showAll(_:))), ("Settings…", #selector(showSettings(_:)))]
            for (title, action) in entries { menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
            menu.addItem(.separator()); menu.addItem(withTitle: "Quit MenuBarCompact", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem?.menu = menu; statusItem?.button?.performClick(nil); statusItem?.menu = nil
        } else if event?.modifierFlags.contains(.option) == true { showAll(nil) }
        else { toggle(nil) }
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }
}
