import Foundation
import Combine

/// Per-problem user-provided answer text. The catalog ships with short
/// paraphrased answers; this store lets the user paste the *full* answer
/// from their own copy of the Stat 110 solutions PDF on a per-problem
/// basis, and the answer reveal in Practice Mode prefers the override
/// when one is set.
///
/// Storage: a single JSON dictionary at
/// `~/Library/Application Support/Focus/answer_overrides.json`, keyed by
/// catalog ID. Atomic writes; no SwiftData / CloudKit overhead — these
/// are personal notes, not a synced surface (yet).
@MainActor
final class AnswerOverridesStore: ObservableObject {
    @Published private(set) var overrides: [String: String] = [:]

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Focus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("answer_overrides.json")
        load()
    }

    func override(for catalogID: String) -> String? {
        let value = overrides[catalogID]
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    func hasOverride(for catalogID: String) -> Bool {
        override(for: catalogID) != nil
    }

    func setOverride(_ text: String, for catalogID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            overrides.removeValue(forKey: catalogID)
        } else {
            overrides[catalogID] = text
        }
        save()
    }

    func clearOverride(for catalogID: String) {
        overrides.removeValue(forKey: catalogID)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            overrides = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(overrides) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
