import Foundation

@main struct PolicyBenchmark {
    static func main() {
        let runtime: [[String: Any]] = (0..<12).map { ["token": "category\($0)", "raw": $0] }
        SystemCatalog.items = SystemCatalog.build(runtime: runtime, plugins: [], specials: [:])
        let running = (0..<100).map { "example.app\($0)" }
        var rules: [String: Int] = [:]
        for i in 0..<40 { rules["example.app\(i)"] = i % 3 }
        for i in 0..<12 { rules["system.category\(i)"] = i % 3 }
        let start = ProcessInfo.processInfo.systemUptime
        var checksum = 0
        for i in 0..<10000 {
            let plan = VisibilityPolicy.plan(running: running, rules: rules, ownID: "test.own", mode: VisibilityMode(rawValue: i % 3)!)
            checksum += plan.bundles.count + plan.systems.count + plan.excluded
        }
        print(String(format: "%.3f ms; checksum %d", (ProcessInfo.processInfo.systemUptime - start) * 1000, checksum))
    }
}
