import Foundation
import Darwin

@objc(MBRuntimeSystemItems)
final class RuntimeSystemItems: NSObject {
    // This private framework already supplies the visibility assertion. Resolve
    // its CaseIterable metadata instead of guessing an integer range of cases.
    @objc static func items() -> [[String: Any]] { discoveredItems }
    private static let discoveredItems: [[String: Any]] = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW),
              let type = _typeByName("17MenuBarClientCore22MBSystemItemIdentifierO") as? any CaseIterable.Type,
              let symbol = dlsym(handle, "$s17MenuBarClientCore22MBSystemItemIdentifierO11stringValueSSvg") else { return [] }
        // Verified macOS 27 ABI: the raw-representable enum passes one Int and
        // this getter returns Swift.String. Never call it with invented values.
        let name = unsafeBitCast(symbol, to: (@convention(thin) (Int) -> String).self)
        var result: [[String: Any]] = []
        var seen = Set<String>()
        for value in type.allCases {
            guard let raw = (value as? any RawRepresentable)?.rawValue as? Int, raw >= 0 else { return [] }
            let token = name(raw)
            guard !token.isEmpty, token.count < 100, seen.insert(token).inserted else { return [] }
            result.append(["raw": raw, "token": token])
        }
        return result
    }()
}
