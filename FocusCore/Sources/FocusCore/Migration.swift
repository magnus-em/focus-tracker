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

    /// Cleans duplicate `StoredWorkSession` rows. Two rows are considered
    /// duplicates if they share (type, label, minute-rounded duration)
    /// AND start within ±3 seconds of each other. Keeps the row with the
    /// smallest UUID so both Mac and iPad converge on the same survivor.
    ///
    /// More lenient than the prior "round to whole seconds" approach,
    /// which missed pairs whose timestamps straddled a second boundary
    /// (e.g. Mac at 15:42:35.998, iPad at 15:42:36.001).
    ///
    /// Cheap to run; safe to call on every launch.
    @discardableResult
    public static func dedupeWorkSessions(container: ModelContainer) -> Int {
        let ctx = ModelContext(container)
        let all = (try? ctx.fetch(FetchDescriptor<StoredWorkSession>())) ?? []
        let sorted = all.sorted { $0.startTime < $1.startTime }
        var toDelete: Set<UUID> = []
        var i = 0
        while i < sorted.count {
            if toDelete.contains(sorted[i].id) { i += 1; continue }
            let anchor = sorted[i]
            var cluster: [StoredWorkSession] = [anchor]
            var j = i + 1
            while j < sorted.count {
                let cand = sorted[j]
                if cand.startTime.timeIntervalSince(anchor.startTime) > 3 { break }
                let sameType  = cand.typeRaw == anchor.typeRaw
                let sameLabel = (cand.label ?? "") == (anchor.label ?? "")
                let sameDur   = Int(cand.durationMinutes.rounded()) == Int(anchor.durationMinutes.rounded())
                if sameType && sameLabel && sameDur && !toDelete.contains(cand.id) {
                    cluster.append(cand)
                }
                j += 1
            }
            if cluster.count > 1 {
                let survivor = cluster.min(by: { $0.id.uuidString < $1.id.uuidString })!
                for r in cluster where r.id != survivor.id {
                    toDelete.insert(r.id)
                }
            }
            i += 1
        }
        var removed = 0
        for row in all where toDelete.contains(row.id) {
            ctx.delete(row)
            removed += 1
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
