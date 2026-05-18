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
        try? context.save()
        refresh()
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
