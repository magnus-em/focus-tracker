import Foundation
import Combine
import FocusCore
import SwiftData

/// Source of truth for the mastery ladder — where each catalog problem
/// sits on the (familiarized → R1 → R2 → R3 → retained) progression and
/// when its next cold review is due.
///
/// Replaces the older `HomeworkProblem.confidence + needsReview` scheme,
/// which couldn't distinguish "I walked through this with AI yesterday"
/// from "I've passed cold solves at 1d / 3d / 7d and own it."
@MainActor
final class MasteryStore: ObservableObject {
    @Published private(set) var records: [StoredMasteryRecord] = []

    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        refresh()
    }

    private func refresh() {
        var descriptor = FetchDescriptor<StoredMasteryRecord>(
            sortBy: [SortDescriptor(\.lastEvent, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        records = (try? context.fetch(descriptor)) ?? []
    }

    /// Public hook for cross-context invalidation (e.g. after a reset
    /// triggered from PracticeStore's own context).
    func refreshFromExternal() { refresh() }

    // MARK: - Read paths

    func record(for catalogID: String) -> StoredMasteryRecord? {
        records.first { $0.catalogID == catalogID }
    }

    /// Sum of all logged attempt durations for a given catalog problem.
    /// Used to show "total time spent on this problem" on the active view.
    func totalTime(forCatalogID id: String) -> Double {
        let predicate = #Predicate<StoredMasteryAttempt> { $0.catalogID == id }
        var descriptor = FetchDescriptor<StoredMasteryAttempt>(predicate: predicate)
        descriptor.includePendingChanges = true
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Number of logged attempts for a given catalog problem (any mode).
    func attemptCount(forCatalogID id: String) -> Int {
        let predicate = #Predicate<StoredMasteryAttempt> { $0.catalogID == id }
        var descriptor = FetchDescriptor<StoredMasteryAttempt>(predicate: predicate)
        descriptor.includePendingChanges = true
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Most recent attempt date for a problem, or nil if never attempted.
    func lastAttemptDate(forCatalogID id: String) -> Date? {
        attempts(forCatalogID: id, limit: 1).first?.date
    }

    /// Newest-first list of attempts for a problem, optionally capped.
    /// Used by the per-problem history panel.
    func attempts(forCatalogID id: String, limit: Int? = nil) -> [StoredMasteryAttempt] {
        let predicate = #Predicate<StoredMasteryAttempt> { $0.catalogID == id }
        var descriptor = FetchDescriptor<StoredMasteryAttempt>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        if let limit { descriptor.fetchLimit = limit }
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Records whose nextDue ≤ now. Source for the review session queue.
    var dueNow: [StoredMasteryRecord] {
        records.filter { $0.isDue }
    }

    var counts: StageCounts {
        var c = StageCounts()
        for r in records {
            switch r.stage {
            case .familiarized: c.familiarized += 1
            case .r1Passed:     c.r1 += 1
            case .r2Passed:     c.r2 += 1
            case .retained:     c.retained += 1
            case .lapsed:       c.lapsed += 1
            }
        }
        return c
    }

    /// Stratified shuffle: no two consecutive problems on the same topic
    /// if avoidable. Round-robin pulls from per-topic queues, longest
    /// queue first each round, which spreads heavy topics evenly across
    /// the session without ever clustering them.
    func interleavedDueQueue() -> [StoredMasteryRecord] {
        let due = dueNow
        guard due.count > 1 else { return due }

        var byTopic: [String: [StoredMasteryRecord]] = [:]
        for r in due {
            let key = r.topic ?? "Mixed homework"
            byTopic[key, default: []].append(r)
        }
        for k in byTopic.keys { byTopic[k]?.shuffle() }

        var result: [StoredMasteryRecord] = []
        while !byTopic.isEmpty {
            let keys = byTopic.keys.sorted {
                (byTopic[$0]?.count ?? 0) > (byTopic[$1]?.count ?? 0)
            }
            for k in keys {
                if var arr = byTopic[k], !arr.isEmpty {
                    result.append(arr.removeFirst())
                    if arr.isEmpty { byTopic.removeValue(forKey: k) }
                    else { byTopic[k] = arr }
                }
            }
        }
        return result
    }

    /// Mix preview: counts by topic for the current due queue. Used to
    /// show "2 Bayes · 3 conditional · 1 binomial" on the idle screen.
    func dueTopicMix() -> [(topic: String, count: Int)] {
        let due = dueNow
        var counts: [String: Int] = [:]
        for r in due {
            let key = r.topic ?? "Mixed homework"
            counts[key, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }
                     .sorted { $0.count > $1.count }
    }

    // MARK: - Write paths (ladder transitions)

    /// Review attempt — solved.
    ///
    /// Ladder rules (per user spec):
    ///   • Untouched problem (no existing record) → anchor at R1 either way.
    ///   • R1 + AI or solo → R2.
    ///   • R2 → R3 requires solo (AI holds at R2).
    ///   • R3 → Retained requires solo (AI holds at R3).
    ///   • Lapsed → R1 either way (treat as a re-entry).
    ///   • Retained stays retained.
    ///
    /// The idea: AI gets you off the bottom rung, but the top of the ladder
    /// (R3 / Retained) demands cold solo solves.
    func recordReviewPass(problem: Stat110Problem,
                          usedAI: Bool,
                          durationSeconds: Double,
                          notes: String) {
        let existing = records.first(where: { $0.catalogID == problem.id })
        let isFresh = (existing == nil)
        let record = upsertRecord(problem: problem)
        let cal = Calendar.current
        let now = Date()

        if isFresh {
            record.stage = .familiarized
            record.nextDue = cal.date(byAdding: .hour, value: 24, to: now)
        } else if usedAI {
            switch record.stage {
            case .familiarized:
                record.stage = .r1Passed
                record.nextDue = cal.date(byAdding: .day, value: record.r2IntervalDays, to: now)
            case .lapsed:
                record.stage = .familiarized
                record.nextDue = cal.date(byAdding: .hour, value: 24, to: now)
            case .r1Passed, .r2Passed, .retained:
                // Holds the rung. nextDue intentionally unchanged so the
                // cold solo review is still owed.
                break
            }
        } else {
            switch record.stage {
            case .familiarized:
                record.stage = .r1Passed
                record.nextDue = cal.date(byAdding: .day, value: record.r2IntervalDays, to: now)
            case .r1Passed:
                record.stage = .r2Passed
                record.nextDue = cal.date(byAdding: .day, value: 7, to: now)
            case .r2Passed:
                record.stage = .retained
                record.nextDue = nil
            case .retained:
                break
            case .lapsed:
                record.stage = .familiarized
                record.nextDue = cal.date(byAdding: .hour, value: 24, to: now)
            }
        }
        record.lastEvent = now
        record.coldPassCount += 1

        appendAttempt(catalogID: problem.id,
                      mode: usedAI ? .familiarization : .review,
                      outcome: usedAI ? .aiAssist : .coldPass,
                      durationSeconds: durationSeconds,
                      notes: notes,
                      feltEasy: nil)
        save()
    }

    /// Manual fast-forward: declare a problem fully retained without
    /// going through the R1 / R2 ladder. Use when the user already
    /// knows the material cold from an external source (e.g. spent a
    /// month on it last semester) and just wants it off the queue.
    /// Logs a coldPass attempt for the audit trail.
    func skipToRetained(problem: Stat110Problem,
                        durationSeconds: Double = 0,
                        notes: String = "") {
        let record = upsertRecord(problem: problem)
        record.stage = .retained
        record.nextDue = nil
        record.lastEvent = Date()
        record.coldPassCount += 1
        appendAttempt(catalogID: problem.id,
                      mode: .review,
                      outcome: .coldPass,
                      durationSeconds: durationSeconds,
                      notes: notes.isEmpty ? "Marked retained directly" : notes,
                      feltEasy: true)
        save()
    }

    /// Review attempt — couldn't solve.
    ///
    /// Stage never drops. If there's an existing record, lastEvent is
    /// refreshed and nextDue is pushed out 24h so the same problem doesn't
    /// loop back into tomorrow's queue. If the problem isn't on the ladder
    /// yet, we DO NOT create a record — couldn't-solve doesn't count as
    /// exposure. The attempt is still logged for the audit trail.
    func recordReviewFail(problem: Stat110Problem,
                          durationSeconds: Double,
                          notes: String) {
        if let record = records.first(where: { $0.catalogID == problem.id }) {
            let cal = Calendar.current
            let now = Date()
            record.lastEvent = now
            record.coldFailCount += 1
            if record.nextDue != nil {
                record.nextDue = cal.date(byAdding: .hour, value: 24, to: now)
            }
        }
        appendAttempt(catalogID: problem.id,
                      mode: .review,
                      outcome: .coldFail,
                      durationSeconds: durationSeconds,
                      notes: notes,
                      feltEasy: nil)
        save()
    }

    /// Manual stage override. Used by the per-problem ladder picker so the
    /// user can park a problem exactly where they want it without playing
    /// the outcome-button shell game. `nextDue` is recomputed from the
    /// stage's canonical interval unless explicitly passed.
    func setStage(problem: Stat110Problem,
                  stage: MasteryStage,
                  nextDueOverride: Date? = nil) {
        let record = upsertRecord(problem: problem)
        let cal = Calendar.current
        let now = Date()
        record.stage = stage
        record.lastEvent = now
        if let due = nextDueOverride {
            record.nextDue = due
        } else {
            switch stage {
            case .familiarized:
                record.nextDue = cal.date(byAdding: .hour, value: 24, to: now)
            case .r1Passed:
                record.nextDue = cal.date(byAdding: .day, value: record.r2IntervalDays, to: now)
            case .r2Passed:
                record.nextDue = cal.date(byAdding: .day, value: 7, to: now)
            case .retained, .lapsed:
                record.nextDue = nil
            }
        }
        appendAttempt(catalogID: problem.id,
                      mode: .review,
                      outcome: .skipped,
                      durationSeconds: 0,
                      notes: "Manual stage set to \(stage.rawValue)",
                      feltEasy: nil)
        save()
    }

    /// Remove a problem from the ladder entirely. Wipes the StoredMasteryRecord
    /// (and its summary counters); per-attempt log rows are preserved so the
    /// user can still see they touched it in the past.
    func resetLadder(problem: Stat110Problem) {
        guard let existing = records.first(where: { $0.catalogID == problem.id }) else { return }
        context.delete(existing)
        save()
    }

    func clearAll() {
        let attemptDescriptor = FetchDescriptor<StoredMasteryAttempt>()
        if let rows = try? context.fetch(attemptDescriptor) {
            for r in rows { context.delete(r) }
        }
        let recordDescriptor = FetchDescriptor<StoredMasteryRecord>()
        if let rows = try? context.fetch(recordDescriptor) {
            for r in rows { context.delete(r) }
        }
        save()
    }

    // MARK: - Internals

    private func upsertRecord(problem: Stat110Problem) -> StoredMasteryRecord {
        if let existing = records.first(where: { $0.catalogID == problem.id }) {
            return existing
        }
        let record = StoredMasteryRecord()
        record.catalogID = problem.id
        record.problemTitle = problem.title
        record.sourceLabel = problem.sourceLabel
        record.topic = problem.topic
        record.setNumber = problem.setNumber
        context.insert(record)
        return record
    }

    private func appendAttempt(catalogID: String,
                               mode: MasteryAttemptMode,
                               outcome: MasteryAttemptOutcome,
                               durationSeconds: Double,
                               notes: String,
                               feltEasy: Bool?) {
        let a = StoredMasteryAttempt()
        a.catalogID = catalogID
        a.date = Date()
        a.mode = mode
        a.outcome = outcome
        a.durationSeconds = durationSeconds
        a.notes = notes
        a.feltEasy = feltEasy
        context.insert(a)
    }

    private func save() {
        try? context.save()
        refresh()
    }
}

struct StageCounts {
    var familiarized: Int = 0
    var r1: Int = 0
    var r2: Int = 0
    var retained: Int = 0
    var lapsed: Int = 0

    /// Records sitting in the active ladder (not retained, not lapsed,
    /// not yet finished familiarization).
    var inFlight: Int { familiarized + r1 + r2 }
}
