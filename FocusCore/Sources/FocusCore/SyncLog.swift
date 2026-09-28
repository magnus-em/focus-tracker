import Foundation
import os

/// Structured cross-device sync log. Every state push, every remote-state
/// application, every Multipeer connect/disconnect, every CloudKit import
/// notification — all get appended here as JSONL lines.
///
/// Why a single global log: we have THREE independent paths that mutate
/// the timer state on each device (CK poll, CK import notification,
/// Multipeer message), plus local user actions. When sync misbehaves we
/// need a single timeline to read, not scattered prints. This file gives
/// us that.
///
/// Where it writes:
///   • os_log subsystem "com.focus.sync" — for live tailing with
///     `log stream --predicate 'subsystem == "com.focus.sync"'`
///   • A JSONL file at `<AppSupport>/Focus/sync.log` (iOS: app sandbox).
///     One line per event, truncated to last ~10k lines at process
///     start so it doesn't grow unbounded.
///
/// Read it from bash:
///   tail -50 ~/Library/Application\ Support/Focus/sync.log | jq .
public enum SyncLog {
    public enum Source: String, Sendable {
        case mac, iPad, unknown
    }

    private static let logger = Logger(subsystem: "com.focus.sync", category: "timer")
    private static let queue = DispatchQueue(label: "com.focus.sync.log", qos: .utility)
    private static let iso = ISO8601DateFormatter()
    private static let device: Source = {
        #if os(macOS)
        return .mac
        #elseif os(iOS)
        return .iPad
        #else
        return .unknown
        #endif
    }()

    /// Where the JSONL file lives. On macOS: `~/Library/Application Support/Focus/sync.log`.
    /// On iOS: `<container>/Library/Application Support/Focus/sync.log`.
    public static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Focus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync.log")
    }

    /// Truncate the file to its last `keep` lines. Cheap because the file
    /// is small (10k JSONL lines ~ 2-3 MB).
    public static func truncateIfLarge(keep: Int = 10_000) {
        queue.async {
            guard let data = try? Data(contentsOf: fileURL) else { return }
            guard data.count > 3_000_000 else { return }
            let str = String(data: data, encoding: .utf8) ?? ""
            let lines = str.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count > keep else { return }
            let trimmed = lines.suffix(keep).joined(separator: "\n")
            try? trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Coerce an Optional to `Any` for inclusion in the fields dict.
    /// Use `SyncLog.opt(date)` instead of `date ?? NSNull()` (which doesn't
    /// type-check since `Date?` and `NSNull` can't unify).
    public static func opt<T>(_ value: T?) -> Any {
        if let v = value { return v }
        return NSNull()
    }

    /// Log one event. `event` is a short tag like "push", "applyState",
    /// "mpRecv", "mpConnect". `fields` is any JSON-serializable dict.
    public static func event(_ event: String, _ fields: [String: Any] = [:]) {
        let ts = iso.string(from: Date())
        var record: [String: Any] = [
            "ts": ts,
            "dev": device.rawValue,
            "ev": event,
        ]
        for (k, v) in fields { record[k] = sanitize(v) }
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8) else { return }
            logger.log("\(line, privacy: .public)")
            appendLine(line)
        }
    }

    private static func appendLine(_ line: String) {
        let url = fileURL
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// JSONSerialization can't handle Date, UUID, etc. Coerce common types.
    private static func sanitize(_ v: Any) -> Any {
        switch v {
        case let d as Date: return iso.string(from: d)
        case let u as UUID: return u.uuidString
        case let arr as [Any]: return arr.map { sanitize($0) }
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (k, val) in dict { out[k] = sanitize(val) }
            return out
        case is NSNull: return NSNull()
        case let s as String: return s
        case let n as NSNumber: return n
        default: return String(describing: v)
        }
    }
}
