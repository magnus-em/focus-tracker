import Foundation
import FocusCore
import SwiftData

enum HealthKind: String, CaseIterable, Identifiable {
    case fap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fap: return "Fap"
        }
    }

    var icon: String {
        switch self {
        case .fap: return "drop.fill"
        }
    }
}

struct HealthEvent: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let kind: HealthKind
}

struct HealthWeek: Identifiable {
    let start: Date
    let count: Int
    let focusHours: Double
    var id: Date { start }
}

class HealthStore: ObservableObject {
    @Published private(set) var events: [HealthEvent] = []

    private let context: ModelContext

    static let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        refresh()
    }

    func refresh() {
        var descriptor = FetchDescriptor<StoredHealthEvent>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        let stored = (try? context.fetch(descriptor)) ?? []
        events = stored.compactMap { s in
            HealthKind(rawValue: s.kind).map { HealthEvent(id: s.id, date: s.date, kind: $0) }
        }
    }

    @discardableResult
    func log(_ kind: HealthKind, at date: Date = Date()) -> UUID {
        let model = StoredHealthEvent(date: date, kind: kind.rawValue)
        context.insert(model)
        try? context.save()
        refresh()
        return model.id
    }

    func delete(id: UUID) {
        let predicate = #Predicate<StoredHealthEvent> { $0.id == id }
        try? context.delete(model: StoredHealthEvent.self, where: predicate)
        try? context.save()
        refresh()
    }

    // MARK: - Stats

    func events(_ kind: HealthKind) -> [HealthEvent] {
        events.filter { $0.kind == kind }
    }

    func weekStart(_ date: Date) -> Date {
        Self.calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? Self.calendar.startOfDay(for: date)
    }

    func count(_ kind: HealthKind, from start: Date, to end: Date) -> Int {
        events.filter { $0.kind == kind && $0.date >= start && $0.date < end }.count
    }

    func daysSinceLast(_ kind: HealthKind) -> Int? {
        guard let last = events(kind).first else { return nil }
        let cal = Self.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: last.date), to: cal.startOfDay(for: Date())).day
    }

    /// Oldest first, ending with the current week.
    func weeks(_ kind: HealthKind, count n: Int, sessionStore: SessionStore) -> [HealthWeek] {
        let cal = Self.calendar
        let thisWeek = weekStart(Date())
        return (0..<n).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            return HealthWeek(
                start: start,
                count: count(kind, from: start, to: end),
                focusHours: sessionStore.workMinutes(since: start, until: end) / 60
            )
        }
    }

    /// Longest run of whole days with no event, counting the open run up to today.
    func longestGapDays(_ kind: HealthKind) -> Int {
        let cal = Self.calendar
        let days = Set(events(kind).map { cal.startOfDay(for: $0.date) }).sorted()
        guard days.count > 0 else { return 0 }
        var best = 0
        for (a, b) in zip(days, days.dropFirst()) {
            best = max(best, (cal.dateComponents([.day], from: a, to: b).day ?? 1) - 1)
        }
        let open = cal.dateComponents([.day], from: days.last!, to: cal.startOfDay(for: Date())).day ?? 0
        return max(best, open)
    }
}
