import Foundation

struct WorkSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let durationMinutes: Double
    let type: SessionType

    init(startTime: Date, durationMinutes: Double, type: SessionType) {
        self.id = UUID()
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.type = type
    }

    enum SessionType: String, Codable {
        case work
        case shortBreak
        case longBreak
    }
}

struct DailySummary: Identifiable {
    let id: String
    let date: Date
    let totalWorkMinutes: Double
    let sessionCount: Int
}
