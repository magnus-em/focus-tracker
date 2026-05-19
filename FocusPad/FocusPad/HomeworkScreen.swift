import SwiftUI
import SwiftData
import FocusCore

struct HomeworkScreen: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settings: PadSettings
    @Query(sort: \StoredHomework.date, order: .reverse) private var items: [StoredHomework]
    @State private var showAdd = false
    @State private var showStat110 = false
    @State private var prefill: AddHomeworkSheet.Prefill? = nil
    @State private var searchText = ""

    private var todayCount: Int {
        let cal = Calendar.current
        return items.filter { cal.isDateInToday($0.date) }.count
    }

    private var filteredItems: [StoredHomework] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { h in
            h.title.lowercased().contains(q)
                || h.source.lowercased().contains(q)
                || h.notes.lowercased().contains(q)
        }
    }

    /// Homework items whose review is due (now or earlier). Sorted by
    /// most-overdue first so the top of the queue is the most stale.
    private var reviewDueItems: [StoredHomework] {
        items.filter { $0.asValue.isDueForReview }
            .sorted { ($0.asValue.reviewDueDate ?? .distantFuture) < ($1.asValue.reviewDueDate ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No homework problems",
                    systemImage: "book",
                    description: Text("Quick capture for problems you're working through.")
                )
            } else {
                List {
                    Section {
                        HomeworkTodayHeader(todayCount: todayCount, goal: settings.homeworkDailyGoal)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    if !reviewDueItems.isEmpty {
                        Section {
                            ForEach(reviewDueItems) { h in
                                NavigationLink {
                                    HomeworkDetailScreen(homework: h)
                                } label: {
                                    HomeworkRow(item: h, showReviewDue: true)
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("REVIEW DUE (\(reviewDueItems.count))")
                            }
                            .foregroundStyle(Color(red: 0.62, green: 0.45, blue: 0.92))
                        }
                    }
                    Section {
                        ForEach(filteredItems) { h in
                            NavigationLink {
                                HomeworkDetailScreen(homework: h)
                            } label: {
                                HomeworkRow(item: h)
                            }
                        }
                        .onDelete(perform: delete)
                    } header: {
                        Text("ALL")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Homework")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search homework")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Haptics.tap(); showStat110 = true
                    } label: { Label("Browse Stat 110", systemImage: "books.vertical") }
                    Button {
                        Haptics.tap(); prefill = nil; showAdd = true
                    } label: { Label("Add manually", systemImage: "square.and.pencil") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddHomeworkSheet(prefill: prefill)
        }
        .sheet(isPresented: $showStat110) {
            Stat110PickerSheet(completedIDs: completedCatalogIDs) { picked in
                showStat110 = false
                prefill = AddHomeworkSheet.Prefill(
                    title: picked.title,
                    source: picked.sourceLabel,
                    catalogID: picked.id
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    showAdd = true
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var completedCatalogIDs: Set<String> {
        Set(items.compactMap { $0.catalogID })
    }

    private func delete(at offsets: IndexSet) {
        let arr = filteredItems
        for i in offsets { context.delete(arr[i]) }
        try? context.save()
    }
}

private struct HomeworkTodayHeader: View {
    let todayCount: Int
    let goal: Int

    private var pct: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(todayCount) / Double(goal))
    }

    private var purple: Color { Color(red: 0.62, green: 0.45, blue: 0.92) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                if goal > 0 {
                    Text("\(todayCount)/\(goal)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(todayCount >= goal ? Color.green : purple)
                    + Text(" problems")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(todayCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(purple)
                    + Text(" problems")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            if goal > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(purple.opacity(0.12))
                        Capsule()
                            .fill(todayCount >= goal ? Color.green : purple)
                            .frame(width: g.size.width * CGFloat(pct))
                            .animation(.spring(response: 0.5), value: pct)
                    }
                }
                .frame(height: 8)
                if todayCount >= goal {
                    Text("Goal hit. Bonus problems welcome.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Text("\(goal - todayCount) to hit goal")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(purple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(purple.opacity(0.18), lineWidth: 1))
    }
}

private struct HomeworkRow: View {
    let item: StoredHomework
    var showReviewDue: Bool = false

    private var purple: Color { Color(red: 0.62, green: 0.45, blue: 0.92) }

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
                            .lineLimit(1)
                    }
                    if item.usedAI {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        HStack(spacing: 2) {
                            Image(systemName: "sparkles").font(.caption2)
                            Text("AI").font(.caption)
                        }.foregroundStyle(.orange)
                    }
                    if item.needsReview {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.caption2)
                            Text("Review").font(.caption)
                        }.foregroundStyle(purple)
                    }
                }
            }
            Spacer()
            if showReviewDue, let due = item.asValue.reviewDueDate {
                Text(due, style: .relative)
                    .font(.caption2).foregroundStyle(purple)
            } else {
                Text(item.date, style: .date)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddHomeworkSheet: View {
    struct Prefill: Equatable {
        var title: String = ""
        var source: String = ""
        var catalogID: String? = nil
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let prefill: Prefill?

    @State private var title: String
    @State private var source: String
    @State private var url = ""
    @State private var difficulty: ProblemDifficulty = .medium
    @State private var confidence: Confidence = .solid
    @State private var usedAI = false
    @State private var needsReview = false
    @State private var notes = ""

    init(prefill: Prefill? = nil) {
        self.prefill = prefill
        _title = State(initialValue: prefill?.title ?? "")
        _source = State(initialValue: prefill?.source ?? "")
    }

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
                Section {
                    Toggle("Mark for review", isOn: $needsReview)
                } footer: {
                    Text("Adds this to the homework review queue (~1 day out, sooner than the confidence-based default).")
                        .font(.caption)
                }
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
            url: url.trimmingCharacters(in: .whitespaces),
            catalogID: prefill?.catalogID,
            needsReview: needsReview
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
            Section {
                Toggle("Mark for review", isOn: $homework.needsReview)
            } footer: {
                if let due = homework.asValue.reviewDueDate {
                    Text("Review due: \(due, style: .date)").font(.caption)
                } else {
                    Text("No review scheduled. Toggle on or lower confidence to schedule.").font(.caption)
                }
            }
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
        .onChange(of: homework.needsReview) { _, _ in try? context.save() }
    }
}
