import Foundation
import SwiftData

// MARK: - Stored types
//
// SwiftData @Model classes mirroring the value-type models. Stored classes
// keep raw string scalars instead of enums so that CloudKit-compatible defaults
// and forward-compat decoding are trivial.
//
// CloudKit compatibility rules followed:
//   - No @Attribute(.unique)
//   - All properties have default values (or are optional)
//   - No required relationships
//
// `init()` is the parameterless initializer required by SwiftData; convenience
// inits take the value-type for one-shot construction during migration.

@Model
public final class StoredWorkSession {
    public var id: UUID = UUID()
    public var startTime: Date = Date()
    public var durationMinutes: Double = 0
    public var typeRaw: String = WorkSession.SessionType.work.rawValue
    public var label: String? = nil
    public var breakKindsRaw: [String] = []

    public init() {}

    public convenience init(value: WorkSession) {
        self.init()
        self.id = value.id
        self.startTime = value.startTime
        self.durationMinutes = value.durationMinutes
        self.typeRaw = value.type.rawValue
        self.label = value.label
        self.breakKindsRaw = value.breakKinds?.map(\.rawValue) ?? []
    }

    public var type: WorkSession.SessionType {
        get { WorkSession.SessionType(rawValue: typeRaw) ?? .work }
        set { typeRaw = newValue.rawValue }
    }

    public var breakKinds: [BreakKind]? {
        get { breakKindsRaw.isEmpty ? nil : breakKindsRaw.compactMap { BreakKind(rawValue: $0) } }
        set { breakKindsRaw = newValue?.map(\.rawValue) ?? [] }
    }

    public var asValue: WorkSession {
        WorkSession(id: id, startTime: startTime, durationMinutes: durationMinutes,
                    type: type, label: label, breakKinds: breakKinds)
    }
}

@Model
public final class StoredProblem {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var title: String = ""
    public var domainRaw: String = ProblemDomain.quant.rawValue
    public var categories: [String] = []
    public var difficultyRaw: String = ProblemDifficulty.medium.rawValue
    public var needsReview: Bool = false
    public var confidenceRaw: String = Confidence.solid.rawValue
    public var source: String = ""
    public var notes: String = ""
    public var urlString: String = ""
    public var solveMinutes: Int? = nil

    public init() {}

    public convenience init(value: ProblemEntry) {
        self.init()
        self.id = value.id
        self.date = value.date
        self.title = value.title
        self.domainRaw = value.domain.rawValue
        self.categories = value.categories
        self.difficultyRaw = value.difficulty.rawValue
        self.needsReview = value.needsReview
        self.confidenceRaw = value.confidence.rawValue
        self.source = value.source
        self.notes = value.notes
        self.urlString = value.url
        self.solveMinutes = value.solveMinutes
    }

    public var domain: ProblemDomain {
        get { ProblemDomain(rawValue: domainRaw) ?? .quant }
        set { domainRaw = newValue.rawValue }
    }

    public var difficulty: ProblemDifficulty {
        get { ProblemDifficulty(rawValue: difficultyRaw) ?? .medium }
        set { difficultyRaw = newValue.rawValue }
    }

    public var confidence: Confidence {
        get { Confidence(rawValue: confidenceRaw) ?? .solid }
        set { confidenceRaw = newValue.rawValue }
    }

    public var asValue: ProblemEntry {
        ProblemEntry(id: id, date: date, title: title, domain: domain,
                     categories: categories, difficulty: difficulty,
                     source: source, needsReview: needsReview, confidence: confidence,
                     notes: notes, url: urlString, solveMinutes: solveMinutes)
    }
}

@Model
public final class StoredHomework {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var title: String = ""
    public var source: String = ""
    public var difficultyRaw: String = ProblemDifficulty.medium.rawValue
    public var confidenceRaw: String = Confidence.solid.rawValue
    public var usedAI: Bool = false
    public var notes: String = ""
    public var urlString: String = ""
    /// Optional link back to a catalog problem (e.g. Stat 110 HW2 #3).
    /// Nil for manually-entered homework. See `Stat110Catalog`.
    public var catalogID: String? = nil
    /// Mirrors ProblemEntry.needsReview — drives the homework review queue.
    public var needsReview: Bool = false
    /// User-set "review again on this date". Overrides the confidence-driven
    /// schedule (`reviewDueDate`) computed in HomeworkProblem.
    public var reviewOverrideDate: Date? = nil

    public init() {}

