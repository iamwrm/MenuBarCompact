import Foundation
import Darwin

struct FileFingerprint: Equatable {
    let path: String
    let metadata: [Int64]
    static func read(_ paths: [String]) -> [FileFingerprint] {
        paths.map { path in
            var info = stat()
            guard stat(path, &info) == 0 else { return FileFingerprint(path: path, metadata: []) }
            return FileFingerprint(path: path, metadata: [Int64(info.st_dev), Int64(bitPattern: info.st_ino), info.st_size, Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec), Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec)])
        }
    }
}
struct CompatibilityFingerprint: Equatable {
    var files: [FileFingerprint]
    var pid: pid_t
}
func needsCompatibilityAudit(current: CompatibilityFingerprint, verified: CompatibilityFingerprint?, ready: Bool, elapsed: TimeInterval, sinceAttempt: TimeInterval, force: Bool) -> Bool {
    if force { return true }
    if !ready { return sinceAttempt >= 60 }
    return current != verified || elapsed >= 3600
}
