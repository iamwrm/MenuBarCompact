import Foundation
@main struct RuntimeDiscoveryTest {
    static func main() {
        let entries = RuntimeSystemItems.items()
        precondition(!entries.isEmpty, "Runtime system item enumeration unavailable")
        let tokens = entries.compactMap { $0["token"] as? String }
        let raw = entries.compactMap { $0["raw"] as? Int }
        precondition(tokens.count == entries.count && raw.count == entries.count)
        precondition(Set(tokens).count == tokens.count && Set(raw).count == raw.count)
        precondition(tokens.contains("battery") && tokens.contains("keyboard"))
        print("Runtime discovery test passed: \(entries.count) OS categories.")
    }
}