    public convenience init(value: HomeworkProblem) {
        self.init()
        self.id = value.id
        self.date = value.date
        self.title = value.title
        self.source = value.source
        self.difficultyRaw = value.difficulty.rawValue
        self.confidenceRaw = value.confidence.rawValue
        self.usedAI = value.usedAI
        self.notes = value.notes
        self.urlString = value.url
        self.catalogID = value.catalogID
        self.needsReview = value.needsReview
        self.reviewOverrideDate = value.reviewOverrideDate
    }

    public var difficulty: ProblemDifficulty {
        get { ProblemDifficulty(rawValue: difficultyRaw) ?? .medium }
        set { difficultyRaw = newValue.rawValue }
    }

    public var confidence: Confidence {
        get { Confidence(rawValue: confidenceRaw) ?? .solid }
        set { confidenceRaw = newValue.rawValue }
    }

    public var asValue: HomeworkProblem {
        HomeworkProblem(id: id, date: date, title: title, source: source,
                        difficulty: difficulty, confidence: confidence,
                        usedAI: usedAI, notes: notes, url: urlString,
                        catalogID: catalogID, needsReview: needsReview,
                        reviewOverrideDate: reviewOverrideDate)
    }
}

@Model
public final class StoredDayRecord {
    public var id: UUID = UUID()
    public var calendarDay: Date = Date()
    public var dayStart: Date? = nil
    public var dayEnd: Date? = nil

    public init() {}

    public convenience init(value: DayRecord) {
        self.init()
        self.id = value.id
        self.calendarDay = value.calendarDay
        self.dayStart = value.dayStart
        self.dayEnd = value.dayEnd
    }

    public var asValue: DayRecord {
        DayRecord(id: id, calendarDay: calendarDay, dayStart: dayStart, dayEnd: dayEnd)
    }
}

@Model
public final class StoredScratchItem {
    public var id: UUID = UUID()
    public var text: String = ""
    public var isChecked: Bool = false
    public var order: Int = 0

    public init() {}

    public convenience init(value: ScratchItem, order: Int = 0) {
        self.init()
        self.id = value.id
        self.text = value.text
        self.isChecked = value.isChecked
        self.order = order
    }

    public var asValue: ScratchItem {
        ScratchItem(id: id, text: text, isChecked: isChecked)
    }
}

/// Shared live-timer state. There's at most one of these — both Mac and iPad
/// read + write the same record so they can mirror the running timer.
///
/// "Anchored time" model: when the timer is running, `endTime` is when it
/// would naturally complete; remaining is computed from wall clock.
/// When paused, `remainingSeconds` holds the value at pause moment.
/// `updatedAt` is the conflict-resolution tiebreaker (last write wins).
@Model
public final class StoredTimerState {
    /// Single owner-scoped ID so SwiftData treats it as one record.
    public var id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    /// "idle" | "work" | "breakPhase"
    public var phaseRaw: String = "idle"
    public var isRunning: Bool = false
    /// Wall-clock moment the running timer would complete. Nil when paused/idle.
    public var endTime: Date? = nil
    /// Remaining seconds when paused. Ignored when running.
    public var remainingSeconds: Double = 0
    public var totalSeconds: Double = 0
    public var label: String = ""
    public var breakKindsRaw: [String] = []
    /// Wall-clock moment the timer originally started (kept as session-start for save).
    public var startTime: Date? = nil
    public var updatedAt: Date = Date()
    /// Which device authored the most recent update — used to avoid feedback loops.
    public var deviceID: String = ""
    /// Monotonic Lamport-style counter. Each push does `version = max(local, remote) + 1`.
    /// Receivers ignore states with `version <= lastSeenVersion`, giving us a clear
    /// causal "this is newer" signal that doesn't depend on device clocks agreeing.
    /// Tiebreak on equal versions: larger deviceID wins (string comparison).
    public var version: Int = 0

    public init() {}

    public enum Phase: String, Sendable {
        case idle, work, breakPhase
    }

    public var phase: Phase {
        get { Phase(rawValue: phaseRaw) ?? .idle }
        set { phaseRaw = newValue.rawValue }
    }

    public var breakKinds: [BreakKind] {
        get { breakKindsRaw.compactMap { BreakKind(rawValue: $0) } }
        set { breakKindsRaw = newValue.map(\.rawValue) }
    }

    /// Remaining seconds, computed from anchor if running.
    public var liveRemaining: TimeInterval {
        if isRunning, let end = endTime {
            return max(0, end.timeIntervalSinceNow)
        }
        return max(0, remainingSeconds)
    }
}

// MARK: - Schema

public enum FocusSchema {
    public static let allModels: [any PersistentModel.Type] = [
        StoredWorkSession.self,
        StoredProblem.self,
        StoredHomework.self,
        StoredDayRecord.self,
        StoredScratchItem.self,
        StoredTimerState.self,
    ]
}
