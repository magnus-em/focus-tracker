import SwiftUI
import SwiftData
import FocusCore

struct HomeworkScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredHomework.date, order: .reverse) private var items: [StoredHomework]
    @State private var showAdd = false

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No homework problems",
                    systemImage: "book",
                    description: Text("Quick capture for side problems to revisit later.")
                )
            } else {
                List {
                    ForEach(items) { h in
                        NavigationLink {
                            HomeworkDetailScreen(homework: h)
                        } label: {
                            HomeworkRow(item: h)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Homework")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddHomeworkSheet() }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
    }
}

private struct HomeworkRow: View {
    let item: StoredHomework
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(item.confidence.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Homework" : item.title)
                    .font(.body).lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.difficulty.rawValue)
                        .font(.caption).foregroundStyle(item.difficulty.color)
                    if !item.source.isEmpty {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        Text(item.source).font(.caption).foregroundStyle(.secondary)
                    }
                    if item.usedAI {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        HStack(spacing: 2) {
                            Image(systemName: "sparkles").font(.caption2)
                            Text("AI").font(.caption)
                        }.foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Text(item.date, style: .date)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct AddHomeworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title = ""
    @State private var source = ""
    @State private var url = ""
    @State private var difficulty: ProblemDifficulty = .medium
    @State private var confidence: Confidence = .solid
    @State private var usedAI = false
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Problem name", text: $title) }
                Section("Difficulty") {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(ProblemDifficulty.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Section("Confidence") {
                    Picker("Confidence", selection: $confidence) {
                        ForEach(Confidence.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Section { Toggle("Used AI help", isOn: $usedAI) }
                Section("Source (optional)") { TextField("e.g. textbook, problem set", text: $source) }
                Section("URL (optional)") {
                    TextField("https://…", text: $url)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("Notes (optional)") {
                    TextField("", text: $notes, axis: .vertical).lineLimit(3...)
                }
            }
            .navigationTitle("Log Homework")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let item = HomeworkProblem(
            title: title.trimmingCharacters(in: .whitespaces),
            source: source, difficulty: difficulty, confidence: confidence,
            usedAI: usedAI, notes: notes.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespaces)
        )
        context.insert(StoredHomework(value: item))
        try? context.save()
        dismiss()
    }
}

struct HomeworkDetailScreen: View {
    @Bindable var homework: StoredHomework
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Title") { TextField("Title", text: $homework.title) }
            Section("Difficulty") {
                Picker("Difficulty", selection: $homework.difficultyRaw) {
                    ForEach(ProblemDifficulty.allCases, id: \.self) {
                        Text($0.rawValue).tag($0.rawValue)
                    }
                }.pickerStyle(.segmented)
            }
            Section("Confidence") {
                Picker("Confidence", selection: $homework.confidenceRaw) {
                    ForEach(Confidence.allCases, id: \.self) {
                        Text($0.rawValue).tag($0.rawValue)
                    }
                }.pickerStyle(.segmented)
            }
            Section { Toggle("Used AI help", isOn: $homework.usedAI) }
            Section("Source") { TextField("Source", text: $homework.source) }
            Section("URL") {
                TextField("https://…", text: $homework.urlString)
                    .textInputAutocapitalization(.never).keyboardType(.URL)
                if let u = URL(string: homework.urlString), !homework.urlString.isEmpty {
                    Link(destination: u) { Label("Open", systemImage: "arrow.up.right.square") }
                }
            }
            Section("Notes") {
                TextField("", text: $homework.notes, axis: .vertical).lineLimit(3...)
            }
            Section("Metadata") {
                HStack {
                    Text("Logged")
                    Spacer()
                    Text(homework.date, style: .date).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(role: .destructive) {
                    context.delete(homework)
                    try? context.save()
                    dismiss()
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .navigationTitle(homework.title.isEmpty ? "Homework" : homework.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: homework.title) { _, _ in try? context.save() }
        .onChange(of: homework.source) { _, _ in try? context.save() }
        .onChange(of: homework.urlString) { _, _ in try? context.save() }
        .onChange(of: homework.notes) { _, _ in try? context.save() }
        .onChange(of: homework.difficultyRaw) { _, _ in try? context.save() }
        .onChange(of: homework.confidenceRaw) { _, _ in try? context.save() }
        .onChange(of: homework.usedAI) { _, _ in try? context.save() }
    }
}
