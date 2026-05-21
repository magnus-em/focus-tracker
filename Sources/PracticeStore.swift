import Foundation
import FocusCore
import SwiftData
import SwiftUI
import Combine

/// Engine for "Practice Mode" — the Stat-110-style problem pacing tracker.
///
/// One instance per Mac process. Holds a single active attempt at a time;
/// completed/abandoned attempts are persisted to SwiftData and the engine
/// returns to idle. The view binds to `phase` / `elapsedSeconds` /
/// `hintsPeeked` to render.
///
/// On every `solved` or `stuck` finish, this also upserts a
/// `HomeworkProblem` row keyed by `catalogID` so the homework list
/// reflects the latest attempt's confidence/difficulty/needsReview. The
/// per-attempt history stays in `StoredDrillAttempt` (kept as the
/// SwiftData class name to avoid a CloudKit schema migration).
@MainActor
final class PracticeStore: ObservableObject {

    // MARK: - Zone definitions

    /// The three zones from the framework. Boundaries are minute-marks of
    /// active (paused-excluded) time on the current attempt.
    enum Zone {
        /// 0–15 min: productive struggle. Stay quiet.
        case green
        /// 15–20 min: approaching wall. Soft check-in.
        case yellow
        /// 20+ min: wall reached. Offer the three escape valves.
        case red

        static let yellowAt: TimeInterval = 15 * 60
        static let redAt: TimeInterval = 20 * 60

        var label: String {
            switch self {
            case .green:  return "Productive struggle"
            case .yellow: return "Approaching the wall"
            case .red:    return "Wall reached — time to pivot"
            }
        }

        var color: Color {
            switch self {
            case .green:  return Color(red: 0.40, green: 0.78, blue: 0.45)
            case .yellow: return Color(red: 0.95, green: 0.74, blue: 0.30)
            case .red:    return Color(red: 0.96, green: 0.36, blue: 0.36)
            }
        }

        var coachingLine: String {
            switch self {
            case .green:
                return "Get a feel for the structure. Where are the symmetries?"
            case .yellow:
                return "Are you actively writing, or staring? If staring, take a nudge."
            case .red:
                return "Pivot. Peek one line, run a Monte Carlo, or log & move on. All valid."
            }
        }
    }

    // MARK: - Active attempt state

    /// True iff there's a practice session currently running (engine timer ticking).
    @Published private(set) var isActive: Bool = false
    /// True iff the active session is paused.
    @Published private(set) var isPaused: Bool = false
    /// Active seconds elapsed on the current attempt (excludes pauses).
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    /// Number of solution-line peeks on the current attempt.
    @Published private(set) var hintsPeeked: Int = 0
    /// Whether the user pivoted to Monte Carlo on this attempt.
    @Published private(set) var monteCarloUsed: Bool = false
    /// Catalog problem currently being practiced (if any).
    @Published private(set) var activeProblem: Stat110Problem?

    /// All completed attempts, newest-first. For the analytics panel.
    @Published private(set) var attempts: [StoredDrillAttempt] = []

    // MARK: - Computed

    var zone: Zone {
        if elapsedSeconds >= Zone.redAt { return .red }
        if elapsedSeconds >= Zone.yellowAt { return .yellow }
        return .green
    }

    var burstCount: Int {
        let gapThreshold: TimeInterval = 30 * 60
        var count = 0
        var lastEnd: Date? = nil
        for a in attempts {
            guard let end = a.endTime else { continue }
            if let last = lastEnd, last.timeIntervalSince(end) > gapThreshold { break }
            count += 1
            lastEnd = a.startTime
        }
        return count
    }

    var shouldSuggestBreak: Bool { burstCount >= 4 }

    // MARK: - Plumbing

    private let context: ModelContext
    private weak var homeworkStore: HomeworkStore?
    private var ticker: AnyCancellable?
    private var resumeTime: Date?
    private var accumulatedBeforePause: TimeInterval = 0

    init(container: ModelContainer, homeworkStore: HomeworkStore? = nil) {
        self.context = ModelContext(container)
        self.homeworkStore = homeworkStore
        refresh()
    }

