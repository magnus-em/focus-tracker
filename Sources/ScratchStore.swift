import Foundation
import FocusCore
import SwiftData

class ScratchStore: ObservableObject {
    @Published var items: [ScratchItem] = []

    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        refresh()
    }

    private func refresh() {
        var descriptor = FetchDescriptor<StoredScratchItem>(
            sortBy: [SortDescriptor(\.order)]
        )
        descriptor.includePendingChanges = true
        let stored = (try? context.fetch(descriptor)) ?? []
        items = stored.map { $0.asValue }
    }

    private func nextOrder() -> Int {
        var descriptor = FetchDescriptor<StoredScratchItem>(
            sortBy: [SortDescriptor(\.order, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let highest = try? context.fetch(descriptor).first {
            return highest.order + 1
        }
        return 0
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let item = StoredScratchItem(value: ScratchItem(text: trimmed), order: nextOrder())
        context.insert(item)
        try? context.save()
        refresh()
    }

    func toggle(_ item: ScratchItem) {
        let target = item.id
        let predicate = #Predicate<StoredScratchItem> { $0.id == target }
        var descriptor = FetchDescriptor<StoredScratchItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            model.isChecked.toggle()
            try? context.save()
            refresh()
        }
    }

    func delete(_ item: ScratchItem) {
        let target = item.id
        let predicate = #Predicate<StoredScratchItem> { $0.id == target }
        var descriptor = FetchDescriptor<StoredScratchItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let model = try? context.fetch(descriptor).first {
            context.delete(model)
            try? context.save()
            refresh()
        }
    }

    func clearChecked() {
        let predicate = #Predicate<StoredScratchItem> { $0.isChecked == true }
        try? context.delete(model: StoredScratchItem.self, where: predicate)
        try? context.save()
        refresh()
    }

    func clearAll() {
        try? context.delete(model: StoredScratchItem.self)
        try? context.save()
        refresh()
    }

    var hasChecked: Bool { items.contains { $0.isChecked } }
}
