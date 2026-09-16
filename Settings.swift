import AppKit

extension MenuBarCompact {
    @discardableResult func label(_ text: String, frame: NSRect, size: CGFloat, secondary: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame; label.font = .systemFont(ofSize: size)
        if secondary { label.textColor = .secondaryLabelColor }
        window?.contentView?.addSubview(label)
        return label
    }
    @discardableResult func button(_ text: String, action: Selector, frame: NSRect) -> NSButton {
        let button = NSButton(title: text, target: self, action: action)
        button.frame = frame; window?.contentView?.addSubview(button)
        return button
    }
    func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 630), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.window = window
        window.delegate = self; window.contentMinSize = NSSize(width: 800, height: 600)
        window.title = "MenuBarCompact"; window.isReleasedWhenClosed = false; window.animationBehavior = .none
        toggleButton = button("Open hidden panel", action: #selector(toggle(_:)), frame: NSRect(x: 24, y: 580, width: 180, height: 32))
        button("All hidden icons", action: #selector(showAll(_:)), frame: NSRect(x: 210, y: 580, width: 160, height: 32))
        takeOverButton = button("Quit Thaw and start", action: #selector(takeOver(_:)), frame: NSRect(x: 725, y: 580, width: 210, height: 32))
        let search = NSSearchField(frame: NSRect(x: 28, y: 533, width: 670, height: 30))
        self.search = search; search.placeholderString = "Find a configured item"; search.delegate = self; window.contentView?.addSubview(search)
        let allApps = NSButton(checkboxWithTitle: "Show all running apps", target: self, action: #selector(toggleAppScope(_:)))
        allAppsButton = allApps; allApps.frame = NSRect(x: 720, y: 536, width: 214, height: 24); window.contentView?.addSubview(allApps)
        for view in window.contentView?.subviews ?? [] { view.autoresizingMask = .minYMargin }
        search.autoresizingMask.insert(.width); allApps.autoresizingMask.insert(.minXMargin); takeOverButton?.autoresizingMask.insert(.minXMargin)
        let scroll = NSScrollView(frame: NSRect(x: 28, y: 208, width: 904, height: 304))
        visibilityEditorScroll = scroll
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay; scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.autoresizingMask = [.height, .width]
        let document = VisibilityDocument(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 304))
        scroll.documentView = document; window.contentView?.addSubview(scroll)
        let titles = ["Always Show", "Hide", "Always Hide"], details = ["In the menu bar", "In the second row", "Option-click to reveal"]
        for rule in 0..<3 {
            let heading = NSTextField(labelWithString: titles[rule]); heading.font = .systemFont(ofSize: 14, weight: .semibold)
            let detail = NSTextField(labelWithString: details[rule]); detail.font = .systemFont(ofSize: 10); detail.textColor = .secondaryLabelColor
            let count = NSTextField(labelWithString: ""); count.font = .systemFont(ofSize: 10); count.textColor = .secondaryLabelColor
            for label in [heading, detail, count] { document.addSubview(label) }
            visibilityLabels.append([heading, detail, count]); visibilityCounts.append(count)
            let lane = VisibilityLane(frame: .zero); lane.rule = rule; lane.editorDelegate = self; lane.setAccessibilityLabel(titles[rule] + " drop area")
            document.addSubview(lane); visibilityLanes.append(lane)
        }
        label("Drag icons between sections to change visibility. Icons wrap automatically.", frame: NSRect(x: 28, y: 166, width: 905, height: 21), size: 12, secondary: true)
        let auto = NSButton(checkboxWithTitle: "Close panel after 15 seconds", target: self, action: #selector(toggleAutoHide(_:)))
        autoHideButton = auto; auto.frame = NSRect(x: 28, y: 122, width: 320, height: 24); auto.state = UserDefaults.standard.bool(forKey: "AutoRehide") ? .on : .off; window.contentView?.addSubview(auto)
        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin(_:)))
        loginButton = login; login.frame = NSRect(x: 420, y: 122, width: 350, height: 24); window.contentView?.addSubview(login)
        loginLabel = label("", frame: NSRect(x: 420, y: 96, width: 370, height: 22), size: 11, secondary: true)
        compatibilityLabel = label("", frame: NSRect(x: 28, y: 60, width: 760, height: 22), size: 12, secondary: true)
        button("Check iStat", action: #selector(checkCompatibility(_:)), frame: NSRect(x: 23, y: 18, width: 120, height: 30))
        button("Diagnostics…", action: #selector(openDiagnostics(_:)), frame: NSRect(x: 150, y: 18, width: 145, height: 30))
        button("Rescan system items", action: #selector(discoverSystemItems(_:)), frame: NSRect(x: 300, y: 18, width: 180, height: 30))
        label("MenuBarCompact 0.7.0 · drag to organize", frame: NSRect(x: 525, y: 23, width: 270, height: 22), size: 11, secondary: true)
        userResizedSettings = true
        userResizedSettings = window.setFrameUsingName("MenuBarCompact.Settings")
        if !userResizedSettings { window.center() }
        window.setFrameAutosaveName("MenuBarCompact.Settings")
    }
    func windowWillStartLiveResize(_ notification: Notification) { userResizedSettings = true }
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { userResizedSettings = true; return true }
    func windowDidResize(_ notification: Notification) { if !visibilityLanes.isEmpty, !layingOutSettings { renderVisibilityLanes() } }
    @objc func showSettings(_ sender: Any?) {
        overflow?.performClose(nil)
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil); refreshApps(); updateUI(); updateLoginUI(); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if overflow?.isShown != true { showSettings(nil) }; return true }
    func canMoveVisibilityItem(_ identifier: String, to rule: Int) -> Bool {
        guard (0..<3).contains(rule), !protectedID(identifier) else { return false }
        if identifier.hasPrefix("system."), SystemCatalog.items[identifier] == nil { return false }
        return rules[identifier] != nil || running[identifier] != nil || SystemCatalog.items[identifier] != nil
    }
    func moveVisibilityItem(_ identifier: String, to rule: Int) {
        guard canMoveVisibilityItem(identifier, to: rule), (rules[identifier] ?? 0) != rule else { return }
        finishInteraction(); rules[identifier] = rule
        saveRules(); rebuildRows(); applyVisibility()
    }
    func renderVisibilityLanes() {
        guard !layingOutSettings, let scroll = visibilityEditorScroll, let window, let document = scroll.documentView else { return }
        layingOutSettings = true
        defer { layingOutSettings = false }
        let titles = ["Always Show", "Hide", "Always Hide"]
        var groups = [[SettingsRow]](repeating: [], count: 3)
        for row in rows { groups[protectedID(row.id) ? 0 : min(2, max(0, row.rule))].append(row) }
        let width = scroll.contentSize.width - 156
        let totalHeight = groups.reduce(CGFloat(28)) { $0 + visibilityHeight($1.count, width) }
        let filtering = !(search?.stringValue.isEmpty ?? true)
        if !userResizedSettings, !filtering, let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
            let maxHeight = window.contentRect(forFrameRect: screen).height - 16
            let height = min(maxHeight, 630 + max(0, totalHeight - 304))
            if abs((window.contentView?.bounds.height ?? 0) - height) > 0.5 {
                var frame = window.frame; let oldHeight = frame.height
                frame.size.height = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: window.contentView?.bounds.width ?? 960, height: height)).height
                frame.origin.y = max(screen.minY, min(frame.origin.y + oldHeight - frame.height, screen.maxY - frame.height))
                window.setFrame(frame, display: true, animate: false)
            }
        }
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: totalHeight)
        var y: CGFloat = 0
        for rule in visibilityLanes.indices {
            let items = groups[rule], lane = visibilityLanes[rule], height = visibilityHeight(groups[rule].count, width)
            lane.frame = NSRect(x: 156, y: y, width: width, height: height)
            visibilityLabels[rule][0].frame = NSRect(x: 0, y: y + 18, width: 148, height: 22)
            visibilityLabels[rule][1].frame = NSRect(x: 0, y: y + 40, width: 148, height: 18)
            visibilityLabels[rule][2].frame = NSRect(x: 0, y: y + 62, width: 148, height: 18)
            y += height + 14
            let key = LaneRenderKey(rows: items, filtering: filtering, columns: visibilityColumns(width))
            if renderedLaneRows[rule] == key { continue }
            renderedLaneRows[rule] = key
            for view in lane.subviews { view.removeFromSuperview() }
            visibilityCounts[rule].stringValue = "\(items.count) item\(items.count == 1 ? "" : "s")"
            for (index, row) in items.enumerated() {
                let locked = protectedID(row.id)
                let icon = VisibilityIcon(frame: visibilityIconFrame(index, items.count, width))
                icon.identifier = NSUserInterfaceItemIdentifier(row.id); icon.title = row.name; icon.font = .systemFont(ofSize: 10); icon.isBordered = false; icon.imagePosition = .imageAbove
                let image = rowIcon(for: row.id, name: row.name)?.copy() as? NSImage
                image?.size = NSSize(width: 24, height: 24); icon.image = image; icon.imageScaling = .scaleProportionallyDown
                icon.cell?.lineBreakMode = .byTruncatingTail; icon.movable = !locked
                icon.setAccessibilityLabel("\(row.name) — \(titles[rule])\(locked ? " (protected)" : "")")
                icon.toolTip = "\(row.name)\n\(locked ? "Kept visible" : "Drag to another section to change visibility")"
                lane.addSubview(icon)
            }
            if items.isEmpty {
                let empty = NSTextField(labelWithString: filtering ? "No matching items in this section" : "Drop icons here")
                empty.textColor = .tertiaryLabelColor; empty.font = .systemFont(ofSize: 12); empty.frame = NSRect(x: 20, y: 32, width: 400, height: 20); lane.addSubview(empty)
            }
            lane.needsDisplay = true
        }
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: min(clip.bounds.origin.y, max(0, totalHeight - clip.bounds.height))))
        scroll.reflectScrolledClipView(clip)
    }
    func controlTextDidChange(_ notification: Notification) { rebuildRows() }
}
