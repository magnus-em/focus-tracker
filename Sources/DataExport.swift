import Foundation
import SwiftData
import AppKit
import FocusCore

/// Mac equivalent of the iPad's DataExport. Same snapshot format —
/// dump every Stored* model to one timestamped JSON file, then offer
/// it via the system save panel.
enum DataExport {
    struct Snapshot: Codable {
        struct WorkSessionDTO: Codable {
            let id: UUID
            let startTime: Date
            let durationMinutes: Double
            let type: String
            let label: String?
            let breakKinds: [String]
        }
        struct ProblemDTO: Codable {
            let id: UUID
            let date: Date
            let title: String
            let domain: String
            let categories: [String]
            let difficulty: String
            let confidence: String
            let needsReview: Bool
            let source: String
            let notes: String
            let url: String
            let solveMinutes: Int?
        }
        struct HomeworkDTO: Codable {
            let id: UUID
            let date: Date
            let title: String
            let source: String
            let difficulty: String
            let confidence: String
            let usedAI: Bool
            let notes: String
            let url: String
        }
        struct DayRecordDTO: Codable {
            let id: UUID
            let calendarDay: Date
            let dayStart: Date?
            let dayEnd: Date?
        }
        struct ScratchDTO: Codable {
            let id: UUID
            let text: String
            let isChecked: Bool
            let order: Int
        }

        let exportedAt: Date
        let sessions: [WorkSessionDTO]
        let problems: [ProblemDTO]
        let homework: [HomeworkDTO]
        let dayRecords: [DayRecordDTO]
        let scratch: [ScratchDTO]
    }

    static func showSavePanel(container: ModelContainer) {
        let ctx = ModelContext(container)
        let sessions = (try? ctx.fetch(FetchDescriptor<StoredWorkSession>())) ?? []
        let problems = (try? ctx.fetch(FetchDescriptor<StoredProblem>())) ?? []
        let homework = (try? ctx.fetch(FetchDescriptor<StoredHomework>())) ?? []
        let days = (try? ctx.fetch(FetchDescriptor<StoredDayRecord>())) ?? []
        let scratch = (try? ctx.fetch(FetchDescriptor<StoredScratchItem>())) ?? []

        let snap = Snapshot(
            exportedAt: Date(),
            sessions: sessions.map {
                .init(id: $0.id, startTime: $0.startTime,
                      durationMinutes: $0.durationMinutes, type: $0.typeRaw,
                      label: $0.label, breakKinds: $0.breakKindsRaw)
            },
            problems: problems.map {
                .init(id: $0.id, date: $0.date, title: $0.title,
                      domain: $0.domainRaw, categories: $0.categories,
                      difficulty: $0.difficultyRaw, confidence: $0.confidenceRaw,
                      needsReview: $0.needsReview, source: $0.source,
                      notes: $0.notes, url: $0.urlString,
                      solveMinutes: $0.solveMinutes)
            },
            homework: homework.map {
                .init(id: $0.id, date: $0.date, title: $0.title,
                      source: $0.source, difficulty: $0.difficultyRaw,
                      confidence: $0.confidenceRaw, usedAI: $0.usedAI,
                      notes: $0.notes, url: $0.urlString)
            },
            dayRecords: days.map {
                .init(id: $0.id, calendarDay: $0.calendarDay,
                      dayStart: $0.dayStart, dayEnd: $0.dayEnd)
            },
            scratch: scratch.map {
                .init(id: $0.id, text: $0.text,
                      isChecked: $0.isChecked, order: $0.order)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snap) else { return }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "focus-export-\(f.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
