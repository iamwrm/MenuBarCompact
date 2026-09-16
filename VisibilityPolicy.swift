import Foundation

enum VisibilityMode: Int { case collapsed, revealed, everything }
struct VisibilityPlan: Equatable {
    var bundles: [String]
    var systems: [Int]
    var excluded: Int
}
enum VisibilityPolicy {
    static func protectedBundle(_ identifier: String, ownID: String) -> Bool {
        identifier.hasPrefix("com.apple.") || identifier == ownID || identifier == "com.stonerl.Thaw"
    }
    static func plan(running: [String], rules: [String: Int], ownID: String, mode: VisibilityMode) -> VisibilityPlan {
        var allowed = Set(running)
        allowed.formUnion(rules.keys.filter { !$0.hasPrefix("system.") })
        allowed.formUnion([ownID, "com.bjango.istatmenus.status", "com.bjango.istatmenus", "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent", "com.apple.Spotlight", "com.apple.campo", "com.apple.TextInputMenuAgent"])
        allowed.formUnion(SystemCatalog.items.values.flatMap(\.bundles))
        var systems = SystemCatalog.categoryIDs
        var excluded = 0
        for (identifier, rule) in rules {
            guard (rule == 1 && mode == .collapsed) || (rule == 2 && mode != .everything) else { continue }
            if let item = SystemCatalog.items[identifier] {
                if item.protected { continue }
                systems.removeAll { item.systems.contains($0) }
                allowed.subtract(item.bundles)
                excluded += 1
            } else if !identifier.hasPrefix("system."), !protectedBundle(identifier, ownID: ownID) {
                allowed.remove(identifier)
                excluded += 1
            }
        }
        return VisibilityPlan(bundles: allowed.sorted(), systems: systems, excluded: excluded)
    }
    static func panelItems(running: [String], rules: [String: Int], ownID: String, includeAlwaysHidden: Bool) -> [String] {
        rules.compactMap { identifier, rule in
            guard rule == 1 || (includeAlwaysHidden && rule == 2) else { return nil }
            let system = SystemCatalog.items[identifier]
            if identifier.hasPrefix("system."), system == nil || system!.protected { return nil }
            if system == nil, protectedBundle(identifier, ownID: ownID) || !running.contains(identifier) { return nil }
            return identifier
        }
    }
    static func interactionRules(_ rules: [String: Int], selected: String?) -> [String: Int] {
        guard let selected else { return rules }
        var effective = rules
        effective[selected] = 0
        return effective
    }
}
