import Foundation
import Combine

struct ZetamacGameResult: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let durationSeconds: Int
    let correctCount: Int
    let attemptedCount: Int

    init(id: UUID = UUID(), startTime: Date, durationSeconds: Int, correctCount: Int, attemptedCount: Int) {
        self.id = id
        self.startTime = startTime
        self.durationSeconds = durationSeconds
        self.correctCount = correctCount
        self.attemptedCount = attemptedCount
    }

    var problemsPerMinute: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(correctCount) * 60.0 / Double(durationSeconds)
    }

    var accuracy: Double {
        guard attemptedCount > 0 else { return 0 }
        return Double(correctCount) / Double(attemptedCount)
    }
}

@MainActor
final class ZetamacStore: ObservableObject {
    @Published private(set) var results: [ZetamacGameResult] = []

    /// True while a sprint is in progress. Published so the menu-bar
    /// popover can show "Sprint running · 01:34 · 12 correct" instead of
    /// the bare "Math Sprint" CTA — and so we can guarantee the popover
    /// button never silently restarts a mid-flight game.
    @Published var isGameActive: Bool = false
    @Published var liveScore: Int = 0
    @Published var liveSecondsLeft: Int = 0

    func gameStarted(durationSeconds: Int) {
        isGameActive = true
        liveScore = 0
        liveSecondsLeft = durationSeconds
    }

    func gameTick(score: Int, secondsLeft: Int) {
        if liveScore != score { liveScore = score }
        if liveSecondsLeft != secondsLeft { liveSecondsLeft = secondsLeft }
    }

    func gameFinished() {
        isGameActive = false
    }

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Focus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("zetamac.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ZetamacGameResult].self, from: data) {
            results = decoded.sorted { $0.startTime > $1.startTime }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(results) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func record(_ result: ZetamacGameResult) {
        results.insert(result, at: 0)
        save()
    }

    var bestScore: Int { results.map(\.correctCount).max() ?? 0 }

    var todayResults: [ZetamacGameResult] {
        let cal = Calendar.current
        return results.filter { cal.isDateInToday($0.startTime) }
    }

    var todayBest: Int { todayResults.map(\.correctCount).max() ?? 0 }

    func recentAverage(days: Int = 7) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let recent = results.filter { $0.startTime >= cutoff }
        guard !recent.isEmpty else { return 0 }
        return Double(recent.map(\.correctCount).reduce(0, +)) / Double(recent.count)
    }

    // MARK: - Daily goal
    //
    // Floor 5 games / day. Anything below that doesn't satisfy the goal.
    // Between 5 and 9 games: a new personal best counts as "done" — beating
    // your record is enough, don't grind. Otherwise play to 10.
    // The user can keep playing past either threshold; the goal is a stop
    // signal, not a cap.

    static let dailyGoalFloor = 5
    static let dailyGoalCeiling = 10

    var todaySessionCount: Int { todayResults.count }

    /// Best score from *before* today. Used to decide whether anything
    /// played today qualifies as a new all-time PB.
    var bestBeforeToday: Int {
        let cal = Calendar.current
        return results
            .filter { !cal.isDateInToday($0.startTime) }
            .map(\.correctCount).max() ?? 0
    }

    var todayHasPersonalBest: Bool {
        todayBest > 0 && todayBest > bestBeforeToday
    }

    var todayGoalMet: Bool {
        let n = todaySessionCount
        if n >= Self.dailyGoalCeiling { return true }
        if n >= Self.dailyGoalFloor && todayHasPersonalBest { return true }
        return false
    }
}
