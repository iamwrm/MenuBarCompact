import AppKit

autoreleasepool {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = MenuBarCompact()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
