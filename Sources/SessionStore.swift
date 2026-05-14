import Foundation
import SwiftUI

class SessionStore: ObservableObject {
    @Published var sessions: [WorkSession] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("LockIn")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("sessions.json")
        load()
    }

    func addSession(_ session: WorkSession) {
        sessions.append(session)
        save()
    }

    func clearAllData() {
        sessions = []
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(sessions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([WorkSession].self, from: data) {
            sessions = decoded
        }
    }

    // MARK: - Today

    var todayWorkSessions: [WorkSession] {
        let calendar = Calendar.current
        return sessions.filter {
            $0.type == .work && calendar.isDateInToday($0.startTime)
        }
    }

    var todayWorkMinutes: Double {
        todayWorkSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    var todaySessionCount: Int {
        todayWorkSessions.count
    }

    // MARK: - Streaks

    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        // If today has no sessions yet, start from yesterday
        if !hasSessions(on: checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        while hasSessions(on: checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        return streak
    }

    private func hasSessions(on date: Date) -> Bool {
        let calendar = Calendar.current
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)!
        return sessions.contains {
            $0.type == .work && $0.startTime >= date && $0.startTime < dayEnd
        }
    }

    // MARK: - Lifetime

    var totalWorkHours: Double {
        sessions.filter { $0.type == .work }.reduce(0) { $0 + $1.durationMinutes } / 60.0
    }

    var totalWorkSessions: Int {
        sessions.filter { $0.type == .work }.count
    }

    var bestStreak: Int {
        let calendar = Calendar.current
        let activeDays = Set(sessions
            .filter { $0.type == .work }
            .map { calendar.startOfDay(for: $0.startTime) }
        ).sorted()

        guard !activeDays.isEmpty else { return 0 }

        var best = 1
        var current = 1
        for i in 1..<activeDays.count {
            let diff = calendar.dateComponents([.day], from: activeDays[i-1], to: activeDays[i]).day ?? 0
            if diff == 1 {
                current += 1
                if current > best { best = current }
            } else if diff > 1 {
                current = 1
            }
        }
        return max(best, currentStreak)
    }

    var bestDayMinutes: Double {
        let calendar = Calendar.current
        var dailyTotals: [Date: Double] = [:]
        for session in sessions where session.type == .work {
            let day = calendar.startOfDay(for: session.startTime)
            dailyTotals[day, default: 0] += session.durationMinutes
        }
        return dailyTotals.values.max() ?? 0
    }

    // MARK: - Charts

    /// Returns (date, minutes) for the last `weeks` calendar weeks, starting on Sunday.
    /// minutes == -1 means a future date (render as empty).
    func heatmapData(weeks: Int) -> [(date: Date, minutes: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1=Sun … 7=Sat
        let thisSunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today)!
        let startDate = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisSunday)!

        return (0..<(weeks * 7)).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDate)!
            guard date <= today else { return (date: date, minutes: -1) }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)!
            let mins = sessions.filter {
                $0.type == .work && $0.startTime >= date && $0.startTime < dayEnd
            }.reduce(0.0) { $0 + $1.durationMinutes }
            return (date: date, minutes: mins)
        }
    }

    func dailySummaries(last days: Int) -> [DailySummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<days).map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -(days - 1 - daysAgo), to: today)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: date)!

            let daySessions = sessions.filter {
                $0.type == .work && $0.startTime >= date && $0.startTime < dayEnd
            }

            let totalMinutes = daySessions.reduce(0.0) { $0 + $1.durationMinutes }

            return DailySummary(
                id: "day-\(daysAgo)",
                date: date,
                totalWorkMinutes: totalMinutes,
                sessionCount: daySessions.count
            )
        }
    }

    /// Total work minutes grouped by label, sorted descending. Includes all historical labels.
    func minutesByTag() -> [(tag: String, minutes: Double)] {
        var dict: [String: Double] = [:]
        for session in sessions where session.type == .work {
            guard let label = session.label, !label.isEmpty else { continue }
            dict[label, default: 0] += session.durationMinutes
        }
        return dict.map { (tag: $0.key, minutes: $0.value) }.sorted { $0.minutes > $1.minutes }
    }

    func weeklyAverage() -> Double {
        let summaries = dailySummaries(last: 7)
        let activeDays = summaries.filter { $0.totalWorkMinutes > 0 }.count
        guard activeDays > 0 else { return 0 }
        let total = summaries.reduce(0) { $0 + $1.totalWorkMinutes }
        return total / Double(activeDays)
    }

    // MARK: - Ranged queries

    func workMinutes(since start: Date, until end: Date? = nil) -> Double {
        let end = end ?? Date()
        return sessions.filter {
            $0.type == .work && $0.startTime >= start && $0.startTime < end
        }.reduce(0.0) { $0 + $1.durationMinutes }
    }

    func minutesByTag(since start: Date, until end: Date? = nil) -> [(tag: String, minutes: Double)] {
        let end = end ?? Date()
        var dict: [String: Double] = [:]
        for s in sessions where s.type == .work && s.startTime >= start && s.startTime < end {
            guard let label = s.label, !label.isEmpty else { continue }
            dict[label, default: 0] += s.durationMinutes
        }
        return dict.map { (tag: $0.key, minutes: $0.value) }.sorted { $0.minutes > $1.minutes }
    }

    /// Last 7 days (rolling, including today).
    var last7DaysMinutes: Double {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return workMinutes(since: start)
    }

    /// The 7-day window before `last7Days` (days -13 through -7).
    var prior7DaysMinutes: Double {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date()))!
        let end = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        return workMinutes(since: start, until: end)
    }

    /// Average minutes/session over the last `n` work sessions.
    func averageSessionMinutes(last n: Int = 20) -> Double {
        let recent = sessions.filter { $0.type == .work }.suffix(n)
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0.0) { $0 + $1.durationMinutes } / Double(recent.count)
    }
}
