import Foundation

/// Simple logger with timestamps.
enum Log {
    static func info(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] INFO  \(msg)")
    }

    static func error(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("[\(ts)] ERROR \(msg)\n", stderr)
    }

    static func warn(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        fputs("[\(ts)] WARN  \(msg)\n", stderr)
    }
}
