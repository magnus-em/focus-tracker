import Foundation
import SwiftData
#if canImport(SQLite3)
import SQLite3
#endif

/// Daily snapshots of the SwiftData store, so a bad CloudKit reset or
/// migration is never the only copy of the data. Uses SQLite's online
/// backup API, which is safe while Core Data holds the store open and
/// folds the WAL into the copy (a plain file copy would not).
public enum StoreBackup {
    public static let keepDays = 14

    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Focus/backups", isDirectory: true)
    }

    /// Newest backup file, if any.
    public static var latest: (url: URL, date: Date)? {
        backups().first
    }

    /// Writes today's snapshot if one doesn't exist yet, then prunes old ones.
    @discardableResult
    public static func runDailyIfNeeded(container: ModelContainer) -> URL? {
        guard let storeURL = container.configurations.first?.url else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let dest = directory.appendingPathComponent("default-\(dayStamp(Date())).store")
        guard !fm.fileExists(atPath: dest.path) else { return nil }

        let tmp = dest.appendingPathExtension("partial")
        try? fm.removeItem(at: tmp)
        guard copy(from: storeURL, to: tmp) else {
            try? fm.removeItem(at: tmp)
            SyncLog.event("storeBackupFailed", ["store": storeURL.path])
            return nil
        }
        try? fm.moveItem(at: tmp, to: dest)
        prune()
        SyncLog.event("storeBackup", ["file": dest.lastPathComponent])
        return dest
    }

    private static func backups() -> [(url: URL, date: Date)] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "store" }
            .compactMap { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return date.map { (url, $0) }
            }
            .sorted { $0.date > $1.date }
    }

    private static func prune() {
        for old in backups().dropFirst(keepDays) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    private static func dayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func copy(from src: URL, to dst: URL) -> Bool {
        var source: OpaquePointer?
        var target: OpaquePointer?
        guard sqlite3_open_v2(src.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(source); return false
        }
        defer { sqlite3_close(source) }
        guard sqlite3_open(dst.path, &target) == SQLITE_OK else {
            sqlite3_close(target); return false
        }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", source, "main") else { return false }
        let step = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        // The copy inherits WAL mode; switch to a self-contained single file
        // so restoring is just copying it back.
        sqlite3_exec(target, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        return step == SQLITE_DONE
    }
}
