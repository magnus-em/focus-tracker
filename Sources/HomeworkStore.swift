import Foundation
import FocusCore
import SwiftData

class HomeworkStore: ObservableObject {
    @Published var items: [HomeworkProblem] = []

    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        refresh()
    }

    private func refresh() {
        var descriptor = FetchDescriptor<StoredHomework>(
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.includePendingChanges = true
        let stored = (try? context.fetch(descriptor)) ?? []
        items = stored.map { $0.asValue }
    }

    func add(_ item: HomeworkProblem) {
        context.insert(StoredHomework(value: item))
        try? context.save()
        refresh()
    }

    func update(_ item: HomeworkProblem) {
        let target = item.id
        let predicate = #Predicate<StoredHomework> { $0.id == target }
        var descriptor = FetchDescriptor<StoredHomework>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let model = try? context.fetch(descriptor).first else { return }
        model.title = item.title
        model.source = item.source
        model.difficulty = item.difficulty
        model.confidence = item.confidence
        model.usedAI = item.usedAI
        model.notes = item.notes
        model.urlString = item.url
        // Previously omitted — bug. Without these the review queue
        // never updated when the user toggled "needs review" or set
        // a custom review date.
        model.needsReview = item.needsReview
        model.reviewOverrideDate = item.reviewOverrideDate
        model.catalogID = item.catalogID
        try? context.save()
        refresh()
    }

    /// Upsert a homework entry from a Practice Mode finish event. If an
    /// entry with the same `catalogID` already exists, update it in place
    /// (so the homework row reflects the LATEST attempt's confidence /
    /// difficulty / review flag, not a parallel history). Otherwise
    /// create a new entry. Returns the resulting HomeworkProblem.
    ///
    /// Why upsert by catalogID: the user wants one "current state" row
    /// per problem in the homework list. The full attempt history lives
    /// in StoredDrillAttempt; this method just keeps the homework row's
    /// confidence/needsReview in sync with the most recent attempt.
    @discardableResult
    func upsertFromPractice(catalogID: String?,
                            title: String,
                            source: String,
                            difficulty: ProblemDifficulty,
                            confidence: Confidence,
                            needsReview: Bool,
                            notes: String,
                            url: String,
                            solveMinutes: Int?) -> HomeworkProblem {
        // Look up by catalogID first (the canonical identity for catalog
        // problems). Manual entries with no catalogID never upsert —
        // they always create a fresh row.
        if let catID = catalogID,
           let existing = items.first(where: { $0.catalogID == catID }) {
            let updated = HomeworkProblem(
                id: existing.id,
                date: Date(),                 // bump to latest attempt
                title: title,
                source: source,
                difficulty: difficulty,
                confidence: confidence,
                usedAI: existing.usedAI,
                notes: mergedNotes(existing.notes, notes),
                url: url.isEmpty ? existing.url : url,
                catalogID: catID,
                needsReview: needsReview,
                reviewOverrideDate: existing.reviewOverrideDate
            )
            update(updated)
            return updated
        }
        let entry = HomeworkProblem(
            title: title,
            source: source,
            difficulty: difficulty,
            confidence: confidence,
            usedAI: false,
            notes: notes,
            url: url,
            catalogID: catalogID,
            needsReview: needsReview,
            reviewOverrideDate: nil
        )
        add(entry)
        return entry
    }

    /// Join old notes + new attempt notes with a newline separator so
    /// we don't clobber the user's prior writing. New on top.
    private func mergedNotes(_ existing: String, _ new: String) -> String {
        let trimmedNew = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOld = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNew.isEmpty { return existing }
        if trimmedOld.isEmpty { return trimmedNew }
        return "\(trimmedNew)\n---\n\(trimmedOld)"
    }

    // MARK: - Review queue

    /// Problems whose computed review date has passed. Source of truth
    /// for the "Due for review" surface in Practice Mode.
    var dueForReview: [HomeworkProblem] {
        items.filter { $0.isDueForReview }.sorted { ($0.reviewDueDate ?? .distantFuture) < ($1.reviewDueDate ?? .distantFuture) }
    }

    func delete(id: UUID) {
        let target = id
        let predicate = #Predicate<StoredHomework> { $0.id == target }
        var descriptor = FetchDescriptor<StoredHomework>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            context.delete(model)
            try? context.save()
            refresh()
        }
    }

    var byNewest: [HomeworkProblem] { items.sorted { $0.date > $1.date } }
}