    /// Wire up the HomeworkStore after init. The App's init constructs
    /// both stores at the same time so we can't pass it inline.
    func attach(homeworkStore: HomeworkStore) {
        self.homeworkStore = homeworkStore
    }

    private func refresh() {
        var descriptor = FetchDescriptor<StoredDrillAttempt>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        attempts = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Controls

    func start(problem: Stat110Problem) {
        guard !isActive else { return }
        activeProblem = problem
        elapsedSeconds = 0
        accumulatedBeforePause = 0
        resumeTime = Date()
        hintsPeeked = 0
        monteCarloUsed = false
        isPaused = false
        isActive = true
        startTicker()
    }

    func pause() {
        guard isActive, !isPaused, let resume = resumeTime else { return }
        accumulatedBeforePause += Date().timeIntervalSince(resume)
        elapsedSeconds = accumulatedBeforePause
        resumeTime = nil
        isPaused = true
        ticker?.cancel(); ticker = nil
    }

    func resume() {
        guard isActive, isPaused else { return }
        resumeTime = Date()
        isPaused = false
        startTicker()
    }

    private func startTicker() {
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if let r = self.resumeTime {
                    self.elapsedSeconds = self.accumulatedBeforePause
                        + Date().timeIntervalSince(r)
                }
            }
    }

    func peekHint() {
        guard isActive else { return }
        hintsPeeked += 1
    }

    func markMonteCarlo() {
        guard isActive else { return }
        monteCarloUsed = true
    }

    // MARK: - Finish (three outcome paths, each syncing to homework when relevant)

    /// Solved — log attempt + upsert homework row with chosen confidence.
    /// needsReview is left to the caller; default in the UI is true for
    /// Shaky/Struggled, false for Got-it.
    func finishSolved(confidence: Confidence,
                      difficulty: ProblemDifficulty,
                      needsReview: Bool,
                      notes: String) {
        guard isActive else { return }
        let elapsed = freezeElapsed()
        persistAttempt(outcome: .solved, notes: notes,
                       confidenceInt: intFor(confidence),
                       elapsed: elapsed)
        if let p = activeProblem {
            homeworkStore?.upsertFromPractice(
                catalogID: p.id,
                title: p.title,
                source: p.sourceLabel,
                difficulty: difficulty,
                confidence: confidence,
                needsReview: needsReview,
                notes: notes,
                url: Stat110Catalog.problemSet(number: p.setNumber)?.pdfURL ?? "",
                solveMinutes: Int(elapsed / 60)
            )
        }
        resetActive()
        refresh()
    }

    /// Stuck — used hints/MC and still couldn't crack it. Mark homework
    /// row as struggled + needsReview so it bubbles up tomorrow.
    func finishStuck(notes: String) {
        guard isActive else { return }
        let elapsed = freezeElapsed()
        persistAttempt(outcome: .stuck, notes: notes,
                       confidenceInt: intFor(.struggled), elapsed: elapsed)
        if let p = activeProblem {
            homeworkStore?.upsertFromPractice(
                catalogID: p.id,
                title: p.title,
                source: p.sourceLabel,
                difficulty: .hard,
                confidence: .struggled,
                needsReview: true,
                notes: notes,
                url: Stat110Catalog.problemSet(number: p.setNumber)?.pdfURL ?? "",
                solveMinutes: Int(elapsed / 60)
            )
        }
        resetActive()
        refresh()
    }

    /// Skipped — bailed early without engaging. Log attempt only; don't
    /// pollute the homework list with this.
    func finishSkipped(notes: String) {
        guard isActive else { return }
        let elapsed = freezeElapsed()
        persistAttempt(outcome: .skipped, notes: notes,
                       confidenceInt: 0, elapsed: elapsed)
        resetActive()
        refresh()
    }

    private func freezeElapsed() -> TimeInterval {
        if !isPaused, let resume = resumeTime {
            accumulatedBeforePause += Date().timeIntervalSince(resume)
        }
        return accumulatedBeforePause
    }

