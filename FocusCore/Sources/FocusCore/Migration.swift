import Foundation
import SwiftData
#if canImport(SQLite3)
import SQLite3
#endif

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

    /// Recover SwiftData rows that exist locally but never got CloudKit
    /// metadata (so they're invisible to NSPersistentCloudKit's export
    /// scheduler and won't sync to peers). This can happen when:
    ///   - CloudKit setup was failing at the moment of insert (partial
    ///     failures during a schema-migration window).
    ///   - A row was inserted via raw SQL bypassing the SwiftData API.
    ///
    /// Recovery strategy: for each orphan, deep-copy its fields into a
    /// brand-new entity (fresh UUID), insert via `context.insert`, save,
    /// then delete the orphan. The fresh insert flows through SwiftData's
    /// transaction journal which NSPersistentCloudKit watches — the row
    /// gets CK metadata and is exported on the next sync cycle.
    ///
    /// Strict dedup then collapses any byte-identical CK-imported version
    /// of the same logical session if/when it arrives from a peer.
    ///
    /// Returns the number of rows recovered.
    @discardableResult
    public static func recoverOrphanSessions(container: ModelContainer) -> Int {
        // We can't ask SwiftData "do you have CloudKit metadata for this
        // row" because that's NSPersistentCloudKit-internal. But we CAN
        // detect orphans by querying the underlying SQLite store for rows
        // in the work-session table that lack a corresponding entry in
        // ANSCKRECORDMETADATA — that's exactly the symptom of the bug.
        guard let storeURL = container.configurations.first?.url else { return 0 }
        let orphanIDs = orphanWorkSessionUUIDs(storeURL: storeURL)
        guard !orphanIDs.isEmpty else { return 0 }

        let ctx = ModelContext(container)
        guard let all = try? ctx.fetch(FetchDescriptor<StoredWorkSession>()) else { return 0 }
        var recovered = 0
        for row in all where orphanIDs.contains(row.id) {
            let snapshot = row.asValue
            // Insert a fresh copy first (new UUID) so we never have a
            // moment where the data is missing. Then delete the orphan.
            let fresh = StoredWorkSession(value: WorkSession(
                startTime: snapshot.startTime,
                durationMinutes: snapshot.durationMinutes,
                type: snapshot.type,
                label: snapshot.label,
                breakKinds: snapshot.breakKinds
            ))
            ctx.insert(fresh)
            ctx.delete(row)
            recovered += 1
        }
        try? ctx.save()
        return recovered
    }

    /// Raw SQLite query — finds work-session UUIDs that have no
    /// corresponding ANSCKRECORDMETADATA row (i.e. NSPersistentCloudKit
    /// doesn't know they exist).
    private static func orphanWorkSessionUUIDs(storeURL: URL) -> Set<UUID> {
        var ids: Set<UUID> = []
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else { return [] }
        defer { sqlite3_close(db) }

        // Joining on s.Z_ENT (not a hard-coded entity number) keeps this
        // correct when SwiftData renumbers entities as models are added.
        let sql = """
        SELECT hex(s.ZID)
        FROM ZSTOREDWORKSESSION s
        LEFT JOIN ANSCKRECORDMETADATA rm
          ON rm.ZENTITYPK = s.Z_PK AND rm.ZENTITYID = s.Z_ENT
        WHERE rm.Z_PK IS NULL;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cStr = sqlite3_column_text(stmt, 0) else { continue }
            let hex = String(cString: cStr)
            if let uuid = uuidFromHex(hex) { ids.insert(uuid) }
        }
        return ids
    }

    private static func uuidFromHex(_ hex: String) -> UUID? {
        guard hex.count == 32 else { return nil }
        var bytes = [UInt8]()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15]))
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
