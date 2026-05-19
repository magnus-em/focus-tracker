import SwiftUI
import FocusCore

// MARK: - Main view

struct ProblemsView: View {
    @ObservedObject var store: ProblemStore
    @ObservedObject var homeworkStore: HomeworkStore
    @ObservedObject var settings: AppSettings

    @State private var showLog = false
    @State private var selectedProblem: ProblemEntry? = nil
    @State private var reviewExpanded = true
    @State private var homeworkExpanded = false
    @State private var showHomeworkLog = false
    @State private var editingHomework: HomeworkProblem? = nil

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 12) {
                    if settings.interviewDate != nil {
                        countdownCard
                    }

                    goalSection

                    if !store.needsReviewItems.isEmpty || !store.dueForReview.isEmpty {
                        reviewCard
                    }

                    progressCard

                    logButton

                    Divider().padding(.horizontal, 8)

                    recentSection

                    homeworkSection
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 18)
            }

            if showLog {
                LogProblemOverlay(store: store, settings: settings, isShowing: $showLog)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    .zIndex(1)
            }

            if showHomeworkLog {
                HomeworkLogOverlay(store: homeworkStore, settings: settings, isShowing: $showHomeworkLog)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    .zIndex(3)
            }

            if let editing = editingHomework {
                HomeworkEditOverlay(
                    store: homeworkStore, settings: settings, item: editing,
                    isShowing: Binding(get: { editingHomework != nil },
                                       set: { if !$0 { editingHomework = nil } })
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                .zIndex(4)
            }

            if selectedProblem != nil {
                ProblemDetailView(
                    store: store,
                    problem: selectedProblem!,
                    isShowing: Binding(
                        get: { selectedProblem != nil },
                        set: { if !$0 { selectedProblem = nil } }
                    )
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                .zIndex(2)
            }
        }
    }

    // MARK: - Homework (side system)

    private var homeworkSection: some View {
        let items = homeworkStore.byNewest
        let cal = Calendar.current
        let todayCount = items.filter { cal.isDateInToday($0.date) }.count
        let goal = settings.homeworkDailyGoal
        let purple = Color(red: 0.62, green: 0.45, blue: 0.92)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { homeworkExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book")
                        .font(.system(size: 10))
                        .foregroundStyle(purple)
                    Text("HOMEWORK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    if goal > 0 {
                        Text("\(todayCount)/\(goal) today")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(todayCount >= goal ? Color.green : purple)
                    } else {
                        Text("\(todayCount) today")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text("· \(items.count) total")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button { showHomeworkLog = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    Image(systemName: homeworkExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if homeworkExpanded {
                Divider().padding(.horizontal, 10)
                if items.isEmpty {
                    Text("No homework problems logged. Use this for side problems you want to revisit — separate from interview tracking.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HomeworkRow(item: item, onTap: { editingHomework = item })
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(8)
    }

    // MARK: - Interview countdown

    private var countdownCard: some View {
        let date = settings.interviewDate!
        let days = max(0, Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)).day ?? 0)
        let totalGoal = settings.quantGoal + settings.sweGoal
        let pace: Double = (totalGoal > 0 && days > 0)
            ? Double(max(0, totalGoal - store.totalCount)) / Double(days)
            : 0

        let urgent = days <= 30
        let accent = urgent ? Color.orange : Color(red: 0.27, green: 0.62, blue: 0.83)

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("INTERVIEW IN")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.tertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(days)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                    Text("days")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if pace > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f / day", pace))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("problems to goal")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else if totalGoal == 0 {
                Text("Set a goal in Settings")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                    Text("Goal reached!")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(accent.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Goal bars

    private var goalSection: some View {
        VStack(spacing: 8) {
            ForEach(ProblemDomain.allCases, id: \.self) { domain in
                GoalBar(
                    domain: domain,
                    count: store.count(for: domain),
                    goal: domain == .quant ? settings.quantGoal : settings.sweGoal
                )
            }
        }
    }

    // MARK: - Review queue

    private var reviewCard: some View {
        let aiItems = store.needsReviewItems
        let dueItems = store.dueForReview.filter { !$0.needsReview } // avoid double-counting
        let total = aiItems.count + dueItems.count

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { reviewExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("REVIEW QUEUE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.orange)
                    Text("\(total)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange)
                        .clipShape(Capsule())
                    if !dueItems.isEmpty {
                        Text("\(dueItems.count) spaced")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: reviewExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if reviewExpanded {
                Divider().padding(.horizontal, 10)
                VStack(spacing: 0) {
                    ForEach((aiItems + dueItems).prefix(6)) { item in
                        ReviewRow(item: item, store: store) { selectedProblem = item }
                    }
                    if total > 6 {
                        Text("+ \(total - 6) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                    }
                }
            }
        }
        .background(Color.orange.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Progress card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LAST 7 DAYS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                let streak = store.problemStreak
                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(streak)d streak")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            let days = store.dailyCounts(days: 7)
            let maxCount = max(1, days.map { $0.count }.max() ?? 1)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days, id: \.date) { day in
                    VStack(spacing: 2) {
                        if day.count > 0 {
                            Text("\(day.count)")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(" ").font(.system(size: 8))
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.count > 0
                                  ? Color(red: 0.27, green: 0.62, blue: 0.83).opacity(0.7)
                                  : Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, 36 * CGFloat(day.count) / CGFloat(maxCount)))
                        Text(weekdayLetter(day.date))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)

            HStack(spacing: 0) {
                let thisWeek = store.thisWeekCount
                let lastWeek = store.lastWeekCount
                let delta    = thisWeek - lastWeek
                let rate     = store.cleanSolveRate

                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(thisWeek)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        if lastWeek > 0 {
                            Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(delta >= 0 ? .green : .red)
                        }
                    }
                    Text("this week").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 26)

                VStack(spacing: 1) {
                    Text(String(format: "%.0f%%", rate * 100))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(rate >= 0.8 ? .green : rate >= 0.5 ? Color.orange : .red)
                    Text("clean").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 26)

                HStack(spacing: 6) {
                    ForEach(store.countByDifficulty(), id: \.difficulty) { item in
                        VStack(spacing: 1) {
                            Text("\(item.count)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(item.difficulty.color)
                            Text(String(item.difficulty.rawValue.prefix(1)))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            // Weak areas
            let weak = store.weakestCategories(limit: 3)
            if !weak.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("FOCUS ON")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.tertiary)
                    ForEach(weak, id: \.category) { item in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(scoreColor(item.avgScore))
                                .frame(width: 6, height: 6)
                            Text(item.category)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.count) logged")
                                .font(.system(size: 9))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.04)))
    }

    private func scoreColor(_ score: Double) -> Color {
        if score < 0.7 { return Color(red: 0.96, green: 0.36, blue: 0.36) }
        if score < 1.4 { return Color(red: 0.98, green: 0.70, blue: 0.18) }
        return Color(red: 0.22, green: 0.72, blue: 0.45)
    }

    // MARK: - Log button

    private var logButton: some View {
        Button { showLog = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Log a Problem")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [ProblemDomain.quant.color, ProblemDomain.swe.color],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent list

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            let days = store.byDay().prefix(7)
            if days.isEmpty {
                Text("No problems logged yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(days), id: \.date) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dayLabel(group.date))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 1)
                        ForEach(group.problems.prefix(8)) { problem in
                            Button { selectedProblem = problem } label: {
                                ProblemRow(problem: problem)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let idx = Calendar.current.component(.weekday, from: date) - 1
        return ["S","M","T","W","T","F","S"][idx]
    }
}

// MARK: - Goal progress bar

private struct GoalBar: View {
    let domain: ProblemDomain
    let count: Int
    let goal: Int

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(count) / Double(goal))
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: domain.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(domain.color)
                    Text(domain.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                if goal > 0 {
                    Text("\(count) / \(goal)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(count >= goal ? domain.color : .secondary)
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(domain.color.opacity(0.8))
                        .frame(width: 32, alignment: .trailing)
                } else {
                    Text("\(count)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(domain.color)
                    Text("problems")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            if goal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(domain.color.opacity(0.1))
                        Capsule().fill(domain.color.opacity(0.85))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 5)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)
            }
        }
        .padding(10)
        .background(domain.color.opacity(0.05))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(domain.color.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Review queue row

private struct ReviewRow: View {
    let item: ProblemEntry
    @ObservedObject var store: ProblemStore
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? item.categories.joined(separator: " · ") : item.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if !item.source.isEmpty {
                                Text(item.source)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text("·").font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            Text(item.difficulty.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(item.difficulty.color)
                            Text("·").font(.system(size: 10)).foregroundStyle(.tertiary)
                            Text(item.domain.rawValue)
                                .font(.system(size: 10))
                                .foregroundStyle(item.domain.color)
                        }
                    }
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { store.clearReview(id: item.id) }
            } label: {
                Text("Done")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
    }
}

// MARK: - Recent problem row

private struct ProblemRow: View {
    let problem: ProblemEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(problem.confidence.color)
                .frame(width: 6, height: 6)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(problem.title.isEmpty ? problem.categories.joined(separator: " · ") : problem.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !problem.source.isEmpty {
                        Text(problem.source)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("·").font(.system(size: 9)).foregroundStyle(.quaternary)
                    }
                    Text(problem.categories.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if problem.needsReview {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            Text(problem.difficulty.rawValue)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(problem.difficulty.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(problem.difficulty.color.opacity(0.12))
                .cornerRadius(4)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Log problem overlay

struct LogProblemOverlay: View {
    @ObservedObject var store: ProblemStore
    @ObservedObject var settings: AppSettings
    @Binding var isShowing: Bool

    @State private var title: String = ""
    @State private var urlText: String = ""
    @State private var selectedSource: String = ""
    @State private var selectedDomain: ProblemDomain = .quant
    @State private var selectedCategories: Set<String> = []
    @State private var selectedDifficulty: ProblemDifficulty = .medium
    @State private var selectedSolveMinutes: Int? = nil
    @State private var selectedConfidence: Confidence = .solid
    @State private var usedAIHelp = false
    @FocusState private var titleFocused: Bool

    private let solveOptions: [(String, Int?)] = [
        ("—", nil), ("< 5m", 3), ("5–15m", 10), ("15–30m", 22), ("30m+", 45)
    ]

    private var canLog: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasCats  = !selectedCategories.isEmpty
        let hasSource = settings.problemSources.isEmpty || !selectedSource.isEmpty
        return hasTitle && hasCats && hasSource
    }

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("LOG A PROBLEM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { isShowing = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        // Title — required
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text("NAME")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(.secondary)
                                Text("required")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            TextField("e.g. Two Sum, Coin Flip Variance", text: $title)
                                .font(.system(size: 13, weight: .medium))
                                .textFieldStyle(.plain)
                                .focused($titleFocused)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.07))
                                .cornerRadius(8)
                                .onSubmit { if canLog { logAndClose() } }
                        }

                        // Source — required if sources configured
                        if !settings.problemSources.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 4) {
                                    Text("SOURCE")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1)
                                        .foregroundStyle(.secondary)
                                    Text("required")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(settings.problemSources, id: \.self) { src in
                                            let sel = selectedSource == src
                                            Button(src) { selectedSource = sel ? "" : src }
                                                .font(.system(size: 11, weight: .medium))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(sel ? Color(red: 0.27, green: 0.62, blue: 0.83).opacity(0.18) : Color.secondary.opacity(0.07))
                                                .foregroundStyle(sel ? Color(red: 0.27, green: 0.62, blue: 0.83) : Color.secondary)
                                                .cornerRadius(8)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(sel ? Color(red: 0.27, green: 0.62, blue: 0.83).opacity(0.4) : Color.clear, lineWidth: 1)
                                                )
                                                .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        // Domain
                        HStack(spacing: 8) {
                            ForEach(ProblemDomain.allCases, id: \.self) { domain in
                                let sel = selectedDomain == domain
                                Button {
                                    selectedDomain = domain
                                    selectedCategories = []
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: domain.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(domain.rawValue)
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundStyle(sel ? .white : domain.color)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(sel ? domain.color : domain.color.opacity(0.1))
                                    .cornerRadius(9)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Category — multi-select
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 4) {
                                Text("CATEGORY")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(.secondary)
                                Text("required")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            let cols = [GridItem(.adaptive(minimum: 90), spacing: 6)]
                            LazyVGrid(columns: cols, spacing: 6) {
                                ForEach(selectedDomain.categories, id: \.self) { cat in
                                    let sel = selectedCategories.contains(cat)
                                    Button(cat) {
                                        if sel { selectedCategories.remove(cat) }
                                        else   { selectedCategories.insert(cat) }
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity)
                                    .background(sel ? selectedDomain.color.opacity(0.18) : Color.secondary.opacity(0.07))
                                    .foregroundStyle(sel ? selectedDomain.color : Color.secondary)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(sel ? selectedDomain.color.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Difficulty
                        VStack(alignment: .leading, spacing: 7) {
                            Text("DIFFICULTY")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(ProblemDifficulty.allCases, id: \.self) { diff in
                                    let sel = selectedDifficulty == diff
                                    Button(diff.rawValue) { selectedDifficulty = diff }
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(sel ? diff.color.opacity(0.18) : Color.secondary.opacity(0.07))
                                        .foregroundStyle(sel ? diff.color : Color.secondary)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(sel ? diff.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
                                        )
                                        .buttonStyle(.plain)
                                }
                            }
                        }

                        // Solve time — optional
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 4) {
                                Text("SOLVE TIME")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(.secondary)
                                Text("optional")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.quaternary)
                            }
                            HStack(spacing: 5) {
                                ForEach(solveOptions, id: \.0) { label, value in
                                    let sel = selectedSolveMinutes == value
                                    Button(label) { selectedSolveMinutes = value }
                                        .font(.system(size: 10, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(sel ? Color(red: 0.27, green: 0.62, blue: 0.83).opacity(0.18) : Color.secondary.opacity(0.07))
                                        .foregroundStyle(sel ? Color(red: 0.27, green: 0.62, blue: 0.83) : Color.secondary)
                                        .cornerRadius(7)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .stroke(sel ? Color(red: 0.27, green: 0.62, blue: 0.83).opacity(0.4) : Color.clear, lineWidth: 1)
                                        )
                                        .buttonStyle(.plain)
                                }
                            }
                        }

                        // Confidence
                        VStack(alignment: .leading, spacing: 7) {
                            Text("CONFIDENCE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                ForEach(Confidence.allCases, id: \.self) { conf in
                                    let sel = selectedConfidence == conf
                                    Button(conf.rawValue) { selectedConfidence = conf }
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(sel ? conf.color.opacity(0.18) : Color.secondary.opacity(0.07))
                                        .foregroundStyle(sel ? conf.color : Color.secondary)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(sel ? conf.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
                                        )
                                        .buttonStyle(.plain)
                                }
                            }
                        }

                        // URL — optional
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text("LINK")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(.secondary)
                                Text("optional")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.quaternary)
                            }
                            TextField("https://leetcode.com/problems/…", text: $urlText)
                                .font(.system(size: 11))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.secondary.opacity(0.07))
                                .cornerRadius(7)
                        }

                        // AI help
                        Button { usedAIHelp.toggle() } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Used AI assistance")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(usedAIHelp ? Color.orange : .primary)
                                    Text("Adds to review queue — redo this one yourself")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Image(systemName: usedAIHelp ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 18))
                                    .foregroundStyle(usedAIHelp ? Color.orange : Color.secondary.opacity(0.4))
                            }
                            .padding(10)
                            .background(usedAIHelp ? Color.orange.opacity(0.08) : Color.secondary.opacity(0.05))
                            .cornerRadius(9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(usedAIHelp ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Log
                        Button {
                            if canLog { logAndClose() }
                        } label: {
                            Text("Log Problem")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(canLog ? .white : Color.secondary.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(canLog ? selectedDomain.color : Color.secondary.opacity(0.1))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canLog)
                    }
                    .padding(18)
                }
            }
        }
        .onAppear { titleFocused = true }
    }

    private func logAndClose() {
        store.add(ProblemEntry(
            title: title.trimmingCharacters(in: .whitespaces),
            domain: selectedDomain,
            categories: Array(selectedCategories),
            difficulty: selectedDifficulty,
            source: selectedSource,
            needsReview: usedAIHelp,
            confidence: selectedConfidence,
            notes: "",
            url: urlText.trimmingCharacters(in: .whitespaces),
            solveMinutes: selectedSolveMinutes
        ))
        isShowing = false
    }
}

// MARK: - Homework row

private struct HomeworkRow: View {
    let item: HomeworkProblem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(item.confidence.color)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.isEmpty ? "Homework problem" : item.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if !item.source.isEmpty {
                            Text(item.source)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text("·").font(.system(size: 9)).foregroundStyle(.quaternary)
                        }
                        Text(item.difficulty.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(item.difficulty.color)
                        if item.usedAI {
                            Text("·").font(.system(size: 9)).foregroundStyle(.quaternary)
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles").font(.system(size: 8))
                                Text("AI").font(.system(size: 9))
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
                Text(shortDateStr(item.date))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortDateStr(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today" }
        if cal.isDateInYesterday(d) { return "yest" }
        let f = DateFormatter(); f.dateFormat = "M/d"
        return f.string(from: d)
    }
}

// MARK: - Homework log/edit overlays (lightweight)

private struct HomeworkFields: View {
    @Binding var title: String
    @Binding var source: String
    @Binding var url: String
    @Binding var difficulty: ProblemDifficulty
    @Binding var confidence: Confidence
    @Binding var usedAI: Bool
    @Binding var notes: String
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NAME").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                TextField("Problem title", text: $title)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.07))
                    .cornerRadius(7)
            }

            if !settings.problemSources.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SOURCE").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(["Homework"] + settings.problemSources, id: \.self) { src in
                                let sel = source == src
                                Button(src) { source = sel ? "" : src }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(sel ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.07))
                                    .foregroundStyle(sel ? .primary : .secondary)
                                    .cornerRadius(7)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("DIFFICULTY").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(ProblemDifficulty.allCases, id: \.self) { d in
                        let sel = difficulty == d
                        Button(d.rawValue) { difficulty = d }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(sel ? d.color.opacity(0.15) : Color.secondary.opacity(0.07))
                            .foregroundStyle(sel ? d.color : .secondary)
                            .cornerRadius(7).buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("CONFIDENCE").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Confidence.allCases, id: \.self) { c in
                        let sel = confidence == c
                        Button(c.rawValue) { confidence = c }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(sel ? c.color.opacity(0.15) : Color.secondary.opacity(0.07))
                            .foregroundStyle(sel ? c.color : .secondary)
                            .cornerRadius(7).buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Toggle(isOn: $usedAI) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text("Used AI").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(usedAI ? .orange : .secondary)
                }
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("URL").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                TextField("https://…", text: $url)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.07))
                    .cornerRadius(7)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("NOTES").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.secondary.opacity(0.07))
                    .cornerRadius(7)
            }
        }
    }
}

struct HomeworkLogOverlay: View {
    @ObservedObject var store: HomeworkStore
    @ObservedObject var settings: AppSettings
    @Binding var isShowing: Bool

    @State private var title = ""
    @State private var source = "Homework"
    @State private var url = ""
    @State private var difficulty: ProblemDifficulty = .medium
    @State private var confidence: Confidence = .solid
    @State private var usedAI = false
    @State private var notes = ""

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("LOG HOMEWORK PROBLEM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Button { isShowing = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16)).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                Divider()
                ScrollView {
                    HomeworkFields(
                        title: $title, source: $source, url: $url,
                        difficulty: $difficulty, confidence: $confidence,
                        usedAI: $usedAI, notes: $notes, settings: settings
                    )
                    .padding(20)
                }
                Divider()
                Button {
                    let t = title.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    store.add(HomeworkProblem(
                        title: t, source: source,
                        difficulty: difficulty, confidence: confidence,
                        usedAI: usedAI,
                        notes: notes.trimmingCharacters(in: .whitespaces),
                        url: url.trimmingCharacters(in: .whitespaces)
                    ))
                    isShowing = false
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(title.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.secondary.opacity(0.2)
                                    : Color(red: 0.27, green: 0.62, blue: 0.83))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(16)
            }
        }
    }
}

struct HomeworkEditOverlay: View {
    @ObservedObject var store: HomeworkStore
    @ObservedObject var settings: AppSettings
    let item: HomeworkProblem
    @Binding var isShowing: Bool

    @State private var title = ""
    @State private var source = ""
    @State private var url = ""
    @State private var difficulty: ProblemDifficulty = .medium
    @State private var confidence: Confidence = .solid
    @State private var usedAI = false
    @State private var notes = ""

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("HOMEWORK PROBLEM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Button { isShowing = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16)).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
                Divider()
                ScrollView {
                    HomeworkFields(
                        title: $title, source: $source, url: $url,
                        difficulty: $difficulty, confidence: $confidence,
                        usedAI: $usedAI, notes: $notes, settings: settings
                    )
                    .padding(20)
                }
                Divider()
                HStack(spacing: 8) {
                    Button {
                        store.delete(id: item.id)
                        isShowing = false
                    } label: {
                        Text("Delete")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }.buttonStyle(.plain)
                    Spacer()
                    Button {
                        var updated = item
                        updated.title = title.trimmingCharacters(in: .whitespaces)
                        updated.source = source
                        updated.url = url.trimmingCharacters(in: .whitespaces)
                        updated.difficulty = difficulty
                        updated.confidence = confidence
                        updated.usedAI = usedAI
                        updated.notes = notes.trimmingCharacters(in: .whitespaces)
                        store.update(updated)
                        isShowing = false
                    } label: {
                        Text("Save")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Color(red: 0.27, green: 0.62, blue: 0.83))
                            .cornerRadius(8)
                    }.buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .onAppear {
            title = item.title
            source = item.source
            url = item.url
            difficulty = item.difficulty
            confidence = item.confidence
            usedAI = item.usedAI
            notes = item.notes
        }
    }
}
