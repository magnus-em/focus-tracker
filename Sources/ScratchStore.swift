import Foundation

class ScratchStore: ObservableObject {
    @Published var items: [ScratchItem] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("LockIn")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("scratch.json")
        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        items.append(ScratchItem(text: trimmed))
        save()
    }

    func toggle(_ item: ScratchItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].isChecked.toggle()
        save()
    }

    func delete(_ item: ScratchItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearChecked() {
        items.removeAll { $0.isChecked }
        save()
    }

    func clearAll() {
        items = []
        save()
    }

    var hasChecked: Bool { items.contains { $0.isChecked } }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ScratchItem].self, from: data) {
            items = decoded
        }
    }
}