    @discardableResult
    private func persistAttempt(outcome: DrillOutcome,
                                notes: String,
                                confidenceInt: Int,
                                elapsed: TimeInterval) -> StoredDrillAttempt {
        let attempt = StoredDrillAttempt()
        attempt.catalogID = activeProblem?.id
        attempt.title = activeProblem?.title ?? ""
        attempt.source = activeProblem?.sourceLabel ?? ""
        attempt.startTime = Date().addingTimeInterval(-elapsed)
        attempt.endTime = Date()
        attempt.activeSeconds = elapsed
        attempt.hintsPeeked = hintsPeeked
        attempt.monteCarloUsed = monteCarloUsed
        attempt.outcome = outcome
        attempt.confidence = confidenceInt
        attempt.notes = notes
        context.insert(attempt)
        try? context.save()
        return attempt
    }

    /// Map Confidence → stored 1-5 int (keeps StoredDrillAttempt's int field
    /// usable; no schema migration). 5 solid · 3 shaky · 1 struggled.
    private func intFor(_ c: Confidence) -> Int {
        switch c {
        case .solid: return 5
        case .shaky: return 3
        case .struggled: return 1
        }
    }

    func discardActive() {
        guard isActive else { return }
        resetActive()
    }

    // MARK: - Catalog navigation
    //
    // When the user is in "read + flip through" mode (not actually working
    // problems through in the app — they have an iPad for that), the
    // prev/next arrows in the active view should change the active problem
    // without logging anything. Each problem gets its own fresh timer.

    /// Flat list of every catalog problem in display order. Cache it
    /// once instead of recomputing on every keystroke.
    private static let flatCatalog: [Stat110Problem] = {
        Stat110Catalog.all.flatMap { $0.problems }
    }()

    /// Move to the next problem in the catalog (across set boundaries).
    /// Discards any in-progress timer; nothing is logged. If we're already
    /// at the last problem, no-op.
    func navigateNext() {
        guard let current = activeProblem,
              let idx = Self.flatCatalog.firstIndex(where: { $0.id == current.id }),
              idx + 1 < Self.flatCatalog.count
        else { return }
        let next = Self.flatCatalog[idx + 1]
        resetActive()
        start(problem: next)
    }

    /// Move to the previous problem. Same semantics as navigateNext.
    func navigatePrevious() {
        guard let current = activeProblem,
              let idx = Self.flatCatalog.firstIndex(where: { $0.id == current.id }),
              idx > 0
        else { return }
        let prev = Self.flatCatalog[idx - 1]
        resetActive()
        start(problem: prev)
    }

    /// Whether prev/next arrows should be enabled.
    var canNavigatePrevious: Bool {
        guard let current = activeProblem,
              let idx = Self.flatCatalog.firstIndex(where: { $0.id == current.id })
        else { return false }
        return idx > 0
    }

    var canNavigateNext: Bool {
        guard let current = activeProblem,
              let idx = Self.flatCatalog.firstIndex(where: { $0.id == current.id })
        else { return false }
        return idx + 1 < Self.flatCatalog.count
    }

    private func resetActive() {
        ticker?.cancel(); ticker = nil
        isActive = false
        isPaused = false
        elapsedSeconds = 0
        accumulatedBeforePause = 0
        resumeTime = nil
        hintsPeeked = 0
        monteCarloUsed = false
        activeProblem = nil
    }

    // MARK: - Analytics

    var sessionsToday: Int {
        let cal = Calendar.current
        return attempts.filter { cal.isDateInToday($0.startTime) }.count
    }

    var solveRateToday: Double {
        let today = attempts.filter { Calendar.current.isDateInToday($0.startTime) }
        guard !today.isEmpty else { return 0 }
        let solved = today.filter { $0.outcome == .solved }.count
        return Double(solved) / Double(today.count)
    }

    var minutesToday: Double {
        let cal = Calendar.current
        return attempts
            .filter { cal.isDateInToday($0.startTime) }
            .reduce(0.0) { $0 + $1.activeSeconds / 60.0 }
    }
}
