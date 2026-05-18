import SwiftUI
import SwiftData
import FocusCore

struct ProblemDetailScreen: View {
    @Bindable var problem: StoredProblem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editingNotes = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $problem.title)
                    .font(.title3.weight(.semibold))
            }

            Section("Domain · Difficulty · Confidence") {
                HStack(spacing: 6) {
                    Tag(text: problem.domain.rawValue, color: problem.domain.color)
                    Tag(text: problem.difficulty.rawValue, color: problem.difficulty.color)
                    Tag(text: problem.confidence.rawValue, color: problem.confidence.color)
                }
                Picker("Difficulty", selection: $problem.difficultyRaw) {
                    ForEach(ProblemDifficulty.allCases, id: \.self) { d in
                        Text(d.rawValue).tag(d.rawValue)
                    }
                }
                Picker("Confidence", selection: $problem.confidenceRaw) {
                    ForEach(Confidence.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c.rawValue)
                    }
                }
            }

            if !problem.categories.isEmpty {
                Section("Categories") {
                    FlowLayout(spacing: 6) {
                        ForEach(problem.categories, id: \.self) { c in
                            Tag(text: c, color: problem.domain.color)
                        }
                    }
                }
            }

            Section("Metadata") {
                if !problem.source.isEmpty {
                    HStack { Text("Source"); Spacer(); Text(problem.source).foregroundStyle(.secondary) }
                }
                HStack {
                    Text("Logged")
                    Spacer()
                    Text(problem.date, style: .date).foregroundStyle(.secondary)
                }
                if let due = problem.asValue.reviewDueDate {
                    HStack {
                        Text("Review due")
                        Spacer()
                        Text(due, style: .date)
                            .foregroundStyle(problem.asValue.isDueForReview ? .orange : .secondary)
                    }
                }
            }

            Section("Notes") {
                TextField("Insight, mistake, retry plan…",
                          text: $problem.notes, axis: .vertical)
                    .lineLimit(3...)
            }

            if !problem.urlString.isEmpty, let url = URL(string: problem.urlString) {
                Section("Link") {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "link")
                            Text(problem.urlString).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }

            Section {
                Toggle("Needs review", isOn: $problem.needsReview)
                if problem.asValue.isDueForReview {
                    Button {
                        problem.needsReview = false
                        problem.date = Date()
                        try? context.save()
                    } label: {
                        Label("Mark Reviewed Today", systemImage: "checkmark.circle.fill")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    context.delete(problem)
                    try? context.save()
                    dismiss()
                } label: {
                    Label("Delete Problem", systemImage: "trash")
                }
            }
        }
        .navigationTitle(problem.title.isEmpty ? "Problem" : problem.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: problem.title) { _, _ in try? context.save() }
        .onChange(of: problem.notes) { _, _ in try? context.save() }
        .onChange(of: problem.difficultyRaw) { _, _ in try? context.save() }
        .onChange(of: problem.confidenceRaw) { _, _ in try? context.save() }
        .onChange(of: problem.needsReview) { _, _ in try? context.save() }
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

// MARK: - Review Queue

struct ReviewQueueScreen: View {
    let items: [StoredProblem]

    var body: some View {
        List {
            Section {
                ForEach(items) { p in
                    NavigationLink {
                        ProblemDetailScreen(problem: p)
                    } label: {
                        ReviewRow(problem: p)
                    }
                }
            } header: {
                Text("\(items.count) due now")
            } footer: {
                Text("Review cadence: 1 day for shaky/AI-flagged, 3 days for solid.")
            }
        }
        .navigationTitle("Review Queue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReviewRow: View {
    let problem: StoredProblem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.title.isEmpty ? "Problem" : problem.title)
                    .font(.body).lineLimit(1)
                HStack(spacing: 4) {
                    Text(problem.domain.rawValue).font(.caption).foregroundStyle(problem.domain.color)
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text("logged \(problem.date, style: .relative) ago")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Circle().fill(problem.confidence.color).frame(width: 8, height: 8)
        }
    }
}
