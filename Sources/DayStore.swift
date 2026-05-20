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

    func record(for date: Date) -> DayRecord? {
        records.first { Calendar.current.isDate($0.calendarDay, inSameDayAs: date) }
    }
}
