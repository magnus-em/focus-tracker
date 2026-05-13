import Foundation

// MARK: - Problem tracking

enum ProblemDifficulty: String, Codable, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

enum Confidence: String, Codable, CaseIterable {
    case solid = "Got it"
    case shaky = "Shaky"
    case struggled = "Struggled"
}

enum ProblemDomain: String, Codable, CaseIterable {
    case quant = "Quant"
    case swe = "SWE"

    var categories: [String] {
        switch self {
        case .quant: return [
            "Probability", "Combinatorics", "Expected Value", "Distributions",
            "Random Walks", "Martingales", "Stochastic Calculus", "Game Theory",
            "Markov Chains", "Linear Algebra", "Statistics", "Options Math", "Brainteasers"
        ]
        case .swe: return [
            "Arrays & Hashing", "Two Pointers", "Sliding Window", "Stack",
            "Binary Search", "Linked List", "Trees", "Tries", "Heap",
            "Backtracking", "Graphs", "Dynamic Programming", "Greedy",
            "Intervals", "Bit Manipulation", "Math & Geometry"
        ]
        }
    }
}

struct ProblemEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let domain: ProblemDomain
    let categories: [String]
    let difficulty: ProblemDifficulty
    var needsReview: Bool
    var confidence: Confidence

    enum CodingKeys: String, CodingKey {
        case id, date, title, domain, categories, difficulty, needsReview, confidence
    }

    init(title: String = "", domain: ProblemDomain, categories: [String],
         difficulty: ProblemDifficulty, needsReview: Bool = false, confidence: Confidence = .solid) {
        self.id = UUID()
        self.date = Date()
        self.title = title
        self.domain = domain
        self.categories = categories
        self.difficulty = difficulty
        self.needsReview = needsReview
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,            forKey: .id)
        date       = try c.decode(Date.self,            forKey: .date)
        title      = try c.decode(String.self,          forKey: .title)
        domain     = try c.decode(ProblemDomain.self,   forKey: .domain)
        categories = try c.decode([String].self,        forKey: .categories)
        difficulty = try c.decode(ProblemDifficulty.self, forKey: .difficulty)
        needsReview = try c.decodeIfPresent(Bool.self,       forKey: .needsReview) ?? false
        confidence  = try c.decodeIfPresent(Confidence.self, forKey: .confidence)  ?? .solid
    }
}

// MARK: - Timer sessions

struct WorkSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let durationMinutes: Double
    let type: SessionType
    var label: String?

    init(startTime: Date, durationMinutes: Double, type: SessionType, label: String? = nil) {
        self.id = UUID()
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.type = type
        self.label = label
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

// MARK: - Scratchpad

struct ScratchItem: Codable, Identifiable {
    let id: UUID
    var text: String
    var isChecked: Bool

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.isChecked = false
    }
}
