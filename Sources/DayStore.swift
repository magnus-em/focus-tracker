import Foundation
import FocusCore
import SwiftData

class DayStore: ObservableObject {
    @Published var records: [DayRecord] = []

    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        refresh()
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
