import AppKit

func visibilityColumns(_ width: CGFloat) -> Int { max(1, Int(floor(max(0, width - 8) / 56))) }
func visibilityHeight(_ count: Int, _ width: CGFloat) -> CGFloat {
    let columns = visibilityColumns(width)
    return CGFloat(92 + (max(1, (count + columns - 1) / columns) - 1) * 68)
}
func visibilityIconFrame(_ index: Int, _ count: Int, _ width: CGFloat) -> NSRect {
    let columns = visibilityColumns(width)
    let x = CGFloat(6 + (index % columns) * 56)
    let y = visibilityHeight(count, width) - 74 - CGFloat((index / columns) * 68)
    return NSRect(x: x, y: y, width: 52, height: 64)
}
final class VisibilityDocument: NSView { override var isFlipped: Bool { true } }
private let visibilityDragType = NSPasteboard.PasteboardType("io.github.iamwrm.MenuBarCompact.visibility-item")
protocol VisibilityEditorDelegate: AnyObject {
    func canMoveVisibilityItem(_ identifier: String, to rule: Int) -> Bool
    func moveVisibilityItem(_ identifier: String, to rule: Int)
}
final class VisibilityIcon: NSButton, NSDraggingSource {
    var movable = false
    private var dragStarted = false
    private var dragStartEvent: NSEvent?
    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted || window?.firstResponder === self {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
        }
        image?.draw(in: NSRect(x: (bounds.width - 24) / 2, y: 8, width: 24, height: 24), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 2, y: 43, width: bounds.width - 4, height: 16), withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        if !movable {
            NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.draw(in: NSRect(x: bounds.width - 15, y: 5, width: 9, height: 10), from: .zero, operation: .sourceOver, fraction: 0.5, respectFlipped: true, hints: nil)
        }
    }
    override func mouseDown(with event: NSEvent) { dragStartEvent = event; dragStarted = false; isHighlighted = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) { isHighlighted = false; needsDisplay = true; dragStartEvent = nil }
    override func mouseDragged(with event: NSEvent) {
        guard movable, !dragStarted, let startEvent = dragStartEvent, let identifier else { return }
        let start = startEvent.locationInWindow
        guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
        dragStarted = true; isHighlighted = false; needsDisplay = true
        let payload = NSPasteboardItem()
        payload.setString(identifier.rawValue, forType: visibilityDragType)
        let item = NSDraggingItem(pasteboardWriter: payload)
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { dragStarted = false; return }
        cacheDisplay(in: bounds, to: bitmap)
        let preview = NSImage(size: bounds.size)
        preview.addRepresentation(bitmap)
        item.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [item], event: startEvent, source: self).animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragStartEvent = nil; dragStarted = false; isHighlighted = false; needsDisplay = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { context == .withinApplication ? .move : [] }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
final class VisibilityLane: NSView {
    var rule = 0
    private var dropHighlighted = false
    weak var editorDelegate: VisibilityEditorDelegate?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([visibilityDragType])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        (dropHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.13) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (dropHighlighted ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = dropHighlighted ? 2 : 0.5
        path.stroke()
    }
    private func acceptedIdentifier(_ sender: NSDraggingInfo) -> String? {
        guard let source = sender.draggingSource as? VisibilityIcon, source.movable, source.window === window,
              let identifier = sender.draggingPasteboard.string(forType: visibilityDragType), source.identifier?.rawValue == identifier,
              editorDelegate?.canMoveVisibilityItem(identifier, to: rule) == true else { return nil }
        return identifier
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let highlight = acceptedIdentifier(sender) != nil
        if dropHighlighted != highlight { dropHighlighted = highlight; needsDisplay = true }
        return highlight ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropHighlighted = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { acceptedIdentifier(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlighted = false; needsDisplay = true
        guard let identifier = acceptedIdentifier(sender) else { return false }
        let delegate = editorDelegate, rule = rule
        // Rebuild only after AppKit has finished delivering the drop.
        DispatchQueue.main.async { delegate?.moveVisibilityItem(identifier, to: rule) }
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { dropHighlighted = false; needsDisplay = true }
}
