import Foundation
import FocusCore
import SwiftData

class DayStore: ObservableObject {
    @Published var records: [DayRecord] = []

    private let context: ModelContext
    private var dayChangedObserver: NSObjectProtocol?

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        refresh()

        // `todayRecord` filters via `Calendar.isDateInToday(...)`. When the
        // menu-bar app stays running across midnight, no @Published fires
        // so SwiftUI doesn't re-render — `isDayStarted` keeps returning
        // true for yesterday's record. NSCalendarDayChanged forces a
        // re-render at the boundary.
        dayChangedObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        if let o = dayChangedObserver { NotificationCenter.default.removeObserver(o) }
    }

    /// Force-refresh path for `.onAppear` of any view that shows
    /// "today"-scoped UI — covers the case where the day-change
    /// notification was missed while the system was asleep.
    func touchForToday() {
        objectWillChange.send()
    }

    private func refresh() {
        var descriptor = FetchDescriptor<StoredDayRecord>(
            sortBy: [SortDescriptor(\.calendarDay)]
        )
        descriptor.includePendingChanges = true
        let stored = (try? context.fetch(descriptor)) ?? []
        records = stored.map { $0.asValue }
    }

    var todayRecord: DayRecord? {
        records.first { Calendar.current.isDateInToday($0.calendarDay) }
    }

    var isDayStarted: Bool {
        guard let r = todayRecord else { return false }
        return r.dayStart != nil && r.dayEnd == nil
    }

    var isDayEnded: Bool { todayRecord?.dayEnd != nil }

    func startDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<StoredDayRecord> { $0.calendarDay == today }
        var descriptor = FetchDescriptor<StoredDayRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            model.dayStart = Date()
            model.dayEnd = nil
        } else {
            let stored = StoredDayRecord()
            stored.calendarDay = today
            stored.dayStart = Date()
            context.insert(stored)
        }
        try? context.save()
        refresh()
    }

    func endDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<StoredDayRecord> { $0.calendarDay == today }
        var descriptor = FetchDescriptor<StoredDayRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            model.dayEnd = Date()
            try? context.save()
            refresh()
        }
    }

    func reopenDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<StoredDayRecord> { $0.calendarDay == today }
        var descriptor = FetchDescriptor<StoredDayRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            model.dayEnd = nil
            if model.dayStart == nil { model.dayStart = Date() }
            try? context.save()
            refresh()
        }
    }

    func record(for date: Date) -> DayRecord? {
        records.first { Calendar.current.isDate($0.calendarDay, inSameDayAs: date) }
    }

    // MARK: - Commitment review

    /// Write today's morning commitment into the day record. Creates the
    /// record if `startDay()` wasn't pressed first.
    func setCommitment(text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        let today = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<StoredDayRecord> { $0.calendarDay == today }
        var descriptor = FetchDescriptor<StoredDayRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            model.commitmentText = cleaned.isEmpty ? nil : cleaned
            model.commitmentFulfilled = nil
        } else {
            let stored = StoredDayRecord()
            stored.calendarDay = today
            stored.commitmentText = cleaned.isEmpty ? nil : cleaned
            context.insert(stored)
        }
        try? context.save()
        refresh()
    }

    /// Record whether the user followed through on a given day's commitment.
    func setFulfillment(_ fulfilled: Bool, forDayID id: UUID) {
        let predicate = #Predicate<StoredDayRecord> { $0.id == id }
        var descriptor = FetchDescriptor<StoredDayRecord>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            model.commitmentFulfilled = fulfilled
            try? context.save()
            refresh()
        }
    }

    /// Most recent past day that has a commitment but hasn't been reviewed
    /// yet. Returns nil if everything's caught up.
    func pendingReviewDay() -> DayRecord? {
        let today = Calendar.current.startOfDay(for: Date())
        return records
            .filter { $0.calendarDay < today }
            .filter { ($0.commitmentText?.isEmpty == false) && $0.commitmentFulfilled == nil }
            .sorted { $0.calendarDay > $1.calendarDay }
            .first
    }

    /// Today's commitment, if reviewable now (text set, not yet answered).
    var todayCommitmentNeedsReview: Bool {
        guard let r = todayRecord else { return false }
        return (r.commitmentText?.isEmpty == false) && r.commitmentFulfilled == nil
    }

    /// Consecutive days going backward from yesterday where the user
    /// fulfilled their commitment. Days without a commitment are skipped
    /// (neither help nor hurt); a `false` answer breaks the streak; an
    /// unreviewed day with a commitment breaks (review it first).
    var commitmentStreak: Int {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        var streak = 0
        var cursor = yesterday
        let earliest = records.map(\.calendarDay).min() ?? yesterday
        while cursor >= earliest {
            if let r = record(for: cursor) {
                if let text = r.commitmentText, !text.isEmpty {
                    if r.commitmentFulfilled == true { streak += 1 }
                    else { break }
                }
            }
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    /// Tally of fulfilled / missed / unreviewed days with commitments over
    /// the last `n` calendar days (inclusive of today).
    func commitmentTally(lastDays n: Int) -> (fulfilled: Int, missed: Int, unreviewed: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -(n - 1), to: today)!
        var f = 0, m = 0, u = 0
        for r in records where r.calendarDay >= cutoff && r.calendarDay <= today {
            guard let text = r.commitmentText, !text.isEmpty else { continue }
            switch r.commitmentFulfilled {
            case .some(true):  f += 1
            case .some(false): m += 1
            case .none:        u += 1
            }
        }
        return (f, m, u)
    }
}
