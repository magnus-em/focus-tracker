import Foundation
import SwiftData

/// One-shot migration from the legacy JSON-file-based persistence to SwiftData.
/// Reads the JSON files in the given directory (typically `~/Library/Application Support/Focus/`),
/// inserts rows into the supplied SwiftData container, then renames each JSON file
/// to `<name>.pre-swiftdata.bak` so it's preserved but no longer the source of truth.
///
/// Idempotent: subsequent calls do nothing once the migration marker is set.
public enum FocusMigration {
    private static let markerKey = "focusCore.jsonToSwiftData.migrated"

    public static var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: markerKey)
    }

    /// Cleans duplicate `StoredWorkSession` rows. **Strict match**: same
    /// whole-second `startTime`, same `type`, same `label`, AND same
    /// duration to 0.01 minutes (~0.6 sec of work-time). Keeps the row
    /// with the smallest UUID so Mac and iPad converge on the same row.
    ///
    /// History note: I tried loosening this to a fuzzy ±3s + minute-rounded
    /// duration match and it deleted a legitimate session whose duration
    /// happened to round into a neighbour's bucket within a 3-second
    /// window. Kept this version strict so it only fires on actual
    /// byte-identical duplicates — the case it was originally designed
    /// for (Mac and iPad both inserting the same broadcast-driven event).
    @discardableResult
    public static func dedupeWorkSessions(container: ModelContainer) -> Int {
        let ctx = ModelContext(container)
        let all = (try? ctx.fetch(FetchDescriptor<StoredWorkSession>())) ?? []
        var seen: [String: StoredWorkSession] = [:]
        var removed = 0
        for row in all {
            let secKey = Int(row.startTime.timeIntervalSince1970)
            let durKey = Int((row.durationMinutes * 100).rounded())
            let key = "\(secKey)|\(row.typeRaw)|\(row.label ?? "")|\(durKey)"
            if let kept = seen[key] {
                if row.id.uuidString < kept.id.uuidString {
                    ctx.delete(kept)
                    seen[key] = row
                } else {
                    ctx.delete(row)
                }
                removed += 1
            } else {
                seen[key] = row
            }
        }
        if removed > 0 { try? ctx.save() }
        return removed
    }

    public struct Result {
        public var sessions: Int = 0
        public var problems: Int = 0
        public var homework: Int = 0
        public var dayRecords: Int = 0
        public var scratch: Int = 0
        public var alreadyMigrated: Bool = false
    }

    public static func migrateIfNeeded(container: ModelContainer, appSupportDir: URL) -> Result {
        var result = Result()
        if hasMigrated {
            result.alreadyMigrated = true
            return result
        }

        let context = ModelContext(container)

        result.sessions    = migrate([WorkSession].self, file: "sessions.json", in: appSupportDir, into: context) { StoredWorkSession(value: $0) }
        result.problems    = migrate([ProblemEntry].self, file: "problems.json", in: appSupportDir, into: context) { StoredProblem(value: $0) }
        result.homework    = migrate([HomeworkProblem].self, file: "homework.json", in: appSupportDir, into: context) { StoredHomework(value: $0) }
        result.dayRecords  = migrate([DayRecord].self, file: "dayrecords.json", in: appSupportDir, into: context) { StoredDayRecord(value: $0) }
        result.scratch     = migrateScratch(in: appSupportDir, into: context)

        try? context.save()
        UserDefaults.standard.set(true, forKey: markerKey)
        return result
    }

    private static func migrate<Value, Stored>(
        _ type: [Value].Type,
        file: String,
        in dir: URL,
        into context: ModelContext,
        wrap: (Value) -> Stored
    ) -> Int where Value: Decodable, Stored: PersistentModel {
        let url = dir.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([Value].self, from: data) else { return 0 }
        for value in decoded {
            context.insert(wrap(value))
        }
        backup(url: url)
        return decoded.count
    }

    private static func migrateScratch(in dir: URL, into context: ModelContext) -> Int {
        let url = dir.appendingPathComponent("scratch.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([ScratchItem].self, from: data) else { return 0 }
        for (i, value) in decoded.enumerated() {
            context.insert(StoredScratchItem(value: value, order: i))
        }
        backup(url: url)
        return decoded.count
    }

    private static func backup(url: URL) {
        let backup = url.appendingPathExtension("pre-swiftdata.bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
