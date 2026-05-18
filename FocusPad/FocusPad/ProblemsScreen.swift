import SwiftUI
import SwiftData
import FocusCore

struct ProblemsScreen: View {
    @EnvironmentObject var settings: PadSettings
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredProblem.date, order: .reverse) private var problems: [StoredProblem]

    @State private var showAdd = false
    @State private var filterDomain: ProblemDomain? = nil
    @State private var showReviewOnly = false

    var body: some View {
        VStack(spacing: 0) {
            goalCards
            filterBar
            list
        }
        .navigationTitle("Problems")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddProblemSheet() }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var todayCount: (quant: Int, swe: Int) {
        let cal = Calendar.current
        let today = problems.filter { cal.isDateInToday($0.date) }
        return (today.filter { $0.domain == .quant }.count,
                today.filter { $0.domain == .swe }.count)
    }

    private var weekCount: (quant: Int, swe: Int) {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        let week = problems.filter { $0.date >= start }
        return (week.filter { $0.domain == .quant }.count,
                week.filter { $0.domain == .swe }.count)
    }

    private var goalCards: some View {
        let t = todayCount, w = weekCount
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                goalCard(domain: .quant, count: t.quant, goal: settings.quantGoal,
                         weekCount: w.quant, weekGoal: settings.quantWeeklyGoal)
                goalCard(domain: .swe, count: t.swe, goal: settings.sweGoal,
                         weekCount: w.swe, weekGoal: settings.sweWeeklyGoal)
                if dueForReview.count > 0 {
                    NavigationLink {
                        ReviewQueueScreen(items: dueForReview)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                Text("REVIEW").font(.system(size: 10, weight: .bold)).tracking(0.8)
                            }
                            .foregroundStyle(.orange)
                            Text("\(dueForReview.count)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("due now").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 130, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: PadTheme.smallCardRadius)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(PadTheme.pad)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var dueForReview: [StoredProblem] {
        problems.filter { $0.asValue.isDueForReview }
    }

    private func goalCard(domain: ProblemDomain, count: Int, goal: Int,
                          weekCount: Int, weekGoal: Int) -> some View {
        let dailyPct = goal > 0 ? min(Double(count) / Double(goal), 1.0) : 0
        let weekPct = weekGoal > 0 ? min(Double(weekCount) / Double(weekGoal), 1.0) : 0
        return Button {
            filterDomain = (filterDomain == domain ? nil : domain)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(domain.color).frame(width: 8, height: 8)
                    Text(domain.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .foregroundStyle(domain.color)
                }
                Text("\(count)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("today · \(goal > 0 ? "\(goal) goal" : "no goal")")
                    .font(.caption).foregroundStyle(.secondary)

                ProgressBar(pct: dailyPct, color: domain.color)
                HStack {
                    Text("Week").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(weekCount)/\(weekGoal)").font(.caption2).foregroundStyle(.secondary)
                }
                ProgressBar(pct: weekPct, color: domain.color.opacity(0.7))
            }
            .frame(width: 180, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: PadTheme.smallCardRadius)
                    .fill(domain.color.opacity(filterDomain == domain ? 0.18 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PadTheme.smallCardRadius)
                    .stroke(filterDomain == domain ? domain.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var filterBar: some View {
        HStack {
            if let f = filterDomain {
                HStack(spacing: 4) {
                    Text("Showing \(f.rawValue)").font(.caption).foregroundStyle(.secondary)
                    Button { filterDomain = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.gray.opacity(0.15)))
            }
            Spacer()
            Toggle(isOn: $showReviewOnly) {
                Text("Review only").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, PadTheme.pad)
        .padding(.bottom, 8)
    }

    private var filteredProblems: [StoredProblem] {
        var arr = problems
        if let f = filterDomain { arr = arr.filter { $0.domain == f } }
        if showReviewOnly { arr = arr.filter { $0.asValue.isDueForReview } }
        return arr
    }

    private var list: some View {
        Group {
            if filteredProblems.isEmpty {
                ContentUnavailableView(
                    "No problems",
                    systemImage: "checkmark.circle",
                    description: Text("Tap + to log your first problem.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredProblems) { p in
                        NavigationLink {
                            ProblemDetailScreen(problem: p)
                        } label: {
                            ProblemRow(problem: p)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let arr = filteredProblems
        for i in offsets { context.delete(arr[i]) }
        try? context.save()
    }
}

struct ProgressBar: View {
    let pct: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.18))
                RoundedRectangle(cornerRadius: 3).fill(color)
                    .frame(width: max(4, geo.size.width * pct))
            }
        }
        .frame(height: 6)
    }
}

private struct ProblemRow: View {
    let problem: StoredProblem
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(problem.confidence.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.title.isEmpty ? "Problem" : problem.title)
                    .font(.body).lineLimit(1)
                HStack(spacing: 4) {
                    Text(problem.domain.rawValue)
                        .font(.caption).foregroundStyle(problem.domain.color)
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text(problem.difficulty.rawValue)
                        .font(.caption).foregroundStyle(problem.difficulty.color)
                    if !problem.source.isEmpty {
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        Text(problem.source).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if problem.asValue.isDueForReview {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Problem Sheet

struct AddProblemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settings: PadSettings

    @State private var title = ""
    @State private var domain: ProblemDomain = .quant
    @State private var selectedCategories: Set<String> = []
    @State private var difficulty: ProblemDifficulty = .medium
    @State private var confidence: Confidence = .solid
    @State private var source = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var usedAI = false
    @State private var solveMinutes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Problem name", text: $title)
                }
                Section("Domain") {
                    Picker("Domain", selection: $domain) {
                        ForEach(ProblemDomain.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }.pickerStyle(.segmented)
                }
                Section("Categories") {
                    FlowLayout(spacing: 6) {
                        ForEach(domain.categories, id: \.self) { cat in
                            let sel = selectedCategories.contains(cat)
                            Button(cat) {
                                if sel { selectedCategories.remove(cat) }
                                else { selectedCategories.insert(cat) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(sel ? domain.color.opacity(0.18) : Color(.tertiarySystemFill))
                            .foregroundStyle(sel ? domain.color : .primary)
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
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
                Section("Source (optional)") {
                    if !settings.problemSources.isEmpty {
                        Picker("Source", selection: $source) {
                            Text("None").tag("")
                            ForEach(settings.problemSources, id: \.self) { src in
                                Text(src).tag(src)
                            }
                        }
                    } else {
                        TextField("e.g. LeetCode, QuantGuide", text: $source)
                    }
                }
                Section("URL (optional)") {
                    TextField("https://…", text: $url)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("Solve time (optional)") {
                    TextField("Minutes", text: $solveMinutes)
                        .keyboardType(.numberPad)
                }
                Section("Notes") {
                    TextField("Insight, mistake, retry plan…", text: $notes, axis: .vertical).lineLimit(3...)
                }
                Section { Toggle("Used AI help", isOn: $usedAI) }
            }
            .navigationTitle("Log Problem")
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
        let entry = ProblemEntry(
            title: title.trimmingCharacters(in: .whitespaces),
            domain: domain,
            categories: Array(selectedCategories),
            difficulty: difficulty,
            source: source,
            needsReview: usedAI,
            confidence: confidence,
            notes: notes.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespaces),
            solveMinutes: Int(solveMinutes)
        )
        context.insert(StoredProblem(value: entry))
        try? context.save()
        dismiss()
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0; rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
