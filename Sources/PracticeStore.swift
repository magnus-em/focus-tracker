import Foundation
import FocusCore
import SwiftData
import SwiftUI
import Combine

/// Two distinct ways a practice attempt can be entered. The mode is set
/// when the attempt starts and drives which finish methods are available
/// and what the UI surfaces (AI/hints/answer reveal in familiarization;
/// strict "got it cold / didn't" in review).
enum PracticeMode: String, Codable {
    /// First exposure. AI assist, hints, answer reveal allowed. Always
    /// results in scheduling R1 in 24h regardless of how it ended.
    case familiarization
    /// Cold attempt at a scheduled review rung. No inline help; outcomes
    /// are pass / fail / skip. Advances or drops the ladder rung.
    case review
}

/// Snapshot of an in-progress attempt — captured to UserDefaults so the
/// user can close the window, quit the app, even reboot, and come back
/// to the same problem at the same elapsed time. On restore the attempt
/// always comes back paused: the wall clock advanced while the app was
/// gone but the user wasn't actually working, so we don't credit that
/// time. They click Resume to keep going.
private struct PracticeSnapshot: Codable {
    let catalogID: String
    let mode: PracticeMode
    /// Total active seconds when the snapshot was taken.
    let elapsedSeconds: TimeInterval
    let hintsPeeked: Int
    let monteCarloUsed: Bool
    /// If non-empty, the user was inside a review session. Restore puts
    /// them back at this position in the queue.
    let reviewQueueCatalogIDs: [String]
    let reviewQueueIndex: Int
    let savedAt: Date
}

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

    /// Whether the active attempt is a fresh familiarization (AI/hints OK,
    /// answer reveal allowed) or a strict cold review (no inline help, just
    /// "got it cold / didn't").
    @Published private(set) var currentMode: PracticeMode = .familiarization

    /// Queue of catalog problems for the current review session, if any.
    /// Set by `startReviewSession(_:)`; consumed by `advanceReviewQueue()`
    /// as the user works through it. Empty when not in a review session.
    @Published private(set) var reviewQueue: [Stat110Problem] = []
    @Published private(set) var reviewQueueIndex: Int = 0

    var isInReviewSession: Bool { !reviewQueue.isEmpty }
    var reviewQueueRemaining: Int {
        max(0, reviewQueue.count - reviewQueueIndex)
    }

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
    private weak var masteryStore: MasteryStore?
    private var ticker: AnyCancellable?
    private var resumeTime: Date?
    private var accumulatedBeforePause: TimeInterval = 0

    init(container: ModelContainer, homeworkStore: HomeworkStore? = nil) {
        self.context = ModelContext(container)
        self.homeworkStore = homeworkStore
        refresh()
        // Restore any in-progress attempt left by a previous launch /
        // window close. The store is constructed at app launch (the
        // PracticeWindowController doesn't exist yet), so the moment the
        // user opens the Practice window they see the same problem at
        // the same elapsed seconds, paused.
        restoreSnapshotIfAvailable()
    }

    // MARK: - Snapshot persistence

    private static let snapshotKey = "practice.activeSnapshot"
    /// Hard cap on snapshot age. Older than this and we assume the user
    /// has moved on; we discard rather than ambushing them with stale
    /// state. Cognitive-science research aside, a week-old "in progress"
    /// attempt isn't really in progress.
    private static let snapshotMaxAge: TimeInterval = 7 * 86_400

    /// Save counter — we don't write every tick (every 0.5s) because
    /// that'd thrash UserDefaults; we write every N ticks for the
    /// periodic checkpoint. Direct triggers (start, pause, peek, finish)
    /// still write immediately.
    private var ticksSinceLastSave: Int = 0

    private func saveSnapshot() {
        guard isActive, let p = activeProblem else { return }
        // Always snapshot the current accumulated elapsed time. If the
        // user is mid-run we add the still-ticking interval up to now.
        let elapsedNow: TimeInterval = {
            if !isPaused, let r = resumeTime {
                return accumulatedBeforePause + Date().timeIntervalSince(r)
            }
            return accumulatedBeforePause
        }()
        let snap = PracticeSnapshot(
            catalogID: p.id,
            mode: currentMode,
            elapsedSeconds: elapsedNow,
            hintsPeeked: hintsPeeked,
            monteCarloUsed: monteCarloUsed,
            reviewQueueCatalogIDs: reviewQueue.map(\.id),
            reviewQueueIndex: reviewQueueIndex,
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
    }

    private func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
    }

    private func restoreSnapshotIfAvailable() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let snap = try? JSONDecoder().decode(PracticeSnapshot.self, from: data) else {
            return
        }
        // Staleness check — drop snapshots older than a week.
        if Date().timeIntervalSince(snap.savedAt) > Self.snapshotMaxAge {
            clearSnapshot()
            return
        }
        guard let problem = Stat110Catalog.problem(id: snap.catalogID) else {
            // Catalog drift — problem no longer exists. Drop the snapshot.
            clearSnapshot()
            return
        }
        // Rehydrate the review queue if there was one.
        let queue: [Stat110Problem] = snap.reviewQueueCatalogIDs
            .compactMap { Stat110Catalog.problem(id: $0) }

        // Restore state directly (don't go through `start(...)` because
        // that would reset elapsed to 0).
        activeProblem = problem
        currentMode = snap.mode
        accumulatedBeforePause = snap.elapsedSeconds
        elapsedSeconds = snap.elapsedSeconds
        hintsPeeked = snap.hintsPeeked
        monteCarloUsed = snap.monteCarloUsed
        reviewQueue = queue
        reviewQueueIndex = min(snap.reviewQueueIndex, max(0, queue.count - 1))
        // Always come back paused — the wall clock advanced while the
        // app was gone but the user wasn't working. They click Resume.
        isPaused = true
        resumeTime = nil
        isActive = true
        // Ticker stays off; resume() will start it.
    }

    /// Wire up the HomeworkStore after init. The App's init constructs
    /// both stores at the same time so we can't pass it inline.
    func attach(homeworkStore: HomeworkStore) {
        self.homeworkStore = homeworkStore
    }

    func attach(masteryStore: MasteryStore) {
        self.masteryStore = masteryStore
    }

    private func refresh() {
        var descriptor = FetchDescriptor<StoredDrillAttempt>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        attempts = (try? context.fetch(descriptor)) ?? []
    }

    /// Nuke all past drill attempts and homework rows. Used for the
    /// "reset history" button on the idle screen. Doesn't touch any
    /// other stores (sessions, day records, problems entries, scratch
    /// items remain). The destination is "as if the user never used
    /// practice mode before."
    func clearAllPracticeData() {
        if isActive { discardActive() }

        let attemptDescriptor = FetchDescriptor<StoredDrillAttempt>()
        if let rows = try? context.fetch(attemptDescriptor) {
            for r in rows { context.delete(r) }
        }
        let homeworkDescriptor = FetchDescriptor<StoredHomework>()
        if let rows = try? context.fetch(homeworkDescriptor) {
            for r in rows { context.delete(r) }
        }
        // Mastery ladder records + per-attempt mastery log. PracticeStore
        // owns its own ModelContext so we delete from that context and
        // tell MasteryStore (which uses a different context) to re-fetch.
        let masteryDescriptor = FetchDescriptor<StoredMasteryRecord>()
        if let rows = try? context.fetch(masteryDescriptor) {
            for r in rows { context.delete(r) }
        }
        let masteryAttemptDescriptor = FetchDescriptor<StoredMasteryAttempt>()
        if let rows = try? context.fetch(masteryAttemptDescriptor) {
            for r in rows { context.delete(r) }
        }
        try? context.save()
        refresh()
        homeworkStore?.refreshFromExternal()
        masteryStore?.refreshFromExternal()
    }

    // MARK: - Controls

    func start(problem: Stat110Problem, mode: PracticeMode = .familiarization) {
        guard !isActive else { return }
        activeProblem = problem
        elapsedSeconds = 0
        accumulatedBeforePause = 0
        resumeTime = Date()
        hintsPeeked = 0
        monteCarloUsed = false
        isPaused = false
        isActive = true
        currentMode = mode
        startTicker()
        saveSnapshot()
    }

    /// Begin a review session: queue up the (already-interleaved) problems
    /// and open the first one in review mode. `advanceReviewQueue()` moves
    /// to the next problem after each completion.
    func startReviewSession(_ problems: [Stat110Problem]) {
        guard !problems.isEmpty else { return }
        reviewQueue = problems
        reviewQueueIndex = 0
        if isActive { discardActive() }
        start(problem: problems[0], mode: .review)
    }

    /// Move to the next problem in the review queue, or end the session
    /// if we've worked through all of them. Called by every review-mode
    /// outcome handler after the current attempt is logged.
    func advanceReviewQueue() {
        reviewQueueIndex += 1
        if reviewQueueIndex < reviewQueue.count {
            start(problem: reviewQueue[reviewQueueIndex], mode: .review)
        } else {
            endReviewSession()
        }
    }

    func endReviewSession() {
        reviewQueue = []
        reviewQueueIndex = 0
        currentMode = .familiarization
    }

    func pause() {
        guard isActive, !isPaused, let resume = resumeTime else { return }
        accumulatedBeforePause += Date().timeIntervalSince(resume)
        elapsedSeconds = accumulatedBeforePause
        resumeTime = nil
        isPaused = true
        ticker?.cancel(); ticker = nil
        saveSnapshot()
    }

    func resume() {
        guard isActive, isPaused else { return }
        resumeTime = Date()
        isPaused = false
        startTicker()
        saveSnapshot()
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
                // Periodic checkpoint every ~30s while running so a crash
                // or hard quit doesn't lose more than half a minute of
                // elapsed time. Direct triggers (pause, hint, etc.) still
                // write immediately for sub-second freshness on the
                // important transitions.
                self.ticksSinceLastSave += 1
                if self.ticksSinceLastSave >= 60 {  // 60 × 0.5s = 30s
                    self.ticksSinceLastSave = 0
                    self.saveSnapshot()
                }
            }
    }

    func peekHint() {
        guard isActive else { return }
        hintsPeeked += 1
        saveSnapshot()
    }

    func markMonteCarlo() {
        guard isActive else { return }
        monteCarloUsed = true
        saveSnapshot()
    }

    // MARK: - Finish — routed through the mastery ladder
    //
    // The mode the attempt was launched in determines which mastery
    // method we call. Familiarization-mode finishes always set the
    // record to .familiarized (with R1 due in 24h). Review-mode finishes
    // advance or drop the ladder rung. We still write the legacy
    // StoredDrillAttempt rows so the audit-log surfaces (dashboard, stats)
    // keep working without further refactoring.

    /// Couldn't solve this attempt — even with AI. Logs time; stage stays
    /// where it is, nextDue is nudged out a day so it doesn't loop back
    /// instantly.
    func finishStuck(notes: String) {
        guard isActive else { return }
        let elapsed = freezeElapsed()
        persistAttempt(outcome: .stuck, notes: notes,
                       confidenceInt: intFor(.struggled), elapsed: elapsed)
        if let p = activeProblem {
            masteryStore?.recordReviewFail(problem: p,
                                           durationSeconds: elapsed,
                                           notes: notes)
        }
        let wasInReviewSession = isInReviewSession
        resetActive()
        refresh()
        if wasInReviewSession { advanceReviewQueue() }
    }

    /// Manually pin the active problem to a specific ladder stage.
    /// Logs the in-progress time spent against the audit log so the
    /// per-problem history still credits the work.
    func setStageManually(_ stage: MasteryStage) {
        guard isActive, let p = activeProblem else { return }
        let elapsed = freezeElapsed()
        if elapsed > 0 {
            persistAttempt(outcome: .skipped, notes: "Manual stage set",
                           confidenceInt: 0, elapsed: elapsed)
        }
        masteryStore?.setStage(problem: p, stage: stage)
        let wasInReviewSession = isInReviewSession
        resetActive()
        refresh()
        if wasInReviewSession { advanceReviewQueue() }
    }

    /// Remove the active problem from the ladder entirely (for when you
    /// shelve something you've decided not to study).
    func removeFromLadder() {
        guard isActive, let p = activeProblem else { return }
        masteryStore?.resetLadder(problem: p)
        discardActive()
    }

    /// Solved this attempt. Advances the ladder one rung iff `usedAI` is
    /// false. With AI, logs the attempt and anchors a fresh problem at R1
    /// but doesn't promote anything that was already on the ladder.
    func finishSolved(usedAI: Bool, notes: String) {
        guard isActive else { return }
        let elapsed = freezeElapsed()
        persistAttempt(outcome: usedAI ? .aiWalkthrough : .solved,
                       notes: notes,
                       confidenceInt: intFor(usedAI ? .shaky : .solid),
                       elapsed: elapsed)
        if let p = activeProblem {
            masteryStore?.recordReviewPass(problem: p,
                                           usedAI: usedAI,
                                           durationSeconds: elapsed,
                                           notes: notes)
        }
        let wasInReviewSession = isInReviewSession
        resetActive()
        refresh()
        if wasInReviewSession { advanceReviewQueue() }
    }

    /// Mark the active problem as fully retained, bypassing the review
    /// ladder entirely. For when the user already knows the material cold
    /// and doesn't need spaced repetition on it.
    func markAsRetained(notes: String = "") {
        guard isActive else { return }
        let elapsed = freezeElapsed()
        persistAttempt(outcome: .solved, notes: notes,
                       confidenceInt: intFor(.solid), elapsed: elapsed)
        if let p = activeProblem {
            masteryStore?.skipToRetained(problem: p,
                                         durationSeconds: elapsed,
                                         notes: notes)
        }
        let wasInReviewSession = isInReviewSession
        resetActive()
        refresh()
        if wasInReviewSession { advanceReviewQueue() }
    }

    /// Skipped — bailed early without engaging. No mastery-state change.
    /// In review mode, also advances the queue.
    func finishSkipped(notes: String) {
        guard isActive else { return }
        let elapsed = freezeElapsed()
        persistAttempt(outcome: .skipped, notes: notes,
                       confidenceInt: 0, elapsed: elapsed)
        let wasInReviewSession = isInReviewSession
        resetActive()
        refresh()
        if wasInReviewSession { advanceReviewQueue() }
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
        // Discarding from a review session aborts the whole session — the
        // user can re-start later. Doesn't drop ladder rungs for problems
        // already completed in this session, just stops queueing more.
        let wasInReviewSession = isInReviewSession
        resetActive()
        if wasInReviewSession { endReviewSession() }
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
        ticksSinceLastSave = 0
        // Clear the persisted in-progress snapshot. resetActive runs at
        // the end of every finish*/discard path, so this is the single
        // gate that guarantees no stale snapshot survives a logged
        // attempt. (Mid-session transitions like `start` re-save it.)
        clearSnapshot()
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
