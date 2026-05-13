import Foundation

class ProblemStore: ObservableObject {
    @Published var problems: [ProblemEntry] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("LockIn")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("problems.json")
        load()
    }

    func add(_ entry: ProblemEntry) {
        problems.append(entry)
        save()
    }

    func clearAll() {
        problems = []
        save()
    }

    func clearReview(id: UUID) {
        guard let i = problems.firstIndex(where: { $0.id == id }) else { return }
        problems[i].needsReview = false
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(problems) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([ProblemEntry].self, from: data) {
            problems = decoded
        }
    }

    // MARK: - Aggregates

    func count(for domain: ProblemDomain) -> Int {
        problems.filter { $0.domain == domain }.count
    }

    var totalCount: Int { problems.count }

    var needsReviewItems: [ProblemEntry] {
        problems.filter { $0.needsReview }.sorted { $0.date > $1.date }
    }

    func countByCategory(domain: ProblemDomain) -> [(category: String, count: Int)] {
        var dict: [String: Int] = [:]
        for p in problems where p.domain == domain {
            for cat in p.categories {
                dict[cat, default: 0] += 1
            }
        }
        return dict.map { (category: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    /// Problems grouped by calendar day, newest first.
    func byDay() -> [(date: Date, problems: [ProblemEntry])] {
        let calendar = Calendar.current
        var groups: [Date: [ProblemEntry]] = [:]
        for p in problems {
            let day = calendar.startOfDay(for: p.date)
            groups[day, default: []].append(p)
        }
        return groups.map { (date: $0.key, problems: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    /// Count per day for the last N days (oldest → newest), including zero-count days.
    func dailyCounts(days: Int) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let count = problems.filter { cal.startOfDay(for: $0.date) == day }.count
            return (date: day, count: count)
        }
    }

    var thisWeekCount: Int {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        return problems.filter { $0.date >= start }.count
    }

    var lastWeekCount: Int {
        let cal = Calendar.current
        let thisStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        let lastStart = cal.date(byAdding: .day, value: -7, to: thisStart)!
        return problems.filter { $0.date >= lastStart && $0.date < thisStart }.count
    }

    /// Fraction of all problems logged without AI help.
    var cleanSolveRate: Double {
        guard !problems.isEmpty else { return 1.0 }
        return Double(problems.filter { !$0.needsReview }.count) / Double(problems.count)
    }

    func countByDifficulty() -> [(difficulty: ProblemDifficulty, count: Int)] {
        ProblemDifficulty.allCases.map { d in
            (difficulty: d, count: problems.filter { $0.difficulty == d }.count)
        }
    }

    func countByConfidence() -> [(confidence: Confidence, count: Int)] {
        Confidence.allCases.map { c in
            (confidence: c, count: problems.filter { $0.confidence == c }.count)
        }
    }
}
