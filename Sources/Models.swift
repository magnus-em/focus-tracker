import Foundation

// MARK: - Problem tracking

enum ProblemDifficulty: String, Codable, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
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

    init(title: String = "", domain: ProblemDomain, categories: [String], difficulty: ProblemDifficulty) {
        self.id = UUID()
        self.date = Date()
        self.title = title
        self.domain = domain
        self.categories = categories
        self.difficulty = difficulty
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
