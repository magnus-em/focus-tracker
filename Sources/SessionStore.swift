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

    // MARK: - Charts

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

    func weeklyAverage() -> Double {
        let summaries = dailySummaries(last: 7)
        let activeDays = summaries.filter { $0.totalWorkMinutes > 0 }.count
        guard activeDays > 0 else { return 0 }
        let total = summaries.reduce(0) { $0 + $1.totalWorkMinutes }
        return total / Double(activeDays)
    }
}
