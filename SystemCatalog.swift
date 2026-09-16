import AppKit

struct SystemItem: Equatable {
    var name: String
    var symbol = "menubar.rectangle"
    var systems: [Int] = []
    var bundles: [String] = []
    var axIdentifiers: [String] = []
    var axName = ""
    var bundlePath = ""
    var hostBundle = ""
    var protected = false
    var source = ""
}

enum SystemCatalog {
    static var items: [String: SystemItem] = [:]
    static var categoryIDs: [Int] { Set(items.values.flatMap(\.systems)).sorted() }
    static func readableName(_ token: String) -> String {
        let capitals = token.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        if capitals > token.utf16.count / 2 { return token }
        let words = token.replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        return words.prefix(1).uppercased() + words.dropFirst()
    }
    // Aliases preserve existing preference keys. Category membership comes from macOS.
    static func build(runtime: [[String: Any]], plugins: [[String: String]], specials: [String: SystemItem]) -> [String: SystemItem] {
        let names = ["keyboard": "Input Method", "volume": "Sound", "wifi": "Wi-Fi", "primaryBentoBox": "Control Center"]
        let symbols = ["battery": "battery.100percent", "bluetooth": "antenna.radiowaves.left.and.right", "clock": "clock", "displays": "display", "keyboard": "character", "volume": "speaker.wave.2", "wifi": "wifi", "screenMirroring": "rectangle.on.rectangle", "primaryBentoBox": "switch.2"]
        var catalog: [String: SystemItem] = [:]
        for item in runtime {
            guard let token = item["token"] as? String, !token.isEmpty, let raw = item["raw"] as? Int else { continue }
            let key = "system." + (token == "keyboard" ? "input-method" : token)
            let ax = "com.apple.menuextra." + (token == "primaryBentoBox" ? "controlcenter" : token.lowercased())
            catalog[key] = SystemItem(name: names[token] ?? readableName(token), symbol: symbols[token] ?? "menubar.rectangle", systems: [raw], bundles: token == "keyboard" ? ["com.apple.TextInputMenuAgent"] : [], axIdentifiers: [ax], protected: token == "clock" || token == "primaryBentoBox", source: "macOS category")
        }
        for plugin in plugins {
            guard let bundle = plugin["bundle"], bundle.hasPrefix("com.apple.menuextra."), let name = plugin["name"], !name.isEmpty else { continue }
            if bundle == "com.apple.menuextra.airport", catalog["system.wifi"] != nil { continue }
            let symbol = ["com.apple.menuextra.TimeMachine": "clock.arrow.circlepath", "com.apple.menuextra.eject": "eject", "com.apple.menuextra.vpn": "network"][bundle] ?? "menubar.rectangle"
            let host = plugin["host"] ?? ""
            // Only an exclusively owned legacy host may be excluded.
            catalog["system.extra." + bundle] = SystemItem(name: name, symbol: symbol, bundles: host == "com.apple.systemuiserver" ? [bundle, host] : [bundle], axIdentifiers: [bundle], axName: name, bundlePath: plugin["path"] ?? "", hostBundle: host, source: "Installed menu extra")
        }
        catalog.merge(specials) { _, new in new }
        return catalog
    }
    private static var cachedCatalog: [String: SystemItem]?
    private static var cachedLoaded: [String] = []
    static func discover(force: Bool) -> [String: SystemItem]? {
        let loaded = UserDefaults.standard.persistentDomain(forName: "com.apple.systemuiserver")?["menuExtras"] as? [String] ?? []
        if !force, let cachedCatalog, loaded == cachedLoaded { return cachedCatalog }
        let runtime = RuntimeSystemItems.items()
        guard !runtime.isEmpty else { return nil } // Fail open, never guess category IDs.
        let directory = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras", isDirectory: true)
        var plugins: [[String: String]] = []
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
            guard url.pathExtension == "menu", let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier, identifier.hasPrefix("com.apple.menuextra.") else { continue }
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let name = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? readableName(url.deletingPathExtension().lastPathComponent)
            plugins.append(["bundle": identifier, "name": name, "path": url.path, "host": loaded.count == 1 && loaded.contains(url.path) ? "com.apple.systemuiserver" : ""])
        }
        var specials: [String: SystemItem] = [:]
        if let identifier = Bundle(path: "/System/Library/CoreServices/Spotlight.app")?.bundleIdentifier {
            specials["system.spotlight"] = SystemItem(name: "Spotlight", symbol: "magnifyingglass", bundles: [identifier, "com.apple.campo"], axName: "Spotlight", source: "Hosted system app")
        }
        cachedLoaded = loaded
        let catalog = build(runtime: runtime, plugins: plugins, specials: specials)
        cachedCatalog = catalog
        return catalog
    }
}
